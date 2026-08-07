import AreaMatrixCoreBridgeContract
import AreaMatrixCoreContracts
import Combine
import Foundation

enum RepositorySettingsCapabilityState: Equatable {
    case loading
    case loaded(PlatformCapabilitiesSnapshot)
    case failed(PlatformCapabilitiesSnapshot, RepositorySettingsCapabilityError)
}

struct RepositorySettingsCapabilityError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
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
        appVersion: String? = nil,
        appVersionReader: any AppVersionReading,
        capabilityLoader: any CorePlatformCapabilitiesLoading,
        errorMapper: any CoreErrorMapping
    ) {
        self.hostPlatform = hostPlatform
        self.appVersion = appVersion ?? appVersionReader.appVersion()
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
            L10n.string("Repository access capability is still loading.")
        case let .loaded(capabilities):
            capabilities.settingsDiagnosticsReason
        case let .failed(_, error):
            L10n.resolve(error.recovery)
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

    private func capabilityError(for error: Error) async -> RepositorySettingsCapabilityError {
        if let display = await errorMapper.mapCoreErrorDisplayIfPresent(error) {
            return RepositorySettingsCapabilityError(
                message: L10n.message("Platform capabilities unavailable"),
                recovery: display.recovery,
                detail: display.detail
            )
        }

        if let bridgeError = error as? CoreBridgeError {
            return RepositorySettingsCapabilityError(
                message: L10n.message("Platform capabilities unavailable"),
                recovery: L10n.message("Check the Core platform capability bridge, then retry."),
                detail: bridgeError.localizedDescription
            )
        }

        return RepositorySettingsCapabilityError(
            message: L10n.message("Platform capabilities unavailable"),
            recovery: L10n.message("Retry repository settings after the platform capability bridge is available."),
            detail: error.localizedDescription
        )
    }
}

extension PlatformCapabilitiesSnapshot {
    var repositorySettingsRows: [RepositorySettingsCapabilityRow] {
        [
            RepositorySettingsCapabilityRow(
                id: "watcher",
                label: L10n.string("Watcher"),
                support: watcher,
                unavailableEffect: L10n.string("Watcher-backed status stays disabled.")
            ),
            RepositorySettingsCapabilityRow(
                id: "trash",
                label: L10n.string("Trash / Recycle Bin"),
                support: trash,
                unavailableEffect: L10n.string("Recoverable destructive actions stay disabled elsewhere.")
            ),
            RepositorySettingsCapabilityRow(
                id: "cloud-placeholder",
                label: L10n.string("Cloud placeholders"),
                support: cloudPlaceholder,
                unavailableEffect: L10n.string("Cloud placeholder state is shown as unavailable or unknown.")
            ),
            RepositorySettingsCapabilityRow(
                id: "security-bookmark",
                label: L10n.string("Repository access"),
                support: securityBookmark,
                unavailableEffect: L10n.string("Diagnostics export is disabled until repository access is available.")
            )
        ]
    }

    var repositorySettingsAllowsDiagnostics: Bool {
        securityBookmark.uiEnabled
    }

    var settingsDiagnosticsReason: String? {
        guard !repositorySettingsAllowsDiagnostics else { return nil }
        return securityBookmark.reason ?? L10n.string("Repository access is not available on this platform.")
    }
}
