@testable import AreaMatrix
import Foundation

actor AISettingsStaticAIErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: String(describing: error),
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: "ai-settings"
        )
    }
}

actor RecordingLocalModelReader: CoreLocalModelStatusReading {
    struct StatusRequest: Equatable {
        var repoPath: String
        var request: LocalModelStatusRequestState
    }

    struct FolderRequest: Equatable {
        var repoPath: String
        var request: LocalModelFolderRequestState
    }

    private let status: LocalModelStatusState
    private let location: LocalModelFolderLocationState
    private var recordedStatusRequests: [StatusRequest] = []
    private var recordedFolderRequests: [FolderRequest] = []

    init(status: LocalModelStatusState, location: LocalModelFolderLocationState) {
        self.status = status
        self.location = location
    }

    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        recordedStatusRequests.append(StatusRequest(repoPath: repoPath, request: request))
        return status
    }

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        recordedFolderRequests.append(FolderRequest(repoPath: repoPath, request: request))
        return location
    }

    func statusRequests() -> [StatusRequest] {
        recordedStatusRequests
    }

    func folderRequests() -> [FolderRequest] {
        recordedFolderRequests
    }
}

struct LocalModelStatusStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: String(describing: error),
            severity: .medium,
            suggestedAction: "Retry status check",
            recoverability: .retryable,
            rawContext: "local-model-status"
        )
    }
}

final class RecordingLocalModelStorageProvider: LocalModelStorageLocationProviding, @unchecked Sendable {
    private(set) var requestCount = 0
    private let defaultLocation: String

    init(defaultLocation: String) {
        self.defaultLocation = defaultLocation
    }

    func defaultStorageLocation() -> String {
        requestCount += 1
        return defaultLocation
    }
}

@MainActor
final class RecordingInstallHelpOpener: LocalModelInstallHelpOpening {
    private(set) var openCount = 0

    func openLocalModelInstallHelp() throws {
        openCount += 1
    }
}

@MainActor
final class LocalModelStatusRecordingFolderOpener: LocalModelFolderOpening {
    private(set) var locations: [LocalModelFolderLocationState] = []

    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws {
        locations.append(location)
    }
}

@MainActor
final class RecordingDiagnosticsCopier: LocalModelDiagnosticsCopying {
    private(set) var summaries: [String] = []

    func copyLocalModelDiagnostics(_ summary: String) throws {
        summaries.append(summary)
    }
}

extension AISettingsSnapshot {
    static func aiSettingsDefault(repoPath: String, aiEnabled: Bool = false) -> AISettingsSnapshot {
        aiSettingsSnapshot(config: AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: aiEnabled,
            providerPreference: .localFirst,
            localAIEnabled: false,
            remoteAIAllowed: false,
            privacyGateEnabled: true,
            privacyPolicyRef: nil,
            featureToggles: AISettingsFeatureKind.allCases.map {
                AISettingsFeatureConfigSnapshot(feature: $0, enabled: false, allowRemote: false)
            }
        ))
    }

    static func aiSettingsSnapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 1_778_000_000
        )
    }
}

extension LocalModelStatusState {
    static func localModelStatusSnapshot(
        storageLocation: String,
        availability: LocalModelAvailabilityState,
        recommendedAction: LocalModelRecommendedActionState
    ) -> LocalModelStatusState {
        LocalModelStatusState(
            modelID: LocalModelStatusModel.defaultModelID,
            storageLocation: storageLocation,
            availability: availability,
            version: nil,
            sizeBytes: nil,
            lastError: availability == .ready ? nil : "Model is not installed",
            recommendedAction: recommendedAction,
            lastCheckedAt: 1_778_000_052,
            diagnosticsSummary: "manifest: missing; runtime: unavailable",
            featureStatuses: [
                LocalModelFeatureStatusState(
                    feature: .classificationSuggestions,
                    available: availability == .ready,
                    unavailableReason: availability == .ready ? nil : "Local model unavailable"
                )
            ]
        )
    }
}

extension LocalModelFolderLocationState {
    static func localModelStatusLocation(folderPath: String, openable: Bool) -> LocalModelFolderLocationState {
        LocalModelFolderLocationState(
            modelID: LocalModelStatusModel.defaultModelID,
            folderPath: folderPath,
            exists: openable,
            readable: openable,
            openable: openable,
            unavailableReason: openable ? nil : "The folder is not available."
        )
    }
}

func temporaryClassifierRuleEditorRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixClassifierRuleEditor")
}

func classifierYaml(_ repoURL: URL) throws -> String {
    let url = repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
    return try String(contentsOf: url, encoding: .utf8)
}
