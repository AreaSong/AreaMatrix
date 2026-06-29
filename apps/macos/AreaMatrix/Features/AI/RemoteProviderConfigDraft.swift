import Foundation

struct RemoteProviderConfigDraft: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String
    var apiKey: String
    var selectedScopes: Set<AISettingsFeatureKind>
    var dataFlowConfirmed: Bool

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedEndpointURL: String? {
        let trimmed = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isEndpointValid: Bool {
        provider != .other || normalizedEndpointURL != nil
    }

    var canTestConnection: Bool {
        !trimmedModelID.isEmpty && !trimmedAPIKey.isEmpty && isEndpointValid
    }

    func canEnable(verifiedToken: String?) -> Bool {
        canTestConnection && verifiedToken != nil && !selectedScopes.isEmpty && dataFlowConfirmed
    }

    func enableDisabledReason(verifiedToken: String?) -> String {
        if trimmedAPIKey.isEmpty { return "API key is required." }
        if selectedScopes.isEmpty { return "Select at least one usage scope." }
        if !dataFlowConfirmed { return "Confirm the remote data flow." }
        if verifiedToken == nil { return "Verify the connection before enabling remote AI." }
        return ""
    }

    func testRequest(keyReference: String) -> RemoteProviderTestRequestState {
        RemoteProviderTestRequestState(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            keyReference: keyReference
        )
    }

    func enableRequest(token: String, keyReference: String) -> RemoteProviderEnableRequestState {
        RemoteProviderEnableRequestState(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            keyReference: keyReference,
            featureScope: AISettingsFeatureKind.allCases.filter { selectedScopes.contains($0) },
            verificationToken: token,
            dataFlowConfirmed: dataFlowConfirmed
        )
    }

    var fingerprint: RemoteProviderDraftFingerprint {
        RemoteProviderDraftFingerprint(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            apiKey: trimmedAPIKey
        )
    }
}

struct RemoteProviderDraftFingerprint: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var apiKey: String
}
