@testable import AreaMatrix
import Foundation
import XCTest

final class RollingStoreRetentionContractTests: XCTestCase {
    func testIncidentBudgetFailurePreservesIncidentBeingAppended() throws {
        let fixture = try RetentionContractFixture()
        defer { fixture.cleanup() }
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        let initial = retentionConfiguration()
        try store.prepare(configuration: initial)
        try store.beginIncident(retentionIncident(id: "prepared"), configuration: initial)
        let incidentURL = fixture.incidentURL(id: "prepared")
        let bytesBefore = try Data(contentsOf: incidentURL)
        let constrained = retentionConfiguration(diskBudgetBytes: store.usageBytes + 1)

        XCTAssertThrowsError(try store.freezeIncident(
            id: "prepared",
            frozenAtMilliseconds: 2,
            configuration: constrained
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .budgetExceeded)
        }

        try assertIncidentIsUnchanged(
            store: store,
            url: incidentURL,
            bytes: bytesBefore,
            id: "prepared"
        )
    }

    func testIncidentBudgetFailurePreservesIncidentAcrossLazyPrepareRetention() throws {
        let fixture = try RetentionContractFixture()
        defer { fixture.cleanup() }
        let initial = retentionConfiguration()
        var seed = RollingObservabilityStore(rootURL: fixture.logsURL)
        try seed.prepare(configuration: initial)
        try seed.beginIncident(retentionIncident(id: "lazy"), configuration: initial)
        seed.close()
        let incidentURL = fixture.incidentURL(id: "lazy")
        let bytesBefore = try Data(contentsOf: incidentURL)
        var lazy = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            now: { Date(timeIntervalSince1970: 4_000_000_000) }
        )
        let constrained = retentionConfiguration(diskBudgetBytes: Int64(bytesBefore.count))

        XCTAssertThrowsError(try lazy.freezeIncident(
            id: "lazy",
            frozenAtMilliseconds: 2,
            configuration: constrained
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .budgetExceeded)
        }

        try assertIncidentIsUnchanged(
            store: lazy,
            url: incidentURL,
            bytes: bytesBefore,
            id: "lazy"
        )
    }
}

private struct RetentionContractFixture {
    let rootURL: URL
    let logsURL: URL

    init() throws {
        rootURL = try makeTestTemporaryDirectory(named: "RollingObservabilityStoreRetentionContractTests")
        logsURL = rootURL.appendingPathComponent("Logs", isDirectory: true)
    }

    func incidentURL(id: String) -> URL {
        logsURL.appendingPathComponent("incidents/incident-\(id).jsonl")
    }

    func cleanup() {
        removeTestTemporaryItems(rootURL)
    }
}

private func retentionConfiguration(
    diskBudgetBytes: Int64 = 100 * 1024 * 1024
) -> AppObservabilityConfiguration {
    AppObservabilityConfiguration(
        mode: .developer,
        minimumSeverity: .trace,
        diskBudgetBytes: diskBudgetBytes,
        retentionHours: 24,
        includeSensitive: false
    )
}

private func retentionIncident(id: String) -> ObservabilityIncidentSnapshot {
    ObservabilityIncidentSnapshot(
        id: id,
        sessionID: "retention-session",
        markedAtMilliseconds: 1,
        captureEndsAtMilliseconds: 2,
        status: .open,
        note: nil,
        events: [],
        isFrozen: false,
        recoveredAfterRestart: false
    )
}

private func assertIncidentIsUnchanged(
    store: RollingObservabilityStore,
    url: URL,
    bytes: Data,
    id: String
) throws {
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(
        try store.loadIncidentSnapshots(currentSessionID: "retention-session").map(\.id),
        [id]
    )
}
