@testable import AreaMatrix
import XCTest

final class ObservabilityIncidentCommitFailureTests: XCTestCase {
    func testCaptureSyncFailureKeepsCommittedPrefix() async throws {
        try await assertSyncFailure(.capture)
    }

    func testFreezeSyncFailureKeepsCommittedPrefixAndDoesNotCreateReplacement() async throws {
        try await assertSyncFailure(.freeze)
    }

    func testStatusSyncFailureKeepsCommittedPrefix() async throws {
        try await assertSyncFailure(.status)
    }

    func testPostRenameManifestDurabilityUncertainFailsAndRevokesWriteability() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let recorder = ManifestPersistRecorder()
        var store = makeStore(fixture: fixture, recorder: recorder)
        let configuration = contractConfiguration(mode: .developer)
        try store.prepare(configuration: configuration)
        try store.beginIncident(
            contractIncident(id: "uncertain", sessionID: "uncertain-session"),
            configuration: configuration
        )
        recorder.makeNextCallUncertain()

        XCTAssertThrowsError(try store.appendIncidentEvent(
            incidentEvent(id: "uncertain-event", incidentID: "uncertain"),
            incidentID: "uncertain",
            configuration: configuration
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .durabilityUncertain)
        }

        XCTAssertFalse(store.available)
        XCTAssertEqual(store.takeIncidentPersistenceChanges().readOnlyIDs, ["uncertain"])
        XCTAssertThrowsError(try store.freezeIncident(
            id: "uncertain",
            frozenAtMilliseconds: 2,
            configuration: configuration
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unavailable)
        }
    }

    func testReadOnlyManifestPersistFailureStillRevokesRuntimeWriteability() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let recorder = ManifestPersistRecorder()
        var store = makeStore(fixture: fixture, recorder: recorder)
        let configuration = contractConfiguration(mode: .developer)
        try store.prepare(configuration: configuration)
        try store.beginIncident(
            contractIncident(id: "double-failure", sessionID: "double-failure-session"),
            configuration: configuration
        )
        let incidentURL = fixture.incidentURL(id: "double-failure")
        let committedPrefix = try Data(contentsOf: incidentURL)
        recorder.failNextCalls(2)

        XCTAssertThrowsError(try store.appendIncidentEvent(
            incidentEvent(id: "uncommitted", incidentID: "double-failure"),
            incidentID: "double-failure",
            configuration: configuration
        )) { error in
            XCTAssertEqual(error as? ContractDurabilityError, .injected)
        }

        XCTAssertFalse(store.available)
        XCTAssertEqual(store.takeIncidentPersistenceChanges().readOnlyIDs, ["double-failure"])
        XCTAssertGreaterThan(try Data(contentsOf: incidentURL).count, committedPrefix.count)
        XCTAssertThrowsError(try store.freezeIncident(
            id: "double-failure",
            frozenAtMilliseconds: 2,
            configuration: configuration
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unavailable)
        }

        var recovered = RollingObservabilityStore(rootURL: fixture.logsURL)
        try recovered.prepare(configuration: configuration)
        recovered.close()
        XCTAssertEqual(try Data(contentsOf: incidentURL), committedPrefix)
        XCTAssertTrue(try recovered.loadIncidentSnapshots(
            currentSessionID: "double-failure-session"
        ).first?.events.isEmpty == true)
    }
}

private extension ObservabilityIncidentCommitFailureTests {
    enum SyncMutation: String {
        case capture
        case freeze
        case status
    }

    func assertSyncFailure(_ mutation: SyncMutation) async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let recorder = IncidentSynchronizeRecorder(fails: true)
        let clock = TestObservabilityClock(milliseconds: 1000)
        let identifiers = TestObservabilityIdentifierSequence([
            "\(mutation.rawValue)-incident",
            "replacement-incident"
        ])
        let writer = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            now: { clock.date },
            durabilityOperations: .init { _, id in try recorder.synchronize(id) }
        )
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            writer: writer,
            sessionID: "\(mutation.rawValue)-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { identifiers.next() }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        let incidentID = await hub.markIncident(note: nil)
        let incidentURL = fixture.incidentURL(id: incidentID)
        let committedPrefix = try Data(contentsOf: incidentURL)

        try await perform(mutation, hub: hub, incidentID: incidentID)

        let snapshots = await hub.incidentSnapshots()
        let snapshot = try XCTUnwrap(snapshots.first)
        let activeIncidentID = await hub.activeIncidentID()
        XCTAssertTrue(snapshot.isFrozen)
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertEqual(snapshot.status, .open)
        XCTAssertNil(activeIncidentID)
        XCTAssertGreaterThan(try Data(contentsOf: incidentURL).count, committedPrefix.count)
        if mutation == .freeze {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: fixture.incidentURL(id: "replacement-incident").path
            ))
            XCTAssertEqual(snapshots.map(\.id), [incidentID])
        }

        let manifest = try decodeStoreManifest(at: fixture.logsURL.appendingPathComponent("manifest.json"))
        let entry = try XCTUnwrap(manifest.entries.first { $0.name == "incident-\(incidentID).jsonl" })
        XCTAssertEqual(entry.disposition, .readOnly)
        XCTAssertEqual(entry.committedBytes, Int64(committedPrefix.count))
        let recovered = try RollingObservabilityStore(rootURL: fixture.logsURL, now: { clock.date })
            .loadRecoverableIncidents(currentSessionID: "\(mutation.rawValue)-session")
        let recoveredSnapshot = try XCTUnwrap(recovered.first?.snapshot)
        XCTAssertTrue(recoveredSnapshot.events.isEmpty)
        XCTAssertEqual(recoveredSnapshot.status, .open)
        XCTAssertFalse(recoveredSnapshot.isFrozen)
    }

    func perform(
        _ mutation: SyncMutation,
        hub: ObservabilityHub,
        incidentID: String
    ) async throws {
        switch mutation {
        case .capture:
            await hub.ingestCoreEvent(contractEvent(
                id: "failed-capture",
                timestamp: 1001,
                sessionID: "capture-session"
            ))
        case .freeze:
            let replacementID = await hub.markIncident(note: nil)
            XCTAssertEqual(replacementID, "")
        case .status:
            do {
                try await hub.updateIncident(id: incidentID, status: "resolved")
                XCTFail("Expected status persistence failure")
            } catch {
                XCTAssertEqual(error as? ObservabilityHub.IncidentError, .persistenceUnavailable)
            }
        }
    }

    func makeStore(
        fixture: HubStoreContractFixture,
        recorder: ManifestPersistRecorder
    ) -> RollingObservabilityStore {
        RollingObservabilityStore(
            rootURL: fixture.logsURL,
            manifestOperations: .init { fileIO, manifest in
                try recorder.persist(fileIO, manifest: manifest)
            }
        )
    }

    func incidentEvent(id: String, incidentID: String) -> ObservabilityEventSnapshot {
        var event = contractEvent(id: id, sessionID: "incident-commit-session")
        event.incidentID = incidentID
        return event
    }
}
