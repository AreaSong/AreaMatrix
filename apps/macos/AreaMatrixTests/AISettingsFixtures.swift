@testable import AreaMatrix

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
