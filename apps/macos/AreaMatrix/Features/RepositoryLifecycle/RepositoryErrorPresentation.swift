import Foundation

enum MainRepoPrimaryRecoveryAction: Equatable {
    case retry
    case reconnectFolder
    case downloadAndRetry
    case openRepair
}

struct RepositoryErrorPresentation: Equatable {
    var title: String
    var message: String
    var primaryAction: MainRepoPrimaryRecoveryAction
    var primaryActionTitle: String
    var runningActionTitle: String
    var showsTechnicalDetails: Bool

    static func mainRepo(mapping: CoreErrorMappingSnapshot?) -> RepositoryErrorPresentation {
        guard let mapping else { return fallback }
        if mapping.kind == .db {
            return mapping.usesInlineRepositoryOpeningError ? temporarilyUnavailable : metadataNeedsRepair
        }
        return mainRepoNonDatabase(mapping.kind)
    }

    private static func mainRepoNonDatabase(_ kind: CoreErrorKindSnapshot) -> RepositoryErrorPresentation {
        switch kind {
        case .fileNotFound, .invalidPath:
            missingFolder
        case .permissionDenied:
            permissionDenied
        case .iCloudPlaceholder:
            iCloudPlaceholder
        case .db:
            metadataNeedsRepair
        case .config, .validation, .repoNotInitialized:
            incompatibleRepository
        case .stagingRecoveryRequired:
            metadataNeedsRepair
        case .io:
            ioFailure
        case .internal:
            internalFailure
        case .classify, .conflict, .duplicateFile, .expiredAction:
            fallback
        }
    }

    private static let missingFolder = RepositoryErrorPresentation(
        title: "Folder is missing",
        message: "AreaMatrix cannot find this folder. It may have been moved, renamed, or disconnected.",
        primaryAction: .reconnectFolder,
        primaryActionTitle: "Reconnect folder",
        runningActionTitle: "Checking folder...",
        showsTechnicalDetails: true
    )

    private static let permissionDenied = RepositoryErrorPresentation(
        title: "Repository needs permission",
        message: "AreaMatrix no longer has permission to read this folder.",
        primaryAction: .reconnectFolder,
        primaryActionTitle: "Reconnect folder",
        runningActionTitle: "Checking permission...",
        showsTechnicalDetails: true
    )

    private static let iCloudPlaceholder = RepositoryErrorPresentation(
        title: "iCloud file is not downloaded",
        message: "AreaMatrix needs this iCloud item to be available locally before opening the repository.",
        primaryAction: .downloadAndRetry,
        primaryActionTitle: "Download and retry",
        runningActionTitle: "Retrying...",
        showsTechnicalDetails: true
    )

    private static let temporarilyUnavailable = RepositoryErrorPresentation(
        title: "Repository is temporarily unavailable",
        message: "AreaMatrix cannot read repository metadata because it is temporarily busy.",
        primaryAction: .retry,
        primaryActionTitle: "Retry",
        runningActionTitle: "Retrying...",
        showsTechnicalDetails: true
    )

    private static let metadataNeedsRepair = RepositoryErrorPresentation(
        title: "Repository metadata needs repair",
        message: "The repository metadata needs repair. Your files remain in the folder.",
        primaryAction: .openRepair,
        primaryActionTitle: "Open repair",
        runningActionTitle: "Opening repair...",
        showsTechnicalDetails: true
    )

    private static let incompatibleRepository = RepositoryErrorPresentation(
        title: "Repository metadata needs repair",
        message: "AreaMatrix cannot confirm this folder is a compatible initialized repository.",
        primaryAction: .openRepair,
        primaryActionTitle: "Open repair",
        runningActionTitle: "Opening repair...",
        showsTechnicalDetails: true
    )

    private static let ioFailure = RepositoryErrorPresentation(
        title: "Repository could not be opened",
        message: "AreaMatrix could not read the repository metadata or files.",
        primaryAction: .retry,
        primaryActionTitle: "Retry",
        runningActionTitle: "Retrying...",
        showsTechnicalDetails: true
    )

    private static let internalFailure = RepositoryErrorPresentation(
        title: "Repository could not be opened",
        message: "AreaMatrix hit an internal error while opening the repository.",
        primaryAction: .retry,
        primaryActionTitle: "Retry",
        runningActionTitle: "Retrying...",
        showsTechnicalDetails: true
    )

    private static let fallback = RepositoryErrorPresentation(
        title: "Repository could not be opened",
        message: "AreaMatrix could not open the selected repository.",
        primaryAction: .retry,
        primaryActionTitle: "Retry",
        runningActionTitle: "Retrying...",
        showsTechnicalDetails: false
    )
}

extension CoreErrorMappingSnapshot {
    var usesInlineRepositoryOpeningError: Bool {
        guard kind == .db else { return false }
        return recoverability == .retryable || severity == .medium || severity == .low
    }
}
