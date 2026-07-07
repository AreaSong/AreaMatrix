@testable import AreaMatrix

extension AISettingsConfigSnapshot {
    static func aiSettingsConfig(
        repoPath: String,
        aiEnabled: Bool = false,
        providerPreference: AISettingsProviderPreference = .localFirst,
        localAIEnabled: Bool = false,
        remoteAIAllowed: Bool = false,
        privacyGateEnabled: Bool = true,
        privacyPolicyRef: String? = nil,
        enabledFeatures: [AISettingsFeatureKind] = [],
        remoteAllowedFeatures: [AISettingsFeatureKind] = []
    ) -> AISettingsConfigSnapshot {
        AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: aiEnabled,
            providerPreference: providerPreference,
            localAIEnabled: localAIEnabled,
            remoteAIAllowed: remoteAIAllowed,
            privacyGateEnabled: privacyGateEnabled,
            privacyPolicyRef: privacyPolicyRef,
            featureToggles: aiSettingsFeatureToggles(
                enabledFeatures: enabledFeatures,
                remoteAllowedFeatures: remoteAllowedFeatures
            )
        )
    }

    static func aiSettingsFeatureToggles(
        enabledFeatures: [AISettingsFeatureKind] = [],
        remoteAllowedFeatures: [AISettingsFeatureKind] = []
    ) -> [AISettingsFeatureConfigSnapshot] {
        AISettingsFeatureKind.allCases.map { feature in
            AISettingsFeatureConfigSnapshot(
                feature: feature,
                enabled: enabledFeatures.contains(feature),
                allowRemote: remoteAllowedFeatures.contains(feature)
            )
        }
    }
}

extension AISettingsSnapshot {
    static func aiSettingsDefault(repoPath: String, aiEnabled: Bool = false) -> AISettingsSnapshot {
        aiSettingsSnapshot(config: .aiSettingsConfig(
            repoPath: repoPath,
            aiEnabled: aiEnabled
        ))
    }

    static func aiSettingsSnapshot(
        config: AISettingsConfigSnapshot,
        updatedAt: Int64? = 1_778_000_000
    ) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: updatedAt
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
