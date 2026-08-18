import AreaMatrixCoreBridgeContract
import Foundation

extension OnboardingModel {
    @MainActor func showWelcome() {
        route = .welcome
        toastMessage = nil
    }

    @MainActor
    func showChoosePath() {
        if case let .mainEmpty(opening) = route {
            validatePathReturnRoute = .settingsGeneral(opening)
            settingsGeneralSelectedTab = "repository"
        }
        if !validatePathReturnRoute.isSettingsReturnRoute { validatePathReturnRoute = .choosePath }
        route = .choosePath
        toastMessage = nil
        repositoryPathErrorMapping = nil
        repositoryPathError = localRepositoryPathError(for: repositoryPathText)
    }

    @MainActor
    func showValidatePath() {
        route = .validatePath
        toastMessage = nil
    }

    @MainActor
    func resetCancelledMainOpening(repoPath: String) {
        repositoryPathText = repoPath
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        latestScanSession = nil
        initializationOpenErrorMapping = nil
        validatePathAction = nil
    }

    @MainActor
    func returnFromChoosePath() {
        if validatePathReturnRouteIsSettings {
            returnFromValidatePath()
        } else {
            showWelcome()
        }
    }

    @MainActor
    func beginSettingsRepositoryPathValidation(_ repoPath: String) async {
        validatePathReturnRoute = .settingsRepository
        updateRepositoryPath(repoPath)
        route = .validatePath
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        validatePathAction = nil
        isICloudRiskAccepted = false
        await validateSelectedRepositoryPath()
    }

    @MainActor
    func beginSettingsRepositoryChange(from opening: RepositoryOpeningResult) {
        validatePathReturnRoute = .settingsGeneral(opening)
        settingsGeneralSelectedTab = "repository"
        updateRepositoryPath(opening.config.repoPath)
        showChoosePath()
    }

    @MainActor
    func returnFromValidatePath() {
        route = validatePathReturnRoute
        toastMessage = nil
        repositoryPathErrorMapping = nil
    }

    @MainActor
    func continueFromWelcome() {
        route = .choosePath
        toastMessage = nil
        repositoryPathError = localRepositoryPathError(for: repositoryPathText)
    }

    @MainActor
    func updateRepositoryPath(_ value: String) {
        repositoryPathText = value
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        latestScanSession = nil
        initializationScanSession = nil
        initializationRecoveryReport = nil
        initializationProgressWarning = nil
        initializationOpenErrorMapping = nil
        mainRepoRecoveryValidation = nil
        mainRepoRecoveryErrorMapping = nil
        mainRepoExternalRemoval = .unavailable
        mainRepoDiagnostics = .idle
        mainRepoLastOpenedAt = nil
        isRetryingMainRepository = false
        initializationDiagnostics = .idle
        isInitializationCancellationRequested = false
        choosePathAction = nil
        validatePathAction = nil
        repositoryPathErrorMapping = nil
        toastMessage = nil
        isICloudRiskAccepted = false
        repositoryPathError = localRepositoryPathError(for: value)
    }

    @MainActor
    func chooseRepositoryPath() {
        if let selectedURL = directoryPicker.chooseDirectory() { updateRepositoryPath(selectedURL.path) }
    }

    @MainActor
    func useDefaultRepositoryPath() async {
        updateRepositoryPath(Self.defaultRepositoryPathDisplay)
        await continueFromChoosePath()
    }

    @MainActor
    func continueFromChoosePath() async {
        guard repositoryPathError == nil else {
            return
        }

        route = .validatePath
        if !validatePathReturnRoute.isSettingsReturnRoute { validatePathReturnRoute = .choosePath }
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        validatePathAction = nil
        isICloudRiskAccepted = false
        await validateSelectedRepositoryPath()
    }

    @MainActor
    func retryRepositoryPathValidation() async {
        validatePathAction = nil
        await validateSelectedRepositoryPath()
    }

    @MainActor
    func updateICloudRiskAccepted(_ isAccepted: Bool) {
        isICloudRiskAccepted = isAccepted
    }

    @MainActor
    func continueFromValidatePath() async {
        guard canContinueFromValidatePath, let validation = repositoryPathValidation else {
            return
        }

        if validation.isInitialized {
            validatePathAction = .openExistingRepositoryRequested(validation)
            await openExistingRepository(validation)
        } else {
            switch validation.recommendedMode {
            case .adoptExisting:
                validatePathAction = .adoptExistingRequested(validation, scanSession: latestScanSession)
                route = .confirmRepositoryInitialization(RepositoryInitializationDraft(
                    validation: validation,
                    mode: .adoptExisting,
                    scanSession: latestScanSession
                ))
            default:
                validatePathAction = .continueRequested(validation)
                route = .confirmRepositoryInitialization(RepositoryInitializationDraft(
                    validation: validation,
                    mode: .createEmpty,
                    scanSession: nil
                ))
            }
        }
    }

    @MainActor
    func createEmptyRepositoryFromConfirmInit() async {
        await initializeRepositoryFromConfirmInit(mode: .createEmpty)
    }

    @MainActor
    func adoptExistingRepositoryFromConfirmInit() async {
        await initializeRepositoryFromConfirmInit(mode: .adoptExisting)
    }

    var shouldConfirmSetupExit: Bool {
        if route == .validatePath { return true }
        if case .confirmRepositoryInitialization = route { return true }
        if case .initializing = route { return true }
        return false
    }

    @MainActor
    func requestSetupQuit() {
        if shouldConfirmSetupExit { isSetupQuitConfirmationPresented = true }
    }

    @MainActor
    func cancelSetupQuit() {
        isSetupQuitConfirmationPresented = false
    }

    @MainActor
    @discardableResult
    func confirmSetupQuit() -> Bool {
        if case .initializing = route {
            isSetupQuitConfirmationPresented = false
            isInitializationCancellationRequested = true
            toastMessage = L10n.message("onboarding.quit.pausingInitialization")
            return false
        }

        let shouldCloseWindow = !validatePathReturnRoute.isSettingsReturnRoute
        isSetupQuitConfirmationPresented = false
        validatePathAction = nil
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        latestScanSession = nil
        initializationScanSession = nil
        initializationRecoveryReport = nil
        initializationProgressWarning = nil
        isInitializationCancellationRequested = false
        stopInitializationProgressPolling()
        route = shouldCloseWindow ? .welcome : validatePathReturnRoute
        return shouldCloseWindow
    }

    @MainActor
    func initializeRepositoryFromConfirmInit(mode: RepoInitModeSnapshot) async {
        guard case let .confirmRepositoryInitialization(draft) = route, draft.mode == mode else { return }

        let repoPath = draft.validation.repoPath
        initializationScanSession = draft.scanSession
        initializationRecoveryReport = nil
        initializationProgressWarning = nil
        initializationDiagnostics = .idle
        route = .initializing(draft)
        defer { stopInitializationProgressPolling() }

        do {
            let latestValidation = try await pathValidator.validateRepoPath(repoPath: repoPath)
            guard Self.validationStillMatchesConfirmMode(latestValidation, mode: mode) else {
                repositoryPathValidation = latestValidation
                repositoryPathError = L10n.message("onboarding.validate.pathChangedRevalidate")
                route = .validatePath
                return
            }

            try await recoverStartupResidue(repoPath: repoPath)
            if finishInitializationCancellationIfRequested() { return }
            let watcherSeed = MainExternalCreatedFileWatcher.currentEventID()
            startInitializationProgressPolling(repoPath: repoPath, mode: mode)
            try await initializeRepository(repoPath: repoPath, mode: mode)
            if let watcherSeed {
                try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                    try await self.externalChangesSyncer.setFSEventCursor(
                        repoPath: repoPath,
                        lastEventID: watcherSeed
                    )
                }
            }
            if finishInitializationCancellationIfRequested() { return }
            settingsWriter.saveConfiguredRepoPath(repoPath)
            initializationOpenErrorMapping = nil
            route = .initializationDone(RepositoryInitializationResult(
                repoPath: repoPath,
                mode: mode,
                scanSession: initializationScanSession,
                recoveryReport: initializationRecoveryReport
            ))
        } catch {
            await routeInitializationFailure(error, repoPath: repoPath)
        }
    }

    @MainActor
    func finishInitializationCancellationIfRequested() -> Bool {
        guard isInitializationCancellationRequested else { return false }

        initializationScanSession = nil
        initializationRecoveryReport = nil
        initializationProgressWarning = nil
        initializationDiagnostics = .idle
        isInitializationCancellationRequested = false
        route = .welcome
        toastMessage = L10n.message("onboarding.quit.stoppedAtSafePoint")
        return true
    }
}
