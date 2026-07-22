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

    private static var missingFolder: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.missingFolder.title"),
            message: L10n.string("repository.error.missingFolder.message"),
            primaryAction: .reconnectFolder,
            primaryActionTitle: L10n.string("repository.error.reconnect.action"),
            runningActionTitle: L10n.string("repository.error.missingFolder.running"),
            showsTechnicalDetails: true
        )
    }

    private static var permissionDenied: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.permission.title"),
            message: L10n.string("repository.error.permission.message"),
            primaryAction: .reconnectFolder,
            primaryActionTitle: L10n.string("repository.error.reconnect.action"),
            runningActionTitle: L10n.string("repository.error.permission.running"),
            showsTechnicalDetails: true
        )
    }

    private static var iCloudPlaceholder: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.icloud.title"),
            message: L10n.string("repository.error.icloud.message"),
            primaryAction: .downloadAndRetry,
            primaryActionTitle: L10n.string("repository.error.icloud.action"),
            runningActionTitle: L10n.string("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var temporarilyUnavailable: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.busy.title"),
            message: L10n.string("repository.error.busy.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.string("settings.action.retry"),
            runningActionTitle: L10n.string("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var metadataNeedsRepair: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.repair.title"),
            message: L10n.string("repository.error.repair.message"),
            primaryAction: .openRepair,
            primaryActionTitle: L10n.string("repository.error.repair.action"),
            runningActionTitle: L10n.string("repository.error.repair.running"),
            showsTechnicalDetails: true
        )
    }

    private static var incompatibleRepository: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.repair.title"),
            message: L10n.string("repository.error.incompatible.message"),
            primaryAction: .openRepair,
            primaryActionTitle: L10n.string("repository.error.repair.action"),
            runningActionTitle: L10n.string("repository.error.repair.running"),
            showsTechnicalDetails: true
        )
    }

    private static var ioFailure: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.open.title"),
            message: L10n.string("repository.error.io.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.string("settings.action.retry"),
            runningActionTitle: L10n.string("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var internalFailure: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.open.title"),
            message: L10n.string("repository.error.internal.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.string("settings.action.retry"),
            runningActionTitle: L10n.string("common.status.retrying"),
            showsTechnicalDetails: true
        )
    }

    private static var fallback: RepositoryErrorPresentation {
        RepositoryErrorPresentation(
            title: L10n.string("repository.error.open.title"),
            message: L10n.string("repository.error.open.message"),
            primaryAction: .retry,
            primaryActionTitle: L10n.string("settings.action.retry"),
            runningActionTitle: L10n.string("common.status.retrying"),
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
