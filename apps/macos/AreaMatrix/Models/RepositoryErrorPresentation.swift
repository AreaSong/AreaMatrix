import Foundation

enum MainRepoPrimaryRecoveryAction: Equatable, Sendable {
    case retry
    case reconnectFolder
    case downloadAndRetry
    case openRepair
}

struct RepositoryErrorPresentation: Equatable, Sendable {
    var title: String
    var message: String
    var primaryAction: MainRepoPrimaryRecoveryAction
    var primaryActionTitle: String
    var runningActionTitle: String
    var showsTechnicalDetails: Bool

    static func mainRepo(mapping: CoreErrorMappingSnapshot?) -> RepositoryErrorPresentation {
        guard let mapping else { return fallback }

        switch mapping.kind {
        case .fileNotFound, .invalidPath:
            return RepositoryErrorPresentation(
                title: "Folder is missing",
                message: "AreaMatrix cannot find this folder. It may have been moved, renamed, or disconnected.",
                primaryAction: .reconnectFolder,
                primaryActionTitle: "Reconnect folder",
                runningActionTitle: "Checking folder...",
                showsTechnicalDetails: true
            )
        case .permissionDenied:
            return RepositoryErrorPresentation(
                title: "Repository needs permission",
                message: "AreaMatrix no longer has permission to read this folder.",
                primaryAction: .reconnectFolder,
                primaryActionTitle: "Reconnect folder",
                runningActionTitle: "Checking permission...",
                showsTechnicalDetails: true
            )
        case .iCloudPlaceholder:
            return RepositoryErrorPresentation(
                title: "iCloud file is not downloaded",
                message: "AreaMatrix needs this iCloud item to be available locally before opening the repository.",
                primaryAction: .downloadAndRetry,
                primaryActionTitle: "Download and retry",
                runningActionTitle: "Retrying...",
                showsTechnicalDetails: true
            )
        case .db where mapping.usesInlineRepositoryOpeningError:
            return RepositoryErrorPresentation(
                title: "Repository is temporarily unavailable",
                message: "AreaMatrix cannot read repository metadata because it is temporarily busy.",
                primaryAction: .retry,
                primaryActionTitle: "Retry",
                runningActionTitle: "Retrying...",
                showsTechnicalDetails: true
            )
        case .db:
            return RepositoryErrorPresentation(
                title: "Repository metadata needs repair",
                message: "The repository metadata needs repair. Your files remain in the folder.",
                primaryAction: .openRepair,
                primaryActionTitle: "Open repair",
                runningActionTitle: "Opening repair...",
                showsTechnicalDetails: true
            )
        case .config, .repoNotInitialized:
            return RepositoryErrorPresentation(
                title: "Repository metadata needs repair",
                message: "AreaMatrix cannot confirm this folder is a compatible initialized repository.",
                primaryAction: .openRepair,
                primaryActionTitle: "Open repair",
                runningActionTitle: "Opening repair...",
                showsTechnicalDetails: true
            )
        case .io:
            return RepositoryErrorPresentation(
                title: "Repository could not be opened",
                message: "AreaMatrix could not read the repository metadata or files.",
                primaryAction: .retry,
                primaryActionTitle: "Retry",
                runningActionTitle: "Retrying...",
                showsTechnicalDetails: true
            )
        case .internal:
            return RepositoryErrorPresentation(
                title: "Repository could not be opened",
                message: "AreaMatrix hit an internal error while opening the repository.",
                primaryAction: .retry,
                primaryActionTitle: "Retry",
                runningActionTitle: "Retrying...",
                showsTechnicalDetails: true
            )
        case .classify, .conflict, .duplicateFile:
            return fallback
        }
    }

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
