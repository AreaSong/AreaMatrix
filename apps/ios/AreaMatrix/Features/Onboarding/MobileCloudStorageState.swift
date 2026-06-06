import Foundation

enum MobileCloudStorageProviderKind: String, Equatable, Sendable {
    case local = "Local"
    case iCloudDrive = "ICloudDrive"
    case oneDrive = "OneDrive"
    case unknown = "Unknown"
}

enum MobileCloudStorageRiskLevel: String, Equatable, Sendable {
    case noRisk = "NoRisk"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case unknown = "Unknown"
}

enum MobileCloudPlaceholderState: String, Equatable, Sendable {
    case notPlaceholder = "NotPlaceholder"
    case placeholder = "Placeholder"
    case unknown = "Unknown"
}

enum MobileCloudPermissionState: String, Equatable, Sendable {
    case accessible = "Accessible"
    case permissionDenied = "PermissionDenied"
    case accessExpired = "AccessExpired"
    case unknown = "Unknown"
}

enum MobileCloudStorageRecommendedAction: String, Equatable, Sendable {
    case none = "None"
    case acknowledgeNotice = "AcknowledgeNotice"
    case retryStatusCheck = "RetryStatusCheck"
    case reconnectFolder = "ReconnectFolder"
    case chooseLocalFolder = "ChooseLocalFolder"
}

struct MobileCloudStorageState: Equatable, Sendable {
    var repoPath: String
    var providerKind: MobileCloudStorageProviderKind
    var risk: MobileCloudStorageRiskLevel
    var placeholderState: MobileCloudPlaceholderState
    var permissionState: MobileCloudPermissionState
    var statusSummary: String
    var riskReasons: [String]
    var recommendedAction: MobileCloudStorageRecommendedAction
    var requiresNoticeAcknowledgement: Bool
    var noticeAcknowledged: Bool
    var canRetry: Bool
    var requiresReconnect: Bool

    var shouldDisplayOnConnectPage: Bool {
        providerKind != .local
            || risk != .noRisk
            || placeholderState != .notPlaceholder
            || permissionState != .accessible
            || recommendedAction != .none
            || requiresReconnect
    }
}
