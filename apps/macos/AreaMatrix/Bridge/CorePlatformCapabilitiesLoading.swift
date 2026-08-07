import AreaMatrixCoreBridgeContract
import AreaMatrixCoreContracts
import Foundation

extension PlatformIdSnapshot {
    var displayName: String {
        self == .unknown ? L10n.string("Unknown") : rawValue
    }
}

extension PlatformCapabilityStatusSnapshot {
    var displayName: String {
        switch self {
        case .available: L10n.string("Available")
        case .limited: L10n.string("Limited")
        case .notAvailable: L10n.string("Not available")
        case .unknown: L10n.string("Unknown")
        }
    }
}

extension CoreBridge: CorePlatformCapabilitiesLoading {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let capabilities = try self.generatedAdapter.loadPlatformCapabilities(
                platform: platform.corePlatformId,
                appVersion: appVersion
            )
            return PlatformCapabilitiesSnapshot(coreCapabilities: capabilities)
        }.value
    }
}

extension PlatformCapabilitiesSnapshot {
    init(coreCapabilities: PlatformCapabilities) {
        self.init(
            platform: PlatformIdSnapshot(corePlatformId: coreCapabilities.platform),
            appVersion: coreCapabilities.appVersion,
            watcher: PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.watcher),
            trash: PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.trash),
            shareExtension: PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.shareExtension),
            cloudPlaceholder: PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.cloudPlaceholder),
            securityBookmark: PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.securityBookmark)
        )
    }
}

private extension PlatformCapabilitySupportSnapshot {
    init(coreSupport: PlatformCapabilitySupport) {
        self.init(
            status: PlatformCapabilityStatusSnapshot(coreStatus: coreSupport.status),
            uiEnabled: coreSupport.uiEnabled,
            requiresPermission: coreSupport.requiresPermission,
            reason: coreSupport.reason
        )
    }
}

private extension PlatformIdSnapshot {
    init(corePlatformId: PlatformId) {
        switch corePlatformId {
        case .macos:
            self = .macos
        case .ios:
            self = .ios
        case .windows:
            self = .windows
        case .linux:
            self = .linux
        case .unknown:
            self = .unknown
        }
    }

    var corePlatformId: PlatformId {
        switch self {
        case .macos:
            .macos
        case .ios:
            .ios
        case .windows:
            .windows
        case .linux:
            .linux
        case .unknown:
            .unknown
        }
    }
}

private extension PlatformCapabilityStatusSnapshot {
    init(coreStatus: PlatformCapabilityStatus) {
        switch coreStatus {
        case .available:
            self = .available
        case .limited:
            self = .limited
        case .notAvailable:
            self = .notAvailable
        case .unknown:
            self = .unknown
        }
    }
}
