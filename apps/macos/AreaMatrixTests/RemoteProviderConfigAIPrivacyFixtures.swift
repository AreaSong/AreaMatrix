@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func remoteProviderConfigAIPrivacyRemoteProviderUnavailable() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "Remote provider unavailable",
            severity: .medium,
            suggestedAction: "Configure remote AI",
            recoverability: .userActionRequired,
            rawContext: "ai-privacy-rules remote-provider-config-core"
        )
    }
}

extension RemoteProviderConfigState {
    static func remoteProviderConfigAIPrivacyRemoteProviderConfigured() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries, .semanticSearch],
            updatedAt: 309,
            disabledReason: nil
        )
    }
}

extension AISettingsSnapshot {
    static func remoteProviderConfigAIPrivacyRemoteReady(repoPath: String) -> AISettingsSnapshot {
        remoteProviderConfigAIPrivacySnapshot(config: AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .remoteFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "Default gate policy",
            featureToggles: [
                AISettingsFeatureConfigSnapshot(feature: .autoSummaries, enabled: true, allowRemote: true),
                AISettingsFeatureConfigSnapshot(feature: .semanticSearch, enabled: true, allowRemote: true)
            ]
        ))
    }

    static func remoteProviderConfigAIPrivacySnapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 309
        )
    }
}
