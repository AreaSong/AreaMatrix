@testable import AreaMatrix
import XCTest

final class ObservabilityIncidentJournalStateTests: XCTestCase {
    func testWriterRejectsEventAndRepeatedFreezeAfterFreeze() throws {
        try assertPostFreezeMutationRejected(.event)
        try assertPostFreezeMutationRejected(.freeze)
    }

    func testRecoveredIncidentUsesRequestedCapacityAndNewestSuffix() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let configuration = contractConfiguration(mode: .developer)
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: configuration)
        let incidentID = "capacity"
        var snapshot = contractIncident(id: incidentID, sessionID: "capacity-session")
        snapshot.events = (1 ... 5).map { index in
            incidentEvent(id: "event-\(index)", incidentID: incidentID)
        }
        try store.beginIncident(snapshot, configuration: configuration)
        store.close()

        let recovered = try store.loadIncidentSnapshots(
            currentSessionID: "restart-session",
            maximumEvents: 2
        )

        XCTAssertEqual(recovered.first?.events.map(\.eventID), ["event-4", "event-5"])
    }

    func testUnfrozenIncidentStatusRoundTripsAndRemainsWritable() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 1)
        let configuration = contractConfiguration(mode: .developer)
        var store = RollingObservabilityStore(rootURL: fixture.logsURL, now: { clock.date })
        try store.prepare(configuration: configuration)
        try store.beginIncident(
            contractIncident(id: "open-status", sessionID: "open-session"),
            configuration: configuration
        )
        try store.updateIncident(
            id: "open-status",
            status: .open,
            frozenAtMilliseconds: nil,
            configuration: configuration
        )
        try store.appendIncidentEvent(
            incidentEvent(id: "after-open-status", incidentID: "open-status"),
            incidentID: "open-status",
            configuration: configuration
        )
        store.close()

        let recovered = try store.loadIncidentSnapshots(currentSessionID: "open-session")
        let snapshot = try XCTUnwrap(recovered.first)
        XCTAssertEqual(snapshot.status, .open)
        XCTAssertFalse(snapshot.isFrozen)
        XCTAssertEqual(snapshot.events.map(\.eventID), ["after-open-status"])
    }
}

private extension ObservabilityIncidentJournalStateTests {
    enum PostFreezeMutation {
        case event
        case freeze
    }

    func assertPostFreezeMutationRejected(_ mutation: PostFreezeMutation) throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let configuration = contractConfiguration(mode: .developer)
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: configuration)
        try store.beginIncident(
            contractIncident(id: "frozen", sessionID: "frozen-session"),
            configuration: configuration
        )
        try store.freezeIncident(
            id: "frozen",
            frozenAtMilliseconds: 2,
            configuration: configuration
        )

        XCTAssertThrowsError(try mutate(&store, mutation: mutation, configuration: configuration)) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .readOnly)
        }
        XCTAssertFalse(store.available)
        XCTAssertEqual(store.takeIncidentPersistenceChanges().readOnlyIDs, ["frozen"])
    }

    func mutate(
        _ store: inout RollingObservabilityStore,
        mutation: PostFreezeMutation,
        configuration: AppObservabilityConfiguration
    ) throws {
        switch mutation {
        case .event:
            try store.appendIncidentEvent(
                incidentEvent(id: "after-freeze", incidentID: "frozen"),
                incidentID: "frozen",
                configuration: configuration
            )
        case .freeze:
            try store.freezeIncident(
                id: "frozen",
                frozenAtMilliseconds: 3,
                configuration: configuration
            )
        }
    }

    func incidentEvent(id: String, incidentID: String) -> ObservabilityEventSnapshot {
        var event = contractEvent(id: id, sessionID: "journal-state-session")
        event.incidentID = incidentID
        return event
    }
}
