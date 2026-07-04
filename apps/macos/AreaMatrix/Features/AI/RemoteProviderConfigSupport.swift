import Foundation

enum RemoteProviderLoadState: Equatable {
    case idle, loading, loaded, testing, enabling, disabling, failed(AISettingsError)

    var isBusy: Bool {
        switch self {
        case .loading, .testing, .enabling, .disabling: true
        default: false
        }
    }
}

enum RemoteProviderOutcome: Equatable {
    case success(String)
    case failed(AISettingsError)
}

enum RemoteProviderConfigErrorFactory {
    static func remoteError(
        for error: Error,
        errorMapper: any CoreErrorMapping,
        message: String,
        fallbackRecovery: String
    ) async -> AISettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: message,
                recovery: mapping.recoveryText(fallback: fallbackRecovery),
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }

    static func credentialCleanupError(for error: Error, message: String, recovery: String) -> AISettingsError {
        AISettingsError(message: message, recovery: recovery, detail: error.localizedDescription)
    }

    static func testFailureTitle(_ status: RemoteProviderTestStatusState) -> String {
        switch status {
        case .providerRejected: "The API key was rejected by the provider."
        case .connectionFailed: "Connection failed. Check your network or endpoint URL."
        case .unsupportedProvider: "This provider is not supported yet."
        case .succeeded: "Remote provider could not be verified."
        }
    }
}
