@testable import AreaMatrix

extension RemoteProviderConfigState {
    static func remoteProviderConfigDisabled() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: false,
            providerVerified: false,
            remoteProviderEnabled: false,
            provider: nil,
            modelID: nil,
            endpointURL: nil,
            credentialConfigured: false,
            featureScope: [],
            updatedAt: nil,
            disabledReason: "Remote AI is off"
        )
    }

    static func remoteProviderConfigEnabled() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries],
            updatedAt: 302,
            disabledReason: nil
        )
    }
}
