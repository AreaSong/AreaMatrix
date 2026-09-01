import AreaMatrixCoreBridgeContract
import Foundation

extension OnboardingModel {
    enum Route: Equatable {
        case loadingConfiguration
        case welcome
        case choosePath
        case validatePath
        case confirmRepositoryInitialization(RepositoryInitializationDraft)
        case initializing(RepositoryInitializationDraft)
        case initializationFailed(String, CoreErrorMappingSnapshot?, RepositoryInitializationDraft?)
        case initializationDone(RepositoryInitializationResult)
        case mainLoading(MainLoadingState)
        case mainRepoError(String, CoreErrorMappingSnapshot?)
        case dbRepairConfirm(DatabaseRepairRouteState)
        case settingsRepository
        case settingsGeneral(RepositoryOpeningResult)
        case importProgress(ImportProgressRouteState)
        case importResult(ImportResultRouteState)
        case mainEmpty(RepositoryOpeningResult)
        case mainList(RepositoryOpeningResult)
        case configurationError(ConfigLoadFailure)

        var isSettingsReturnRoute: Bool {
            switch self {
            case .settingsRepository, .settingsGeneral:
                true
            default:
                false
            }
        }
    }

    enum ChoosePathAction: Equatable {
        case continueRequested(RepoPathValidationSnapshot)
    }

    enum ValidatePathAction: Equatable {
        case continueRequested(RepoPathValidationSnapshot)
        case adoptExistingRequested(RepoPathValidationSnapshot, scanSession: ScanSessionSnapshot?)
        case openExistingRepositoryRequested(RepoPathValidationSnapshot)
    }
}

struct DatabaseRepairRouteState: Equatable {
    var repoPath: String
    var scanSession: ScanSessionSnapshot?
    var mapping: CoreErrorMappingSnapshot?
    var returnRoute: DatabaseRepairReturnRoute
}

enum DatabaseRepairReturnRoute: Equatable {
    case validatePath
    case mainLoading(MainLoadingState)
    case mainRepoError(CoreErrorMappingSnapshot?)
    case mainList(RepositoryOpeningResult)
    case mainEmpty(RepositoryOpeningResult)
    case settingsRepository
    case settingsGeneral(RepositoryOpeningResult, selectedTab: String?)
}
