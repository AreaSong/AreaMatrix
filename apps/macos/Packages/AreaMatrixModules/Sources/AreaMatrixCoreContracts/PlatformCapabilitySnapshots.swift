import Foundation

/// Stable platform capability identifiers shared by CoreBridge and features.
public enum PlatformIdSnapshot: String, Equatable, Hashable, Sendable {
    case macos = "macOS"
    case ios = "iOS"
    case windows = "Windows"
    case linux = "Linux"
    case unknown = "Unknown"
}

/// Availability reported for one platform capability.
public enum PlatformCapabilityStatusSnapshot: String, Equatable, Hashable, Sendable {
    case available = "Available"
    case limited = "Limited"
    case notAvailable = "Not available"
    case unknown = "Unknown"
}

/// A capability result that is safe for feature and preview consumption.
public struct PlatformCapabilitySupportSnapshot: Equatable, Hashable, Sendable {
    public let status: PlatformCapabilityStatusSnapshot
    public let uiEnabled: Bool
    public let requiresPermission: Bool
    public let reason: String?

    public init(
        status: PlatformCapabilityStatusSnapshot,
        uiEnabled: Bool,
        requiresPermission: Bool,
        reason: String?
    ) {
        self.status = status
        self.uiEnabled = uiEnabled
        self.requiresPermission = requiresPermission
        self.reason = reason
    }
}

/// The complete platform capability snapshot used by settings and diagnostics.
public struct PlatformCapabilitiesSnapshot: Equatable, Sendable {
    public let platform: PlatformIdSnapshot
    public let appVersion: String
    public let watcher: PlatformCapabilitySupportSnapshot
    public let trash: PlatformCapabilitySupportSnapshot
    public let shareExtension: PlatformCapabilitySupportSnapshot
    public let cloudPlaceholder: PlatformCapabilitySupportSnapshot
    public let securityBookmark: PlatformCapabilitySupportSnapshot

    public init(
        platform: PlatformIdSnapshot,
        appVersion: String,
        watcher: PlatformCapabilitySupportSnapshot,
        trash: PlatformCapabilitySupportSnapshot,
        shareExtension: PlatformCapabilitySupportSnapshot,
        cloudPlaceholder: PlatformCapabilitySupportSnapshot,
        securityBookmark: PlatformCapabilitySupportSnapshot
    ) {
        self.platform = platform
        self.appVersion = appVersion
        self.watcher = watcher
        self.trash = trash
        self.shareExtension = shareExtension
        self.cloudPlaceholder = cloudPlaceholder
        self.securityBookmark = securityBookmark
    }

    public static func unknown(
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
