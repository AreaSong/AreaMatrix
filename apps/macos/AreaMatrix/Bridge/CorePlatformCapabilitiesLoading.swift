import Foundation

protocol CorePlatformCapabilitiesLoading: Sendable {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot
}

enum PlatformIdSnapshot: String, Equatable, Hashable {
    case macos = "macOS"
    case ios = "iOS"
    case windows = "Windows"
    case linux = "Linux"
    case unknown = "Unknown"
}

enum PlatformCapabilityStatusSnapshot: String, Equatable, Hashable {
    case available = "Available"
    case limited = "Limited"
    case notAvailable = "Not available"
    case unknown = "Unknown"
}

struct PlatformCapabilitySupportSnapshot: Equatable {
    var status: PlatformCapabilityStatusSnapshot
    var uiEnabled: Bool
    var requiresPermission: Bool
    var reason: String?
}

struct PlatformCapabilitiesSnapshot: Equatable {
    var platform: PlatformIdSnapshot
    var appVersion: String
    var watcher: PlatformCapabilitySupportSnapshot
    var trash: PlatformCapabilitySupportSnapshot
    var shareExtension: PlatformCapabilitySupportSnapshot
    var cloudPlaceholder: PlatformCapabilitySupportSnapshot
    var securityBookmark: PlatformCapabilitySupportSnapshot

    static func unknown(
        platform: PlatformIdSnapshot,
        appVersion: String,
        reason: String
    ) -> PlatformCapabilitiesSnapshot {
        let support = PlatformCapabilitySupportSnapshot(
            status: .unknown,
            uiEnabled: false,
            requiresPermission: false,
            reason: reason
        )
        return PlatformCapabilitiesSnapshot(
            platform: platform,
            appVersion: appVersion,
            watcher: support,
            trash: support,
            shareExtension: support,
            cloudPlaceholder: support,
            securityBookmark: support
        )
    }
}

extension CoreBridge: CorePlatformCapabilitiesLoading {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let capabilities = try loadCorePlatformCapabilities(
                platform: platform.corePlatformId,
                appVersion: appVersion
            )
            return PlatformCapabilitiesSnapshot(coreCapabilities: capabilities)
        }.value
    }
}

extension PlatformCapabilitiesSnapshot {
    init(coreCapabilities: PlatformCapabilities) {
        platform = PlatformIdSnapshot(corePlatformId: coreCapabilities.platform)
        appVersion = coreCapabilities.appVersion
        watcher = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.watcher)
        trash = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.trash)
        shareExtension = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.shareExtension)
        cloudPlaceholder = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.cloudPlaceholder)
        securityBookmark = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.securityBookmark)
    }
}

private extension PlatformCapabilitySupportSnapshot {
    init(coreSupport: PlatformCapabilitySupport) {
        status = PlatformCapabilityStatusSnapshot(coreStatus: coreSupport.status)
        uiEnabled = coreSupport.uiEnabled
        requiresPermission = coreSupport.requiresPermission
        reason = coreSupport.reason
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

private func loadCorePlatformCapabilities(
    platform: PlatformId,
    appVersion: String
) throws -> PlatformCapabilities {
    try getPlatformCapabilities(platform: platform, appVersion: appVersion)
}
