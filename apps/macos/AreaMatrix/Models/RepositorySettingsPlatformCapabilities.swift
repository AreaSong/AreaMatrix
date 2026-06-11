import Combine
import Foundation

enum RepositorySettingsCapabilityState: Equatable {
    case loading
    case loaded(PlatformCapabilitiesSnapshot)
    case failed(PlatformCapabilitiesSnapshot, RepositorySettingsCapabilityError)
}

struct RepositorySettingsCapabilityError: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

struct RepositorySettingsCapabilityRow: Equatable, Identifiable {
    var id: String
    var label: String
    var support: PlatformCapabilitySupportSnapshot
    var unavailableEffect: String
}

@MainActor
final class RepoPlatformCapabilitiesModel: ObservableObject {
    @Published private(set) var state: RepositorySettingsCapabilityState = .loading
    @Published private(set) var isLoading = false

    let hostPlatform: PlatformIdSnapshot
    let appVersion: String
    private let capabilityLoader: any CorePlatformCapabilitiesLoading
    private let errorMapper: any CoreErrorMapping

    init(
        hostPlatform: PlatformIdSnapshot = .macos,
        appVersion: String = RepoPlatformCapabilitiesModel.defaultAppVersion(),
        capabilityLoader: any CorePlatformCapabilitiesLoading = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.hostPlatform = hostPlatform
        self.appVersion = appVersion
        self.capabilityLoader = capabilityLoader
        self.errorMapper = errorMapper
    }

    var allowsDiagnosticsExport: Bool {
        switch state {
        case let .loaded(capabilities):
            capabilities.repositorySettingsAllowsDiagnostics
        case .failed, .loading:
            false
        }
    }

    var diagnosticsDisabledReason: String? {
        switch state {
        case .loading:
            "Repository access capability is still loading."
        case let .loaded(capabilities):
            capabilities.settingsDiagnosticsReason
        case let .failed(_, error):
            error.recovery
        }
    }

    func load() async {
        isLoading = true
        state = .loading
        defer {
            isLoading = false
        }

        do {
            let capabilities = try await capabilityLoader.getPlatformCapabilities(
                platform: hostPlatform,
                appVersion: appVersion
            )
            state = .loaded(capabilities)
        } catch {
            let mappedError = await capabilityError(for: error)
            state = .failed(.unknown(
                platform: hostPlatform,
                appVersion: appVersion,
                reason: mappedError.detail
            ), mappedError)
        }
    }

    nonisolated static func defaultAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
    }

    private func capabilityError(for error: Error) async -> RepositorySettingsCapabilityError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsCapabilityError(
                message: "Platform capabilities unavailable",
                recovery: mapping.suggestedAction.isEmpty ? mapping.userMessage : mapping.suggestedAction,
                detail: mapping.rawContext.isEmpty ? coreError.localizedDescription : mapping.rawContext
            )
        }

        if let bridgeError = error as? CoreBridgeError {
            return RepositorySettingsCapabilityError(
                message: "Platform capabilities unavailable",
                recovery: "Check the Core platform capability bridge, then retry.",
                detail: bridgeError.localizedDescription
            )
        }

        return RepositorySettingsCapabilityError(
            message: "Platform capabilities unavailable",
            recovery: "Retry repository settings after the platform capability bridge is available.",
            detail: error.localizedDescription
        )
    }
}

extension PlatformCapabilitiesSnapshot {
    var repositorySettingsRows: [RepositorySettingsCapabilityRow] {
        [
            RepositorySettingsCapabilityRow(
                id: "watcher",
                label: "Watcher",
                support: watcher,
                unavailableEffect: "Watcher-backed status stays disabled."
            ),
            RepositorySettingsCapabilityRow(
                id: "trash",
                label: "Trash / Recycle Bin",
                support: trash,
                unavailableEffect: "Recoverable destructive actions stay disabled elsewhere."
            ),
            RepositorySettingsCapabilityRow(
                id: "cloud-placeholder",
                label: "Cloud placeholders",
                support: cloudPlaceholder,
                unavailableEffect: "Cloud placeholder state is shown as unavailable or unknown."
            ),
            RepositorySettingsCapabilityRow(
                id: "security-bookmark",
                label: "Repository access",
                support: securityBookmark,
                unavailableEffect: "Diagnostics export is disabled until repository access is available."
            )
        ]
    }

    var repositorySettingsAllowsDiagnostics: Bool {
        securityBookmark.uiEnabled
    }

    var settingsDiagnosticsReason: String? {
        guard !repositorySettingsAllowsDiagnostics else { return nil }
        return securityBookmark.reason ?? "Repository access is not available on this platform."
    }
}
