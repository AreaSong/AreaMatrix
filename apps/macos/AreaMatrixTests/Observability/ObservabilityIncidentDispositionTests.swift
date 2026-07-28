@testable import AreaMatrix
import XCTest

final class ObservabilityIncidentDispositionTests: XCTestCase {
    func testLedgerRejectsDuplicateIDsAndFailsClosedWhenPersistenceBecomesReadOnly() {
        var ledger = ObservabilityIncidentLedger()
        let incident = contractIncident(id: "duplicate", sessionID: "ledger-session")
        XCTAssertTrue(ledger.begin(incident, activate: true, disposition: .manifestOwned))
        XCTAssertFalse(ledger.begin(incident, activate: true, disposition: .memoryOnly))
        XCTAssertEqual(ledger.removalDisposition(id: "duplicate"), .manifestOwned)

        ledger.markPersistence(.readOnly, for: "duplicate")

        XCTAssertEqual(ledger.removalDisposition(id: "duplicate"), .readOnly)
        XCTAssertNil(ledger.activeID(at: 1))
        XCTAssertTrue(ledger.snapshots[0].isFrozen)
        XCTAssertEqual(
            ledger.statusChange(id: "duplicate", status: .resolved, at: 1)?.disposition,
            .readOnly
        )
    }

    func testReadOnlyPlansCarryDispositionWithoutApplyingMutations() {
        var ledger = ObservabilityIncidentLedger()
        let incident = contractIncident(id: "readonly-plan", sessionID: "ledger-session")
        XCTAssertTrue(ledger.begin(incident, activate: true, disposition: .readOnly))
        let event = contractEvent(id: "capture", sessionID: "ledger-session")
        let snapshotsBeforePlans = ledger.snapshots
        let activeIDBeforePlans = ledger.activeID(at: 1)

        XCTAssertEqual(
            ledger.capturePlan(event, at: 1, capacity: 10)?.disposition,
            .readOnly
        )
        XCTAssertEqual(
            ledger.freezePlan(at: 1, truncatingWindow: true)?.disposition,
            .readOnly
        )
        XCTAssertEqual(
            ledger.statusChange(id: "readonly-plan", status: .resolved, at: 1)?.disposition,
            .readOnly
        )
        XCTAssertEqual(ledger.removalDisposition(id: "readonly-plan"), .readOnly)
        XCTAssertEqual(ledger.snapshots, snapshotsBeforePlans)
        XCTAssertEqual(ledger.activeID(at: 1), activeIDBeforePlans)
    }

    func testRecoveredReadOnlyIncidentRejectsStatusAndDeleteAndSurvivesRemoveAll() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let incidentID = "legacy-readonly"
        let incidentURL = fixture.incidentURL(id: incidentID)
        try incidentHeaderLine(id: incidentID).write(to: incidentURL)
        try writeStoreManifestV1(
            ObservabilityStoreManifestV1(schemaVersion: 1, nextEventSequence: 0, eventFiles: []),
            logsURL: fixture.logsURL
        )
        let hub = makeHub(fixture: fixture, sessionID: "readonly-session")
        await hub.configure(contractConfiguration(mode: .developer))
        let bytesBefore = try Data(contentsOf: incidentURL)

        await assertIncidentError(.readOnly) {
            try await hub.updateIncident(id: incidentID, status: "resolved")
        }
        await assertIncidentError(.readOnly) {
            try await hub.deleteIncident(id: incidentID)
        }
        try await hub.removeLocalLogs()

        let snapshots = await hub.incidentSnapshots()
        let activeIncidentID = await hub.activeIncidentID()
        XCTAssertEqual(try Data(contentsOf: incidentURL), bytesBefore)
        XCTAssertEqual(snapshots.map(\.id), [incidentID])
        XCTAssertNil(activeIncidentID)
    }

    func testDuplicateGeneratedIDDoesNotDowngradePersistedIncident() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "duplicate-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            idGenerator: { "same-id" }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        let firstIncidentID = await hub.markIncident(note: nil)
        let duplicateIncidentID = await hub.markIncident(note: nil)
        XCTAssertEqual(firstIncidentID, "same-id")
        XCTAssertEqual(duplicateIncidentID, "")

        try await hub.updateIncident(id: "same-id", status: "resolved")
        let snapshots = await hub.incidentSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].status, .resolved)
        try await hub.deleteIncident(id: "same-id")
        let remainingSnapshots = await hub.incidentSnapshots()
        XCTAssertTrue(remainingSnapshots.isEmpty)
    }

    func testFailedCaptureAndStatusDoNotApplyInMemoryPlans() async throws {
        try await assertFailedCaptureDoesNotApply()
        try await assertFailedStatusDoesNotApply()
    }
}

private extension ObservabilityIncidentDispositionTests {
    func assertFailedCaptureDoesNotApply() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let hub = makeHub(
            fixture: fixture,
            sessionID: "capture-failure-session",
            idGenerator: { "capture-failure" }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        _ = await hub.markIncident(note: nil)
        try FileManager.default.removeItem(at: fixture.incidentURL(id: "capture-failure"))

        await hub.ingestCoreEvent(contractEvent(
            id: "not-captured",
            sessionID: "capture-failure-session"
        ))

        let snapshots = await hub.incidentSnapshots()
        let activeIncidentID = await hub.activeIncidentID()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertTrue(snapshot.isFrozen)
        XCTAssertNil(activeIncidentID)
    }

    func assertFailedStatusDoesNotApply() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let hub = makeHub(
            fixture: fixture,
            sessionID: "status-failure-session",
            idGenerator: { "status-failure" }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        _ = await hub.markIncident(note: nil)
        try FileManager.default.removeItem(at: fixture.incidentURL(id: "status-failure"))

        await assertIncidentError(.persistenceUnavailable) {
            try await hub.updateIncident(id: "status-failure", status: "resolved")
        }

        let snapshots = await hub.incidentSnapshots()
        let activeIncidentID = await hub.activeIncidentID()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.status, .open)
        XCTAssertTrue(snapshot.isFrozen)
        XCTAssertNil(activeIncidentID)
    }

    func makeHub(
        fixture: HubStoreContractFixture,
        sessionID: String,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) -> ObservabilityHub {
        ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: sessionID,
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            idGenerator: idGenerator
        )
    }

    func incidentHeaderLine(id: String) throws -> Data {
        var data = try JSONEncoder().encode(ObservabilityIncidentRecord.header(
            contractIncident(id: id, sessionID: "legacy-session")
        ))
        data.append(0x0A)
        return data
    }

    func assertIncidentError(
        _ expected: ObservabilityHub.IncidentError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected incident operation to fail")
        } catch {
            XCTAssertEqual(error as? ObservabilityHub.IncidentError, expected)
        }
    }
}
