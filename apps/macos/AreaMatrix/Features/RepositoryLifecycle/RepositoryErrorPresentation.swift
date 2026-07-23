import Foundation

enum MainRepoPrimaryRecoveryAction: Equatable {
    case retry
    case reconnectFolder
    case downloadAndRetry
    case openRepair
}

struct RepositoryErrorPresentation: Equatable {
    var title: LocalizedMessage
    var message: LocalizedMessage
    var primaryAction: MainRepoPrimaryRecoveryAction
    var primaryActionTitle: LocalizedMessage
    var runningActionTitle: LocalizedMessage
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

    private static var missingFolder: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.missingFolder.title"),
            message: L10n.message("repository.error.missingFolder.message"),
            primaryAction: .reconnectFolder,
            primaryActionTitle: L10n.message("repository.error.reconnect.action"),
            runningActionTitle: L10n.message("repository.error.missingFolder.running"),
            showsTechnicalDetails: true
        )
    }

    private static var permissionDenied: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.permission.title"),
            message: L10n.message("repository.error.permission.message"),
            primaryAction: .reconnectFolder,
            primaryActionTitle: L10n.message("repository.error.reconnect.action"),
            runningActionTitle: L10n.message("repository.error.permission.running"),
            showsTechnicalDetails: true
        )
    }

    private static var iCloudPlaceholder: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.icloud.title"),
            message: L10n.message("repository.error.icloud.message"),
            primaryAction: .downloadAndRetry,
            primaryActionTitle: L10n.message("repository.error.icloud.action"),
            runningActionTitle: L10n.message("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var temporarilyUnavailable: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.busy.title"),
            message: L10n.message("repository.error.busy.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.message("settings.action.retry"),
            runningActionTitle: L10n.message("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var metadataNeedsRepair: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.repair.title"),
            message: L10n.message("repository.error.repair.message"),
            primaryAction: .openRepair,
            primaryActionTitle: L10n.message("repository.error.repair.action"),
            runningActionTitle: L10n.message("repository.error.repair.running"),
            showsTechnicalDetails: true
        )
    }

    private static var incompatibleRepository: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.repair.title"),
            message: L10n.message("repository.error.incompatible.message"),
            primaryAction: .openRepair,
            primaryActionTitle: L10n.message("repository.error.repair.action"),
            runningActionTitle: L10n.message("repository.error.repair.running"),
            showsTechnicalDetails: true
        )
    }

    private static var ioFailure: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.open.title"),
            message: L10n.message("repository.error.io.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.message("settings.action.retry"),
            runningActionTitle: L10n.message("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var internalFailure: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.open.title"),
            message: L10n.message("repository.error.internal.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.message("settings.action.retry"),
            runningActionTitle: L10n.message("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var fallback: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.message("repository.error.open.title"),
            message: L10n.message("repository.error.open.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.message("settings.action.retry"),
            runningActionTitle: L10n.message("common.status.retrying"),
            showsTechnicalDetails: false
        )
    }
}

extension CoreErrorMappingSnapshot {
    var usesInlineRepositoryOpeningError: Bool {
        guard kind == .db else { return false }
        return recoverability == .retryable || severity == .medium || severity == .low
    }
}
