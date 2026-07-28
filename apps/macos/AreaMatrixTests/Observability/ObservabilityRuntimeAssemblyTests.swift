@testable import AreaMatrix
import XCTest

final class ObservabilityRuntimeAssemblyTests: XCTestCase {
    @MainActor
    func testRepeatedStartInitializesCoreExactlyOnce() async throws {
        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }

        fixture.runtime.start()
        fixture.runtime.start()
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition {
            await core.initializeCallCount() == 1 && fixture.runtime.state == .running
        }
        XCTAssertTrue(didStart)

        fixture.runtime.start()
        await Task.yield()
        let initializeCallCount = await core.initializeCallCount()
        let initializedModes = await core.initializedModes()
        let startupCalls = await core.recordedStartupCalls()
        XCTAssertEqual(initializeCallCount, 1)
        XCTAssertEqual(initializedModes, [.standard])
        XCTAssertEqual(startupCalls, [.buildContext, .initialize])
        _ = await fixture.runtime.stop()
    }

    @MainActor
    func testConcurrentUpdatesAreSerializedInSubmissionOrder() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.blockFirstModeUpdate = true
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)

        let first = Task { try await fixture.runtime.update(.runtimeMode(.diagnostic)) }
        await core.waitUntilModeUpdateEntered()
        let second = Task { try await fixture.runtime.update(.runtimeMode(.developer)) }
        await Task.yield()
        let blockedUpdateModes = await core.updatedModes()
        XCTAssertEqual(blockedUpdateModes, [.diagnostic])

        await core.releaseModeUpdate()
        try await first.value
        try await second.value
        let completedUpdateModes = await core.updatedModes()
        let persistedMode = await fixture.hub.configurationSnapshot().mode
        XCTAssertEqual(completedUpdateModes, [.diagnostic, .developer])
        XCTAssertEqual(persistedMode, .developer)
        _ = await fixture.runtime.stop()
    }

    @MainActor
    func testConcurrentStopRunsStagesOnceReturnsSameReportAndRejectsNewMutations() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.suspendFlush = true
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)

        let firstStop = Task { await fixture.runtime.stop(deadline: .seconds(5)) }
        await core.waitUntilFlushEntered()
        let secondStop = Task { await fixture.runtime.stop(deadline: .seconds(10)) }
        do {
            try await fixture.runtime.update(.runtimeMode(.developer))
            XCTFail("A stopping runtime must reject new mutations")
        } catch {
            XCTAssertEqual(error as? ObservabilityRuntimeError, .notRunning)
        }

        await core.releaseFlush()
        let firstReport = await firstStop.value
        let secondReport = await secondStop.value
        let expectedStages: [ObservabilityStopReport.Stage] = [
            .acceptedMutations,
            .coreProducerGate,
            .coreFlush,
            .adapterDrain,
            .hubFlush,
            .storeClose,
            .sessionMarker
        ]
        XCTAssertEqual(firstReport, secondReport)
        XCTAssertEqual(firstReport.completedStages, expectedStages)
        XCTAssertTrue(firstReport.succeeded)
        let updatedModes = await core.updatedModes()
        let flushCallCount = await core.recordedFlushDeadlines().count
        XCTAssertEqual(updatedModes, [.disabled])
        XCTAssertEqual(flushCallCount, 1)
        XCTAssertEqual(try fixture.readSessionMarker().state, .closed)
    }

    @MainActor
    func testStopPersistsCoreEventDeliveredDuringFlushBeforeClosingIngress() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.emitEventDuringFlush = true
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)

        let report = await fixture.runtime.stop()
        let recentEventIDs = await fixture.hub.recentEvents().map(\.eventID)
        let persistedEventIDs = try RollingObservabilityStore(
            rootURL: fixture.rootURL.appendingPathComponent("Logs", isDirectory: true)
        ).loadRecentEvents(limit: 10).map(\.eventID)

        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(recentEventIDs.contains("flush-event"))
        XCTAssertTrue(persistedEventIDs.contains("flush-event"))
    }

    @MainActor
    func testStopFailureContinuesLaterStagesAndLeavesRunningMarker() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.failDisabledUpdate = true
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)

        let report = await fixture.runtime.stop()

        XCTAssertEqual(report.failures, [
            ObservabilityStopFailure(stage: .coreProducerGate, code: "operation-failed")
        ])
        XCTAssertEqual(report.completedStages, [
            .acceptedMutations,
            .coreFlush,
            .adapterDrain,
            .hubFlush,
            .storeClose
        ])
        XCTAssertFalse(report.succeeded)
        XCTAssertFalse(report.cleanSessionMarkerWritten)
        let flushCallCount = await core.recordedFlushDeadlines().count
        XCTAssertEqual(flushCallCount, 1)
        XCTAssertEqual(try fixture.readSessionMarker().state, .running)
    }

    @MainActor
    func testHealthIssuesRemainStableAndDeduplicatedAcrossReads() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.failInitialization = true
        behavior.reportedHealth = ObservabilityHealth(
            initialized: false,
            mode: .standard,
            queueDepth: 0,
            queueCapacity: 4096,
            droppedTrace: 0,
            droppedDebug: 0,
            droppedInfo: 0,
            droppedWarn: 0,
            droppedError: 0,
            redactionRejected: 0,
            callbackConnected: false,
            degraded: true,
            degradedReason: "core-degraded"
        )
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }

        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let first = await fixture.runtime.health()
        let second = await fixture.runtime.health()
        let expectedIssues = [
            ObservabilityHealthIssue(source: .core, code: "core-degraded"),
            ObservabilityHealthIssue(source: .core, code: "core-not-initialized"),
            ObservabilityHealthIssue(source: .runtime, code: "core-initialization-failed")
        ]
        XCTAssertEqual(first.issues, expectedIssues)
        XCTAssertEqual(second.issues, expectedIssues)
        XCTAssertEqual(first.degradedReason, "core-degraded")
        XCTAssertEqual(Set(first.issues.map(\.id)).count, first.issues.count)
        _ = await fixture.runtime.stop()
    }
}
