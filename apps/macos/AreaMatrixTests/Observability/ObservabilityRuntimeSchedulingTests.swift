@testable import AreaMatrix
import XCTest

final class ObservabilityRuntimeSchedulingTests: XCTestCase {
    @MainActor
    func testTimedLeaseRevertsAtExactExpiryWithoutRealSleep() async throws {
        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler(wallMilliseconds: 1000)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        let lease = AppObservabilityModeLease(
            policy: .timed,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: 2000
        )
        await fixture.hub.configure(.runtimeMode(.diagnostic, lease: lease))

        fixture.runtime.start()
        let didScheduleLease = await waitForRuntimeCondition {
            fixture.runtime.state == .running && scheduler.pendingSleepMilliseconds() == [1000]
        }
        XCTAssertTrue(didScheduleLease)
        scheduler.setTime(wallMilliseconds: 2000)
        XCTAssertTrue(scheduler.resumeFirstSleep(milliseconds: 1000))
        let didRevert = await waitForRuntimeCondition {
            await (fixture.hub.configurationSnapshot()).mode == .standard
        }
        let updatedModes = await core.updatedModes()
        XCTAssertTrue(didRevert)
        XCTAssertEqual(updatedModes, [.standard])
        _ = await fixture.runtime.stop()
    }

    @MainActor
    func testReplacingTimedLeaseCancelsOldTimerAndUsesNewExpiry() async throws {
        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler(wallMilliseconds: 1000)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let firstLease = AppObservabilityModeLease(
            policy: .timed,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: 2000
        )
        let secondLease = AppObservabilityModeLease(
            policy: .timed,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: 3000
        )

        try await fixture.runtime.update(.runtimeMode(.diagnostic, lease: firstLease))
        let didScheduleFirstLease = await waitForRuntimeCondition {
            scheduler.pendingSleepMilliseconds() == [1000]
        }
        XCTAssertTrue(didScheduleFirstLease)
        try await fixture.runtime.update(.runtimeMode(.developer, lease: secondLease))
        let didReplaceLease = await waitForRuntimeCondition {
            scheduler.pendingSleepMilliseconds() == [2000]
        }
        XCTAssertTrue(didReplaceLease)
        XCTAssertGreaterThanOrEqual(scheduler.cancelledSleepCount(), 1)
        XCTAssertFalse(scheduler.resumeFirstSleep(milliseconds: 1000))

        scheduler.setTime(wallMilliseconds: 3000)
        XCTAssertTrue(scheduler.resumeFirstSleep(milliseconds: 2000))
        let didRevert = await waitForRuntimeCondition {
            await (fixture.hub.configurationSnapshot()).mode == .standard
        }
        let updatedModes = await core.updatedModes()
        XCTAssertTrue(didRevert)
        XCTAssertEqual(updatedModes, [.diagnostic, .developer, .standard])
        _ = await fixture.runtime.stop()
    }

    @MainActor
    func testManualAndNextLaunchLeasesDoNotScheduleTimers() async throws {
        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler()
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let manual = AppObservabilityModeLease(
            policy: .manual,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: nil
        )
        let nextLaunch = AppObservabilityModeLease(
            policy: .nextLaunch,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: nil
        )

        try await fixture.runtime.update(.runtimeMode(.diagnostic, lease: manual))
        XCTAssertTrue(scheduler.pendingSleepMilliseconds().isEmpty)
        try await fixture.runtime.update(.runtimeMode(.developer, lease: nextLaunch))
        XCTAssertTrue(scheduler.pendingSleepMilliseconds().isEmpty)
        _ = await fixture.runtime.stop()
    }

    @MainActor
    func testStopCancelsPendingLeaseWithoutRevertingConfiguration() async throws {
        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler(wallMilliseconds: 1000)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let lease = AppObservabilityModeLease(
            policy: .timed,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: 2000
        )
        try await fixture.runtime.update(.runtimeMode(.diagnostic, lease: lease))
        let didScheduleLease = await waitForRuntimeCondition {
            scheduler.pendingSleepMilliseconds() == [1000]
        }
        XCTAssertTrue(didScheduleLease)

        let report = await fixture.runtime.stop()

        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(scheduler.pendingSleepMilliseconds().isEmpty)
        XCTAssertGreaterThanOrEqual(scheduler.cancelledSleepCount(), 1)
        let persistedMode = await fixture.hub.configurationSnapshot().mode
        let updatedModes = await core.updatedModes()
        XCTAssertEqual(persistedMode, .diagnostic)
        XCTAssertEqual(updatedModes, [.diagnostic, .disabled])
    }

    @MainActor
    func testLeaseRevertFailureAddsOneStableRuntimeHealthIssue() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.failStandardUpdate = true
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler(wallMilliseconds: 1000)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let lease = AppObservabilityModeLease(
            policy: .timed,
            activatedAtMilliseconds: 1000,
            activationSessionID: "runtime-session",
            expiresAtMilliseconds: 2000
        )
        try await fixture.runtime.update(.runtimeMode(.developer, lease: lease))
        let didScheduleLease = await waitForRuntimeCondition {
            scheduler.pendingSleepMilliseconds() == [1000]
        }
        XCTAssertTrue(didScheduleLease)
        scheduler.setTime(wallMilliseconds: 2000)
        XCTAssertTrue(scheduler.resumeFirstSleep(milliseconds: 1000))
        let didReportFailure = await waitForRuntimeCondition {
            let health = await fixture.runtime.health()
            return health.issues.contains(ObservabilityHealthIssue(
                source: .runtime,
                code: "mode-lease-revert-failed"
            ))
        }
        XCTAssertTrue(didReportFailure)

        let health = await fixture.runtime.health()
        XCTAssertEqual(
            health.issues.filter { $0.code == "mode-lease-revert-failed" }.count,
            1
        )
        let persistedMode = await fixture.hub.configurationSnapshot().mode
        XCTAssertEqual(persistedMode, .developer)
        _ = await fixture.runtime.stop()
    }

    @MainActor
    func testDeadlineDuringSuspendedFlushReportsActualCoreFlushStage() async throws {
        var behavior = ObservabilityRuntimeCoreSpy.Behavior()
        behavior.suspendFlush = true
        let core = ObservabilityRuntimeCoreSpy(behavior: behavior)
        let scheduler = TestObservabilityRuntimeScheduler(uptimeNanoseconds: 1_000_000)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)

        let stopTask = Task { await fixture.runtime.stop(deadline: .milliseconds(50)) }
        await core.waitUntilFlushEntered()
        let didScheduleTimeout = await waitForRuntimeCondition {
            scheduler.pendingSleepMilliseconds().contains(50)
        }
        XCTAssertTrue(didScheduleTimeout)
        scheduler.setTime(uptimeNanoseconds: 51_000_000)
        XCTAssertTrue(scheduler.resumeFirstSleep(milliseconds: 50))
        let report = await stopTask.value

        XCTAssertTrue(report.timedOut)
        XCTAssertEqual(report.failures.last, .init(stage: .coreFlush, code: "deadline-exceeded"))
        XCTAssertFalse(report.cleanSessionMarkerWritten)
        let flushDeadlines = await core.recordedFlushDeadlines()
        XCTAssertEqual(flushDeadlines, [50])
        XCTAssertEqual(try fixture.readSessionMarker().state, .running)
        let eventsBeforeLateCallback = await fixture.hub.recentEvents()
        let filesBeforeLateCallback = try runtimeEventFileContents(in: fixture.rootURL)
        await core.emit(runtimeCoreEvent(id: "late-before-release", sessionID: "runtime-session"))
        let eventsAfterStop = await fixture.hub.recentEvents()
        XCTAssertEqual(eventsAfterStop, eventsBeforeLateCallback)
        XCTAssertEqual(try runtimeEventFileContents(in: fixture.rootURL), filesBeforeLateCallback)
        await core.releaseFlush()
        await Task.yield()
        await core.emit(runtimeCoreEvent(id: "late-after-release", sessionID: "runtime-session"))
        let eventsAfterLateCallback = await fixture.hub.recentEvents()
        XCTAssertEqual(eventsAfterLateCallback, eventsBeforeLateCallback)
        XCTAssertEqual(try runtimeEventFileContents(in: fixture.rootURL), filesBeforeLateCallback)
    }

    @MainActor
    func testDeadlineClampingAndSaturationReachCoreWithoutOverflow() async throws {
        try await assertFlushDeadline(deadline: .zero, expected: 1)

        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler(uptimeNanoseconds: 1)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let report = await fixture.runtime.stop(deadline: .milliseconds(Int64.max))
        let flushDeadlines = await core.recordedFlushDeadlines()
        let deadline = try XCTUnwrap(flushDeadlines.first)

        XCTAssertTrue(report.succeeded)
        XCTAssertGreaterThan(deadline, 1_000_000_000_000)
        XCTAssertEqual(
            ObservabilityRuntimePolicy.saturatingMultiply(.max, 1_000_000),
            .max
        )
    }

    @MainActor
    private func assertFlushDeadline(deadline: Duration, expected: UInt64) async throws {
        let core = ObservabilityRuntimeCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler(uptimeNanoseconds: 1_000_000)
        let fixture = try ObservabilityRuntimeFixture(core: core, scheduler: scheduler)
        defer { fixture.cleanup() }
        fixture.runtime.start()
        let didStart = await waitForRuntimeCondition { fixture.runtime.state == .running }
        XCTAssertTrue(didStart)
        let report = await fixture.runtime.stop(deadline: deadline)

        XCTAssertTrue(report.succeeded)
        let flushDeadlines = await core.recordedFlushDeadlines()
        XCTAssertEqual(flushDeadlines, [expected])
    }
}

private func runtimeEventFileContents(in rootURL: URL) throws -> [String: Data] {
    let logsURL = rootURL.appendingPathComponent("Logs", isDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" }
    return try Dictionary(uniqueKeysWithValues: urls.map {
        try ($0.lastPathComponent, Data(contentsOf: $0))
    })
}
