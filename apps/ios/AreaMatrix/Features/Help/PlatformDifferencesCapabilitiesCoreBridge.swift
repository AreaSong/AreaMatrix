import AreaMatrixCoreSDK
import Foundation

protocol PlatformDifferencesCapabilityLoading: Sendable {
    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) async throws -> PlatformDifferencesCapabilities
}

enum PlatformDifferencesPlatformId: String, Equatable, Sendable {
    case macos = "macOS"
    case ios = "iOS"
    case windows = "Windows"
    case linux = "Linux"
    case unknown = "Unknown"
}

enum PlatformDifferencesCapabilityStatus: String, Equatable, Sendable {
    case available = "Available"
    case limited = "Limited"
    case notAvailable = "Not available"
    case unknown = "Unknown"
}

struct PlatformDifferencesCapabilitySupport: Equatable, Sendable {
    var status: PlatformDifferencesCapabilityStatus
    var uiEnabled: Bool
    var requiresPermission: Bool
    var reason: String?
}

struct PlatformDifferencesCapabilities: Equatable, Sendable {
    var platform: PlatformDifferencesPlatformId
    var appVersion: String
    var watcher: PlatformDifferencesCapabilitySupport
    var trash: PlatformDifferencesCapabilitySupport
    var shareExtension: PlatformDifferencesCapabilitySupport
    var cloudPlaceholder: PlatformDifferencesCapabilitySupport
    var securityBookmark: PlatformDifferencesCapabilitySupport
}

enum PlatformDifferencesCapabilityError: Error, Equatable, LocalizedError {
    case config(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .config(reason), let .unavailable(reason):
            reason
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .config:
            "Use a supported platform id and app version, then retry."
        case .unavailable:
            "Check the Core bridge integration, then retry."
        }
    }
}

actor LivePlatformDifferencesCapabilityBridge: PlatformDifferencesCapabilityLoading {
    private let client: PlatformDifferencesCapabilitiesFFIClient

    init(client: PlatformDifferencesCapabilitiesFFIClient = PlatformDifferencesCapabilitiesFFIClient()) {
        self.client = client
    }

    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) async throws -> PlatformDifferencesCapabilities {
        try client.getPlatformCapabilities(platform: platform, appVersion: appVersion)
    }
}

struct PlatformDifferencesCapabilitiesFFIClient: Sendable {
    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) throws -> PlatformDifferencesCapabilities {
        do {
            return PlatformDifferencesCapabilitiesSDKMapping.capabilities(
                try AreaMatrixCoreSDK.getPlatformCapabilities(
                    platform: PlatformDifferencesCapabilitiesSDKMapping.sdkPlatform(platform),
                    appVersion: appVersion
                )
            )
        } catch {
            throw PlatformDifferencesCapabilitiesSDKMapping.error(error)
        }
    }
}

enum PlatformDifferencesCapabilitiesSDKMapping {
    static func capabilities(
        _ value: AreaMatrixCoreSDK.PlatformCapabilities
    ) -> PlatformDifferencesCapabilities {
        PlatformDifferencesCapabilities(
            platform: platform(value.platform),
            appVersion: value.appVersion,
            watcher: support(value.watcher),
            trash: support(value.trash),
            shareExtension: support(value.shareExtension),
            cloudPlaceholder: support(value.cloudPlaceholder),
            securityBookmark: support(value.securityBookmark)
        )
    }

    private static func support(
        _ value: AreaMatrixCoreSDK.PlatformCapabilitySupport
    ) -> PlatformDifferencesCapabilitySupport {
        PlatformDifferencesCapabilitySupport(
            status: status(value.status),
            uiEnabled: value.uiEnabled,
            requiresPermission: value.requiresPermission,
            reason: value.reason
        )
    }

    private static func platform(
        _ value: AreaMatrixCoreSDK.PlatformId
    ) -> PlatformDifferencesPlatformId {
        switch value {
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

    private static func status(
        _ value: AreaMatrixCoreSDK.PlatformCapabilityStatus
    ) -> PlatformDifferencesCapabilityStatus {
        switch value {
        case .available:
            .available
        case .limited:
            .limited
        case .notAvailable:
            .notAvailable
        case .unknown:
            .unknown
        }
    }

    static func sdkPlatform(
        _ value: PlatformDifferencesPlatformId
    ) -> AreaMatrixCoreSDK.PlatformId {
        switch value {
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

    static func error(_ error: Error) -> PlatformDifferencesCapabilityError {
        if let capabilityError = error as? PlatformDifferencesCapabilityError {
            return capabilityError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable("Capability snapshot is unavailable.")
        }
        switch coreError {
        case let .Config(reason), let .Validation(reason):
            return .config(reason)
        default:
            return .unavailable("Capability snapshot is unavailable.")
        }
    }
}
