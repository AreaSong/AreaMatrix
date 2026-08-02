import Combine
import Foundation

enum AIPrivacyRemoteProviderLoadState: Equatable {
    case loading, loaded, failed(AISettingsError)
}

enum AIPrivacyRulesLoadState: Equatable {
    case loading, loaded, failed(AISettingsError)
}

@MainActor
final class AIPrivacyRemoteProviderStateModel: ObservableObject {
    @Published private(set) var loadState: AIPrivacyRemoteProviderLoadState = .loading
    @Published private(set) var snapshot: RemoteProviderConfigState?

    let repoPath: String
    private let providerReader: any CoreRemoteProviderConfiguring
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        providerReader: any CoreRemoteProviderConfiguring,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.providerReader = providerReader
        self.errorMapper = errorMapper
    }

    var allowsPrivacyGateEnable: Bool {
        guard let snapshot else { return false }
        return snapshot.providerConfigured && snapshot.providerVerified &&
            snapshot.remoteProviderEnabled && !snapshot.featureScope.isEmpty
    }

    var providerStatusText: String {
        switch loadState {
        case .loading: L10n.string("Loading remote provider...")
        case .failed: L10n.string("Remote provider state unavailable")
        case .loaded: loadedProviderStatusText
        }
    }

    var verifiedStatusText: String {
        guard let snapshot else { return L10n.string("Loading") }
        return snapshot.providerVerified
            ? L10n.string("Connection tested")
            : L10n.string("Connection test required")
    }

    var enabledStatusText: String {
        guard let snapshot else { return L10n.string("Loading") }
        return snapshot.remoteProviderEnabled
            ? L10n.string("Remote provider enabled")
            : L10n.string("Remote provider disabled")
    }

    var featureScopeText: String {
        guard let snapshot else { return L10n.string("Loading") }
        guard !snapshot.featureScope.isEmpty else { return L10n.string("No remote usage scope selected") }
        return snapshot.featureScope.map(\.title).joined(separator: ", ")
    }

    func load() async {
        loadState = .loading
        do {
            snapshot = try await providerReader.loadRemoteProviderConfig(repoPath: repoPath)
            loadState = .loaded
        } catch {
            snapshot = nil
            loadState = await .failed(providerError(for: error))
        }
    }

    private var loadedProviderStatusText: String {
        guard let snapshot else { return L10n.string("Remote provider state unavailable") }
        if !snapshot.providerConfigured { return L10n.string("Configure remote AI required") }
        if !snapshot.providerVerified { return L10n.string("Remote provider needs connection test.") }
        if !snapshot.remoteProviderEnabled { return L10n.string("Remote provider is disabled in AI settings.") }
        if snapshot.featureScope.isEmpty { return L10n.string("Remote scope is not selected.") }
        return L10n.string("Configured")
    }

    private func providerError(for error: Error) async -> AISettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: L10n.message("Remote provider state could not be loaded."),
                recovery: mapping.recoveryMessage(fallback: L10n.message("Retry or configure remote AI.")),
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: L10n.message("Remote provider state could not be loaded."),
            recovery: L10n.message("Retry or configure remote AI."),
            detail: error.localizedDescription
        )
    }
}
