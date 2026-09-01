import Foundation

public enum AISettingsFeatureKind: String, CaseIterable, Equatable, Identifiable, Sendable {
    case classificationSuggestions, autoSummaries, autoTags, semanticSearch

    public var id: String {
        rawValue
    }
}

public enum RemoteProviderKindState: String, CaseIterable, Equatable, Identifiable, Sendable {
    case openAi, anthropic, other

    public var id: String {
        rawValue
    }
}

public struct RemoteProviderTestRequestState: Equatable, Sendable {
    public var provider: RemoteProviderKindState
    public var modelID: String
    public var endpointURL: String?
    public var keyReference: String

    public init(provider: RemoteProviderKindState, modelID: String, endpointURL: String?, keyReference: String) {
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.keyReference = keyReference
    }
}

public struct RemoteProviderEnableRequestState: Equatable, Sendable {
    public var provider: RemoteProviderKindState
    public var modelID: String
    public var endpointURL: String?
    public var keyReference: String
    public var featureScope: [AISettingsFeatureKind]
    public var verificationToken: String
    public var dataFlowConfirmed: Bool

    public init(
        provider: RemoteProviderKindState,
        modelID: String,
        endpointURL: String?,
        keyReference: String,
        featureScope: [AISettingsFeatureKind],
        verificationToken: String,
        dataFlowConfirmed: Bool
    ) {
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.keyReference = keyReference
        self.featureScope = featureScope
        self.verificationToken = verificationToken
        self.dataFlowConfirmed = dataFlowConfirmed
    }
}

public struct RemoteProviderConfigState: Equatable, Sendable {
    public var providerConfigured: Bool
    public var providerVerified: Bool
    public var remoteProviderEnabled: Bool
    public var provider: RemoteProviderKindState?
    public var modelID: String?
    public var endpointURL: String?
    public var credentialConfigured: Bool
    public var featureScope: [AISettingsFeatureKind]
    public var updatedAt: Int64?
    public var disabledReason: String?

    public init(
        providerConfigured: Bool,
        providerVerified: Bool,
        remoteProviderEnabled: Bool,
        provider: RemoteProviderKindState?,
        modelID: String?,
        endpointURL: String?,
        credentialConfigured: Bool,
        featureScope: [AISettingsFeatureKind],
        updatedAt: Int64?,
        disabledReason: String?
    ) {
        self.providerConfigured = providerConfigured
        self.providerVerified = providerVerified
        self.remoteProviderEnabled = remoteProviderEnabled
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.credentialConfigured = credentialConfigured
        self.featureScope = featureScope
        self.updatedAt = updatedAt
        self.disabledReason = disabledReason
    }
}

public struct RemoteProviderTestResultState: Equatable, Sendable {
    public var provider: RemoteProviderKindState
    public var modelID: String
    public var endpointURL: String?
    public var status: RemoteProviderTestStatusState
    public var providerVerified: Bool
    public var verificationToken: String?
    public var sanitizedMessage: String

    public init(
        provider: RemoteProviderKindState,
        modelID: String,
        endpointURL: String?,
        status: RemoteProviderTestStatusState,
        providerVerified: Bool,
        verificationToken: String?,
        sanitizedMessage: String
    ) {
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.status = status
        self.providerVerified = providerVerified
        self.verificationToken = verificationToken
        self.sanitizedMessage = sanitizedMessage
    }
}

public enum RemotePrivacyGateAction: Equatable, Sendable {
    case enable, disable
}

public enum RemoteProviderEnableDisabledReason: Equatable, Sendable {
    case missingAPIKey
    case missingScope
    case dataFlowUnconfirmed
    case connectionUnverified
}

public struct RemoteProviderConfigDraft: Equatable, Sendable {
    public var provider: RemoteProviderKindState
    public var modelID: String
    public var endpointURL: String
    public var apiKey: String
    public var selectedScopes: Set<AISettingsFeatureKind>
    public var dataFlowConfirmed: Bool

    public init(
        provider: RemoteProviderKindState,
        modelID: String,
        endpointURL: String,
        apiKey: String,
        selectedScopes: Set<AISettingsFeatureKind>,
        dataFlowConfirmed: Bool
    ) {
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.selectedScopes = selectedScopes
        self.dataFlowConfirmed = dataFlowConfirmed
    }

    public var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedEndpointURL: String? {
        let trimmed = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var isEndpointValid: Bool {
        provider != .other || normalizedEndpointURL != nil
    }

    public var canTestConnection: Bool {
        !trimmedModelID.isEmpty && !trimmedAPIKey.isEmpty && isEndpointValid
    }

    public func canEnable(verifiedToken: String?) -> Bool {
        canTestConnection && verifiedToken != nil && !selectedScopes.isEmpty && dataFlowConfirmed
    }

    public func enableDisabledReason(verifiedToken: String?) -> RemoteProviderEnableDisabledReason? {
        if trimmedAPIKey.isEmpty { return .missingAPIKey }
        if selectedScopes.isEmpty { return .missingScope }
        if !dataFlowConfirmed { return .dataFlowUnconfirmed }
        if verifiedToken == nil { return .connectionUnverified }
        return nil
    }

    public func testRequest(keyReference: String) -> RemoteProviderTestRequestState {
        RemoteProviderTestRequestState(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            keyReference: keyReference
        )
    }

    public func enableRequest(token: String, keyReference: String) -> RemoteProviderEnableRequestState {
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

    public var fingerprint: RemoteProviderDraftFingerprint {
        RemoteProviderDraftFingerprint(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            apiKey: trimmedAPIKey
        )
    }
}

public struct RemoteProviderDraftFingerprint: Equatable, Sendable {
    public var provider: RemoteProviderKindState
    public var modelID: String
    public var endpointURL: String?
    public var apiKey: String

    public init(provider: RemoteProviderKindState, modelID: String, endpointURL: String?, apiKey: String) {
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.apiKey = apiKey
    }
}
