@testable import AreaMatrix
import XCTest

final class ObservabilityHubStoreContractTests: XCTestCase {
    func testHealthIsReadOnlyWhenActiveIncidentHasExpired() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 1_000_000)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "health-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "health-incident" }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        _ = await hub.markIncident(note: nil)

        let incidentURL = fixture.incidentURL(id: "health-incident")
        let bytesBefore = try Data(contentsOf: incidentURL)
        let healthBefore = await hub.health(core: nil)
        clock.milliseconds = 1_030_001

        let first = await hub.health(core: nil)
        let second = await hub.health(core: nil)

        XCTAssertEqual(first, second)
        XCTAssertNil(first.activeIncidentID)
        XCTAssertEqual(first.fileUsageBytes, healthBefore.fileUsageBytes)
        XCTAssertEqual(try Data(contentsOf: incidentURL), bytesBefore)
    }

    func testIncidentMutationSynchronizesBeforeReturning() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let recorder = IncidentSynchronizeRecorder()
        var store = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            durabilityOperations: .init { _, id in recorder.record(id) }
        )
        let configuration = contractConfiguration(mode: .developer)
        try store.prepare(configuration: configuration)
        try store.beginIncident(
            contractIncident(id: "dirty-incident", sessionID: "dirty-session"),
            configuration: configuration
        )
        try store.freezeIncident(
            id: "dirty-incident",
            frozenAtMilliseconds: 2,
            configuration: configuration
        )

        XCTAssertEqual(recorder.ids, ["dirty-incident"])
        try store.flush()
        XCTAssertEqual(recorder.ids, ["dirty-incident"])
    }

    func testStoreShutdownTerminalMatrixPreservesSuccessAndFailure() throws {
        let successFixture = try makeHubStoreContractFixture()
        defer { successFixture.cleanup() }
        let configuration = contractConfiguration(mode: .developer)
        var successful = RollingObservabilityStore(rootURL: successFixture.logsURL)
        try successful.prepare(configuration: configuration)
        try successful.shutdown()
        try successful.shutdown()
        try successful.flush()
        XCTAssertThrowsError(try successful.prepare(configuration: configuration)) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unavailable)
        }

        let failureFixture = try makeHubStoreContractFixture()
        defer { failureFixture.cleanup() }
        let recorder = IncidentSynchronizeRecorder(fails: true)
        var failed = RollingObservabilityStore(
            rootURL: failureFixture.logsURL,
            durabilityOperations: .init { _, id in try recorder.synchronize(id) }
        )
        try failed.prepare(configuration: configuration)
        try failed.beginIncident(
            contractIncident(id: "failed-shutdown", sessionID: "failed-session"),
            configuration: configuration
        )
        XCTAssertThrowsError(try failed.freezeIncident(
            id: "failed-shutdown",
            frozenAtMilliseconds: 2,
            configuration: configuration
        )) { error in
            XCTAssertEqual(error as? ContractDurabilityError, .injected)
        }
        XCTAssertEqual(failed.takeIncidentPersistenceChanges().readOnlyIDs, ["failed-shutdown"])
        XCTAssertFalse(failed.available)
        XCTAssertThrowsError(try failed.flush()) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unavailable)
        }
        XCTAssertThrowsError(try failed.shutdown()) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unavailable)
        }
        XCTAssertEqual(
            try failed.loadIncidentSnapshots(currentSessionID: "failed-session").map(\.id),
            ["failed-shutdown"]
        )
    }

    func testShutdownFreezesActiveIncidentBeforeClosingStore() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 2_000_000)
        let signpostSink = ObservabilitySignpostSink(maximumActiveIntervals: 2)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "shutdown-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "shutdown-incident" },
            signpostSink: signpostSink
        )
        await hub.configure(contractConfiguration(mode: .developer))
        var intervalStart = contractEvent(id: "shutdown-interval", sessionID: "shutdown-session")
        intervalStart.actionID = "repository.import.validation"
        intervalStart.componentID = "core.storage.import"
        intervalStart.phase = "started"
        await hub.ingestCoreEvent(intervalStart)
        _ = await hub.markIncident(note: nil)
        XCTAssertEqual(signpostSink.health().activeIntervalCount, 1)

        try await hub.shutdown()
        try await hub.shutdown()
        XCTAssertEqual(signpostSink.health().activeIntervalCount, 0)

        let recovered = try RollingObservabilityStore(
            rootURL: fixture.logsURL,
            now: { clock.date }
        ).loadIncidentSnapshots(currentSessionID: "shutdown-session")
        let incident = try XCTUnwrap(recovered.first)
        XCTAssertTrue(incident.isFrozen)
        XCTAssertFalse(incident.recoveredAfterRestart)
        XCTAssertEqual(incident.captureEndsAtMilliseconds, clock.milliseconds)
    }

    func testShutdownFreezesMemoryAndClosesStoreAfterIncidentPersistenceFailure() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 2_500_000)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "failed-freeze-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "failed-freeze-incident" }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        _ = await hub.markIncident(note: nil)
        try FileManager.default.removeItem(at: fixture.incidentURL(id: "failed-freeze-incident"))

        do {
            try await hub.shutdown()
            XCTFail("Expected shutdown failure")
        } catch {
            XCTAssertNotNil(error as? ObservabilitySafeFileError)
        }

        let incidentSnapshots = await hub.incidentSnapshots()
        let incident = try XCTUnwrap(incidentSnapshots.first)
        let health = await hub.health(core: nil)
        XCTAssertTrue(incident.isFrozen)
        XCTAssertEqual(incident.captureEndsAtMilliseconds, clock.milliseconds + 30_000)
        XCTAssertNil(health.activeIncidentID)
        XCTAssertFalse(health.writerAvailable)
        do {
            try await hub.shutdown()
            XCTFail("Expected terminal shutdown failure")
        } catch {
            XCTAssertEqual(error as? ObservabilityStoreError, .unavailable)
        }
    }

    func testShutdownRejectsCoreAndSemanticLateEventsWithoutAppendingOrReopening() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "late-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(contractConfiguration(mode: .developer))
        await hub.ingestCoreEvent(contractEvent(id: "before", sessionID: "late-session"))
        try await hub.flush()
        try await hub.shutdown()
        let filesBefore = try eventFileContents(in: fixture.logsURL)
        let eventsBefore = await hub.recentEvents(limit: 10)

        await hub.ingestCoreEvent(contractEvent(id: "late-core", sessionID: "late-session"))
        await hub.recordSemanticAction(ObservabilitySemanticEventInput(
            actionID: "test.late.semantic",
            componentID: "test.runtime"
        ))

        let health = await hub.health(core: nil)
        let eventsAfter = await hub.recentEvents(limit: 10)
        XCTAssertEqual(eventsAfter, eventsBefore)
        XCTAssertEqual(try eventFileContents(in: fixture.logsURL), filesBefore)
        XCTAssertEqual(health.rejectedEvents, 2)
        XCTAssertFalse(health.writerAvailable)
        XCTAssertEqual(
            try RollingObservabilityStore(rootURL: fixture.logsURL)
                .loadRecentEvents(limit: 10).map(\.eventID),
            ["before"]
        )
    }

    func testStoreCreatesSequentialManifestAndFailsClosedOnCorruption() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let configuration = contractConfiguration(mode: .developer, diskBudgetBytes: 20000)
        var store = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            rotationBytesOverride: 650
        )
        try store.prepare(configuration: configuration)
        for index in 0 ..< 6 {
            try store.append(contractEvent(
                id: "manifest-\(index)",
                sessionID: "manifest-session",
                message: String(repeating: "x", count: 120)
            ), configuration: configuration)
        }
        store.close()

        let manifestURL = fixture.logsURL.appendingPathComponent("manifest.json")
        XCTAssertEqual(try contractPermissions(at: manifestURL), 0o600)
        let manifest = try assertValidStoreManifest(at: manifestURL, logsURL: fixture.logsURL)
        let eventNames = try eventFileContents(in: fixture.logsURL).keys.sorted()
        XCTAssertTrue(eventNames.allSatisfy(isSequentialEventFileName))
        XCTAssertEqual(
            Set(manifest.entries.filter { $0.kind == .event && $0.disposition == .managed }.map(\.name)),
            Set(eventNames)
        )

        let eventBytes = try eventFileContents(in: fixture.logsURL)
        try Data("{corrupt".utf8).write(to: manifestURL)
        var recoveredStore = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            rotationBytesOverride: 650
        )
        XCTAssertThrowsError(try recoveredStore.prepare(configuration: configuration)) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .corruptManifest)
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), Data("{corrupt".utf8))
        XCTAssertEqual(try eventFileContents(in: fixture.logsURL), eventBytes)
        let temporaryFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.logsURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".tmp") }
        XCTAssertTrue(temporaryFiles.isEmpty)
    }

    func testPersistedIncidentExpiresOnceAndRecoversAtInclusiveBoundary() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 3_000_000)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "expiry-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "expiry-incident" }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        _ = await hub.markIncident(note: nil)
        clock.milliseconds = 3_030_000
        await hub.ingestCoreEvent(contractEvent(
            id: "inclusive-upper-bound",
            timestamp: clock.milliseconds,
            sessionID: "expiry-session"
        ))
        clock.milliseconds += 1
        await hub.ingestCoreEvent(contractEvent(
            id: "after-window",
            timestamp: clock.milliseconds,
            sessionID: "expiry-session"
        ))
        let incidentURL = fixture.incidentURL(id: "expiry-incident")
        let bytesAfterFreeze = try Data(contentsOf: incidentURL)

        await hub.ingestCoreEvent(contractEvent(
            id: "later-event",
            timestamp: clock.milliseconds + 1,
            sessionID: "expiry-session"
        ))

        XCTAssertEqual(try Data(contentsOf: incidentURL), bytesAfterFreeze)
        let recovered = try RollingObservabilityStore(
            rootURL: fixture.logsURL,
            now: { clock.date }
        ).loadIncidentSnapshots(currentSessionID: "expiry-session")
        let incident = try XCTUnwrap(recovered.first)
        XCTAssertTrue(incident.isFrozen)
        XCTAssertEqual(incident.events.map(\.eventID), ["inclusive-upper-bound"])
    }
}
