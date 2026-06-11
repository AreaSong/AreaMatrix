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
        providerReader: any CoreRemoteProviderConfiguring = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
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
        case .loading: "Loading remote provider..."
        case .failed: "Remote provider state unavailable"
        case .loaded: loadedProviderStatusText
        }
    }

    var verifiedStatusText: String {
        guard let snapshot else { return "Loading" }
        return snapshot.providerVerified ? "Connection tested" : "Connection test required"
    }

    var enabledStatusText: String {
        guard let snapshot else { return "Loading" }
        return snapshot.remoteProviderEnabled ? "Remote provider enabled" : "Remote provider disabled"
    }

    var featureScopeText: String {
        guard let snapshot else { return "Loading" }
        guard !snapshot.featureScope.isEmpty else { return "No remote usage scope selected" }
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
        guard let snapshot else { return "Remote provider state unavailable" }
        if !snapshot.providerConfigured { return "Configure remote AI required" }
        if !snapshot.providerVerified { return "Remote provider needs connection test." }
        if !snapshot.remoteProviderEnabled { return "Remote provider is disabled in AI settings." }
        if snapshot.featureScope.isEmpty { return "Remote scope is not selected." }
        return "Configured by S3-03"
    }

    private func providerError(for error: Error) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: "Remote provider state could not be loaded.",
                recovery: mapping.suggestedAction.isEmpty ? "Retry or configure remote AI." : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: "Remote provider state could not be loaded.",
            recovery: "Retry or configure remote AI.",
            detail: error.localizedDescription
        )
    }
}
