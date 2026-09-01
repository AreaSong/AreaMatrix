import AreaMatrixCoreSDK

struct MobileCloudStorageCoreFFIClient: Sendable {
    func detectCloudStorageState(repoPath: String) throws -> MobileCloudStorageState {
        do {
            return MobileCloudStorageCoreSDKMapping.state(
                try AreaMatrixCoreSDK.detectCloudStorageState(repoPath: repoPath)
            )
        } catch {
            throw MobileCloudStorageCoreSDKMapping.error(error)
        }
    }
}

enum MobileCloudStorageCoreSDKMapping {
    static func state(
        _ value: AreaMatrixCoreSDK.CloudStorageState
    ) -> MobileCloudStorageState {
        MobileCloudStorageState(
            repoPath: value.repoPath,
            providerKind: provider(value.providerKind),
            risk: risk(value.risk),
            placeholderState: placeholder(value.placeholderState),
            permissionState: permission(value.permissionState),
            statusSummary: value.statusSummary,
            riskReasons: value.riskReasons,
            recommendedAction: action(value.recommendedAction),
            requiresNoticeAcknowledgement: value.requiresNoticeAcknowledgement,
            noticeAcknowledged: value.noticeAcknowledged,
            canRetry: value.canRetry,
            requiresReconnect: value.requiresReconnect
        )
    }

    private static func provider(
        _ value: AreaMatrixCoreSDK.CloudStorageProviderKind
    ) -> MobileCloudStorageProviderKind {
        switch value {
        case .local:
            .local
        case .iCloudDrive:
            .iCloudDrive
        case .oneDrive:
            .oneDrive
        case .unknown:
            .unknown
        }
    }

    private static func risk(
        _ value: AreaMatrixCoreSDK.CloudStorageRiskLevel
    ) -> MobileCloudStorageRiskLevel {
        switch value {
        case .noRisk:
            .noRisk
        case .low:
            .low
        case .medium:
            .medium
        case .high:
            .high
        case .unknown:
            .unknown
        }
    }

    private static func placeholder(
        _ value: AreaMatrixCoreSDK.CloudPlaceholderState
    ) -> MobileCloudPlaceholderState {
        switch value {
        case .notPlaceholder:
            .notPlaceholder
        case .placeholder:
            .placeholder
        case .unknown:
            .unknown
        }
    }

    private static func permission(
        _ value: AreaMatrixCoreSDK.CloudPermissionState
    ) -> MobileCloudPermissionState {
        switch value {
        case .accessible:
            .accessible
        case .permissionDenied:
            .permissionDenied
        case .accessExpired:
            .accessExpired
        case .unknown:
            .unknown
        }
    }

    private static func action(
        _ value: AreaMatrixCoreSDK.CloudStorageRecommendedAction
    ) -> MobileCloudStorageRecommendedAction {
        switch value {
        case .none:
            .none
        case .acknowledgeNotice:
            .acknowledgeNotice
        case .retryStatusCheck:
            .retryStatusCheck
        case .reconnectFolder:
            .reconnectFolder
        case .chooseLocalFolder:
            .chooseLocalFolder
        }
    }

    static func error(_ error: Error) -> MobileRepositoryConnectionError {
        if let connectionError = error as? MobileRepositoryConnectionError {
            return connectionError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable("Cloud storage status could not be checked. Try again.")
        }
        switch coreError {
        case let .InvalidPath(path):
            return .invalidPath(path)
        case let .ICloudPlaceholder(path):
            return .iCloudPlaceholder(path)
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        case let .RepoNotInitialized(path):
            return .invalidRepository(path)
        default:
            return .unavailable("Cloud storage status could not be checked. Try again.")
        }
    }
}
