@testable import AreaMatrix
import Foundation
import XCTest

final class DiagnosticsIncidentSettingsModelTests: XCTestCase {
    @MainActor
    func testDeleteSelectedIncidentUpdatesProjectionAndSelection() async throws {
        let fixture = try DiagnosticsIncidentSettingsFixture()
        defer { fixture.cleanup() }
        let incidentManager = DiagnosticsIncidentManagerSpy(snapshots: [
            makeDiagnosticsIncident(id: "older", markedAtMilliseconds: 100),
            makeDiagnosticsIncident(id: "newer", markedAtMilliseconds: 200)
        ])
        let model = DiagnosticsSettingsModel(
            runtime: fixture.runtime,
            incidentManager: incidentManager
        )

        await model.load()
        XCTAssertEqual(model.selectedIncidentID, "newer")

        await model.deleteSelectedIncident()

        let deletedIDs = await incidentManager.deletedIDs()
        XCTAssertEqual(deletedIDs, ["newer"])
        XCTAssertEqual(model.incidents.map(\.id), ["older"])
        XCTAssertEqual(model.selectedIncidentID, "older")
        XCTAssertEqual(
            model.feedback,
            .success(L10n.message("observability.feedback.incidentDeleted"))
        )
        XCTAssertFalse(model.isBusy)
    }

    @MainActor
    func testDeleteSelectedIncidentFailureKeepsProjectionAndSelection() async throws {
        let fixture = try DiagnosticsIncidentSettingsFixture()
        defer { fixture.cleanup() }
        let incident = makeDiagnosticsIncident(id: "retained", markedAtMilliseconds: 100)
        let incidentManager = DiagnosticsIncidentManagerSpy(
            snapshots: [incident],
            deleteFailure: .rejected
        )
        let model = DiagnosticsSettingsModel(
            runtime: fixture.runtime,
            incidentManager: incidentManager
        )

        await model.load()
        await model.deleteSelectedIncident()

        let deletedIDs = await incidentManager.deletedIDs()
        XCTAssertEqual(deletedIDs, ["retained"])
        XCTAssertEqual(model.incidents, [incident])
        XCTAssertEqual(model.selectedIncidentID, "retained")
        guard case let .failure(message) = model.feedback else {
            return XCTFail("Expected incident deletion failure feedback")
        }
        XCTAssertEqual(message.key, "observability.error.incidentDelete")
        XCTAssertFalse(model.isBusy)
    }
}

private struct DiagnosticsIncidentSettingsFixture {
    let rootURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let runtime: ObservabilityRuntimeAssembly

    @MainActor
    init() throws {
        rootURL = try makeTestTemporaryDirectory(named: "DiagnosticsIncidentSettingsModelTests")
        suiteName = "DiagnosticsIncidentSettingsModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: defaults),
            rootURL: rootURL.appendingPathComponent("Logs", isDirectory: true),
            sessionID: "diagnostics-incident-settings-tests"
        )
        runtime = ObservabilityRuntimeAssembly(hub: hub, core: DiagnosticsIncidentCoreStub())
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        removeTestTemporaryItems(rootURL)
    }
}

extension ObservabilityHealth {
    static let diagnosticsIncidentTestHealthy = Self(
        initialized: true,
        mode: .developer,
        queueDepth: 0,
        queueCapacity: 4096,
        droppedTrace: 0,
        droppedDebug: 0,
        droppedInfo: 0,
        droppedWarn: 0,
        droppedError: 0,
        redactionRejected: 0,
        callbackConnected: true,
        degraded: false,
        degradedReason: nil
    )
}

private func makeDiagnosticsIncident(
    id: String,
    markedAtMilliseconds: Int64
) -> ObservabilityIncidentSnapshot {
    ObservabilityIncidentSnapshot(
        id: id,
        sessionID: "diagnostics-incident-settings-tests",
        markedAtMilliseconds: markedAtMilliseconds,
        captureEndsAtMilliseconds: markedAtMilliseconds + 1,
        status: .open,
        note: nil,
        events: [],
        isFrozen: true,
        recoveredAfterRestart: false
    )
}
