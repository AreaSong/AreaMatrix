import Foundation

enum RemoteProviderKindState: String, CaseIterable, Equatable, Identifiable {
    case openAi, anthropic, other

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .openAi: "OpenAI"
        case .anthropic: "Anthropic"
        case .other: "Other"
        }
    }
}

enum RemoteProviderTestStatusState: String, Equatable {
    case succeeded, providerRejected, connectionFailed, unsupportedProvider
}

struct RemoteProviderTestRequestState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var keyReference: String
}

struct RemoteProviderEnableRequestState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var keyReference: String
    var featureScope: [AISettingsFeatureKind]
    var verificationToken: String
    var dataFlowConfirmed: Bool
}

struct RemoteProviderDisableRequestState: Equatable {
    var removeStoredCredential: Bool
}

struct RemoteProviderConfigState: Equatable {
    var providerConfigured: Bool
    var providerVerified: Bool
    var remoteProviderEnabled: Bool
    var provider: RemoteProviderKindState?
    var modelID: String?
    var endpointURL: String?
    var credentialConfigured: Bool
    var featureScope: [AISettingsFeatureKind]
    var updatedAt: Int64?
    var disabledReason: String?
}

struct RemoteProviderTestResultState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var status: RemoteProviderTestStatusState
    var providerVerified: Bool
    var verificationToken: String?
    var sanitizedMessage: String
}
