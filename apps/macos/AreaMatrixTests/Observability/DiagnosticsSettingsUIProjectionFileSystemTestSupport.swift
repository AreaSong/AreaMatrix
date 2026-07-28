@testable import AreaMatrix
import Foundation
import XCTest

struct DiagnosticsUIFixture {
    let rootURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let hub: ObservabilityHub

    init() throws {
        rootURL = try makeTestTemporaryDirectory(named: "DiagnosticsSettingsUIProjectionTests")
        suiteName = "DiagnosticsSettingsUIProjectionTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: defaults),
            rootURL: rootURL.appendingPathComponent("Logs", isDirectory: true),
            sessionID: "diagnostics-ui-tests",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        removeTestTemporaryItems(rootURL)
    }

    func makeRepositoryMetadata() throws -> URL {
        let repositoryURL = rootURL.appendingPathComponent("Repository", isDirectory: true)
        let metadataURL = repositoryURL.appendingPathComponent(".areamatrix", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try Data("diagnostic-index".utf8).write(
            to: metadataURL.appendingPathComponent("index.db", isDirectory: false)
        )
        return repositoryURL
    }
}

actor DiagnosticsCoreSpy: CoreObservabilityControlling {
    private var updatedConfiguration: ObservabilityConfig?

    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot {
        observabilityTestCoreBuildContext()
    }

    func initializeObservability(
        config: ObservabilityConfig,
        sink _: any CoreObservabilitySink
    ) async throws -> ObservabilityHealth {
        updatedConfiguration = config
        return .testHealthy
    }

    func updateObservability(config: ObservabilityConfig) async throws -> ObservabilityHealth {
        updatedConfiguration = config
        return .testHealthy
    }

    func observabilityHealth() async -> ObservabilityHealth {
        .testHealthy
    }

    func flushObservability(deadlineMilliseconds _: UInt64) async throws -> ObservabilityHealth {
        .testHealthy
    }

    func lastUpdatedConfiguration() -> ObservabilityConfig? {
        updatedConfiguration
    }
}

@MainActor
final class DiagnosticsPackageHandlerSpy: DiagnosticsPackageHandling {
    private(set) var exportedPackageID: String?
    private(set) var lastPreview: DiagnosticPackagePreview?
    var inspection: DiagnosticPackageInspection?
    let exportURL = URL(fileURLWithPath: "/tmp/diagnostics-ui-tests.amdiagnostic")

    func export(
        _ preview: DiagnosticPackagePreview,
        suggestedFileName _: String
    ) throws -> URL? {
        exportedPackageID = preview.manifest.packageID
        lastPreview = preview
        return exportURL
    }

    func openPackage() throws -> DiagnosticPackageInspection? {
        inspection
    }
}

actor DiagnosticsPackagePreviewerSpy: DiagnosticsPackagePreviewing {
    struct Call {
        let eventIDs: [String]
        let privacySelection: DiagnosticPackagePrivacySelection
        let repositoryURL: URL?
    }

    private var recordedCalls: [Call] = []

    func makePreview(
        events: [ObservabilityEventSnapshot],
        privacySelection: DiagnosticPackagePrivacySelection,
        repositoryURL: URL?,
        summary: String
    ) throws -> DiagnosticPackagePreview {
        recordedCalls.append(Call(
            eventIDs: events.map(\.eventID),
            privacySelection: privacySelection,
            repositoryURL: repositoryURL
        ))
        return try DiagnosticPackageExporter().preview(
            events: events,
            privacySelection: privacySelection,
            repositoryURL: repositoryURL,
            summary: summary
        )
    }

    func calls() -> [Call] {
        recordedCalls
    }
}

extension AppObservabilityConfiguration {
    static let testDisabled = Self(
        mode: .disabled,
        minimumSeverity: .trace,
        diskBudgetBytes: 50 * 1024 * 1024,
        retentionHours: 24,
        includeSensitive: false
    )
}

extension ObservabilityHealth {
    static let testHealthy = Self(
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

struct DiagnosticsTestSemantic {
    let actionID: String
    let componentID: String
    let phase: String
}

func makeDiagnosticsUIEvent(
    id: String,
    sequence: UInt64,
    parentSpanID: String?,
    semantic: DiagnosticsTestSemantic
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 2,
        eventID: id,
        wallTimestampMilliseconds: Int64(sequence),
        monotonicTimestampNanoseconds: sequence,
        sequenceNumber: sequence,
        sessionID: "diagnostics-ui-tests",
        incidentID: nil,
        traceID: "diagnostics-trace",
        spanID: "span-\(id)",
        parentSpanID: parentSpanID,
        operationID: nil,
        retryOfOperationID: nil,
        actionID: semantic.actionID,
        componentID: semantic.componentID,
        layer: "platform",
        phase: semantic.phase,
        severity: .info,
        outcome: "succeeded",
        durationMilliseconds: 10,
        resources: [],
        error: nil,
        attributes: [],
        privacy: "public",
        message: nil,
        target: nil,
        threadName: nil,
        buildContext: observabilityTestCoreBuildContext()
    )
}

func makeDiagnosticsOfflineInspection(
    _ preview: DiagnosticPackagePreview
) -> DiagnosticPackageInspection {
    DiagnosticPackageInspection(
        manifest: preview.manifest,
        privacyReport: preview.privacyReport,
        events: [makeDiagnosticsUIEvent(
            id: "offline-event",
            sequence: 1,
            parentSpanID: nil,
            semantic: DiagnosticsTestSemantic(
                actionID: "repository.import.confirmed",
                componentID: "core.repository.import",
                phase: "completed"
            )
        )],
        summary: "Offline inspection"
    )
}
