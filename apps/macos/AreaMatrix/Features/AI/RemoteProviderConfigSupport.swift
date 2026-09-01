import AreaMatrixFeatureAI
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
    case success(LocalizedMessage)
    case failed(AISettingsError)
}

enum RemoteProviderConfigErrorFactory {
    static func remoteError(
        for error: Error,
        errorMapper: any CoreErrorMapping,
        message: LocalizedMessage,
        fallbackRecovery: LocalizedMessage
    ) async -> AISettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: message,
                recovery: mapping.recoveryMessage(fallback: fallbackRecovery),
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }

    static func credentialCleanupError(
        for error: Error,
        message: LocalizedMessage,
        recovery: LocalizedMessage
    ) -> AISettingsError {
        AISettingsError(message: message, recovery: recovery, detail: error.localizedDescription)
    }

    static func testFailureTitle(_ status: RemoteProviderTestStatusState) -> LocalizedMessage {
        switch status {
        case .providerRejected: L10n.message("The API key was rejected by the provider.")
        case .connectionFailed: L10n.message("Connection failed. Check your network or endpoint URL.")
        case .unsupportedProvider: L10n.message("This provider is not supported yet.")
        case .succeeded: L10n.message("Remote provider could not be verified.")
        }
    }
}
