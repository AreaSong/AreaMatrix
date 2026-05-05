extension OnboardingModel {
    enum Route: Equatable, Sendable {
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
        case dbRepairConfirm(String, ScanSessionSnapshot?, CoreErrorMappingSnapshot?)
        case settingsRepository
        case mainEmpty(RepositoryOpeningResult)
        case mainList(RepositoryOpeningResult)
        case configurationError(ConfigLoadFailure)
    }

    enum ChoosePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
    }

    enum ValidatePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
        case adoptExistingRequested(RepoPathValidationSnapshot, scanSession: ScanSessionSnapshot?)
        case openExistingRepositoryRequested(RepoPathValidationSnapshot)
    }
}
