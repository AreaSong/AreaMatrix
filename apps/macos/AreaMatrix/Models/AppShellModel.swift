import Combine
import Foundation

final class OnboardingModel: ObservableObject {
    private static let defaultRepositoryPathDisplay = "~/AreaMatrix/"
    @Published var route: Route = .loadingConfiguration
    @Published var toastMessage: String?
    @Published var settingsGeneralSelectedTab: String? = "general"
    @Published private(set) var choosePathAction: ChoosePathAction?
    @Published private(set) var validatePathAction: ValidatePathAction?
    @Published var repositoryPathText = OnboardingModel.defaultRepositoryPathDisplay
    @Published var repositoryPathError: String?
    @Published var repositoryPathErrorMapping: CoreErrorMappingSnapshot?
    @Published var repositoryPathValidation: RepoPathValidationSnapshot?
    @Published private(set) var existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    @Published var latestScanSession: ScanSessionSnapshot?
    @Published var initializationScanSession: ScanSessionSnapshot?
    @Published var initializationRecoveryReport: RecoveryReportSnapshot?
    @Published var initializationProgressWarning: String?
    @Published var initializationOpenErrorMapping: CoreErrorMappingSnapshot?
    @Published var mainRepoRecoveryValidation: RepoPathValidationSnapshot?
    @Published var mainRepoRecoveryErrorMapping: CoreErrorMappingSnapshot?
    @Published var mainRepoExternalRemoval: MainRepoExternalRemovalState = .unavailable
    @Published var mainRepoDiagnostics: MainRepoDiagnosticsState = .idle
    @Published var mainRepoLastOpenedAt: Int64?
    @Published var pendingExternalCreatedFileEvent: MainPendingExternalCreatedFileEvent?
    @Published var isRetryingMainRepository = false
    var openingCancellationToken: UUID?
    @Published var initializationDiagnostics: InitializationDiagnosticsState = .idle
    @Published var pendingImportEntry: ImportEntryRequest?
    @Published private(set) var isInitializationCancellationRequested = false
    @Published private(set) var isValidatingRepositoryPath = false
    @Published private(set) var isICloudRiskAccepted = false
    @Published private(set) var isSetupQuitConfirmationPresented = false

    var canContinueFromChoosePath: Bool {
        !isValidatingRepositoryPath && repositoryPathError == nil
    }

    var canContinueFromValidatePath: Bool {
        guard !isValidatingRepositoryPath, let validation = repositoryPathValidation else {
            return false
        }

        if validatePathBlockingMessage(for: validation) != nil {
            return false
        }

        if validation.isICloudPath && !isICloudRiskAccepted {
            return false
        }

        return validation.recommendedMode != nil || validation.isInitialized
    }

    var validatePathPrimaryActionTitle: String {
        repositoryPathValidation?.isInitialized == true ? "Open Repository" : "Continue"
    }

    var validatePathReturnRouteIsSettings: Bool {
        validatePathReturnRoute.isSettingsReturnRoute
    }

    let settingsReader: any AppSettingsReading
    let settingsWriter: any AppSettingsWriting
    let pathValidator: any CoreRepositoryPathValidating
    let initializedPathValidator: any CoreInitializedRepositoryPathValidating
    let repositoryInitializer: any CoreRepositoryInitializing
    let emptyRepositoryOpener: any CoreEmptyRepositoryOpening
    let importProgressImporter: any CoreFileImporting
    let importResultChangeLister: any CoreChangeLogListing
    let mainLoadingTreeLister: (any CoreRepositoryTreeListing)?
    let startupRecoverer: any CoreStartupRecovering
    let externalChangesSyncer: any CoreExternalChangesSyncing
    let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    let scanSessionReader: any CoreScanSessionReading
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    let errorMapper: any CoreErrorMapping
    let finderOpener: any RepositoryFinderOpening
    let fileRevealer: any RepositoryFileRevealing
    let fileOpener: any RepositoryFileOpening
    let pathCopier: any RepositoryPathCopying
    let importResultExporter: any ImportResultDetailsExporting
    let importBatchSessionStore: any ImportBatchSessionPersisting
    let importProgressControlState: ImportProgressControlState
    let accessibilityAnnouncer: any AccessibilityAnnouncing
    let helpOpener: any WelcomeHelpOpening
    let directoryPicker: any RepositoryDirectoryPicking
    let importPicker: any RepositoryImportPicking
    private var didBootstrap = false
    var queuedDockImportBatches: [[URL]] = []
    private var validatePathReturnRoute: Route = .choosePath
    var initializationProgressTask: Task<Void, Never>?
    init(
        settingsReader: any AppSettingsReading = UserDefaultsAppSettingsReader(),
        settingsWriter: any AppSettingsWriting = UserDefaultsAppSettingsReader(),
        configLoader _: any CoreConfigurationLoading = CoreBridge(),
        pathValidator: any CoreRepositoryPathValidating = CoreBridge(),
        initializedPathValidator: any CoreInitializedRepositoryPathValidating = CoreBridge(),
        repositoryInitializer: any CoreRepositoryInitializing = CoreBridge(),
        emptyRepositoryOpener: any CoreEmptyRepositoryOpening = CoreBridge(),
        importProgressImporter: any CoreFileImporting = CoreBridge(),
        importResultChangeLister: any CoreChangeLogListing = CoreBridge(),
        mainLoadingTreeLister: (any CoreRepositoryTreeListing)? = nil,
        startupRecoverer: any CoreStartupRecovering = CoreBridge(),
        externalChangesSyncer: any CoreExternalChangesSyncing = CoreBridge(),
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            SQLiteExistingRepositoryMetadataReader(),
        scanSessionReader: any CoreScanSessionReading = CoreBridge(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        finderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        fileRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer(),
        fileOpener: any RepositoryFileOpening = NSWorkspaceRepositoryFileOpener(),
        pathCopier: any RepositoryPathCopying = NSPasteboardRepositoryPathCopier(),
        importResultExporter: any ImportResultDetailsExporting = NSSavePanelImportResultDetailsExporter(),
        importBatchSessionStore: any ImportBatchSessionPersisting = FileImportBatchSessionStore(),
        importProgressControlState: ImportProgressControlState = ImportProgressControlState(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer(),
        helpOpener: any WelcomeHelpOpening = LocalWelcomeHelpOpener(),
        directoryPicker: any RepositoryDirectoryPicking = NSOpenPanelRepositoryDirectoryPicker(),
        importPicker: any RepositoryImportPicking = NSOpenPanelRepositoryImportPicker()
    ) {
        self.settingsReader = settingsReader
        self.settingsWriter = settingsWriter
        self.pathValidator = pathValidator
        self.initializedPathValidator = initializedPathValidator
        self.repositoryInitializer = repositoryInitializer
        self.emptyRepositoryOpener = emptyRepositoryOpener
        self.importProgressImporter = importProgressImporter
        self.importResultChangeLister = importResultChangeLister
        self.mainLoadingTreeLister = mainLoadingTreeLister ?? (emptyRepositoryOpener as? any CoreRepositoryTreeListing)
        self.startupRecoverer = startupRecoverer
        self.externalChangesSyncer = externalChangesSyncer
        self.existingRepositoryMetadataReader = existingRepositoryMetadataReader
        self.scanSessionReader = scanSessionReader
        self.diagnosticsCollector = diagnosticsCollector
        self.errorMapper = errorMapper
        self.finderOpener = finderOpener
        self.fileRevealer = fileRevealer
        self.fileOpener = fileOpener
        self.pathCopier = pathCopier
        self.importResultExporter = importResultExporter
        self.importBatchSessionStore = importBatchSessionStore
        self.importProgressControlState = importProgressControlState
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.helpOpener = helpOpener
        self.directoryPicker = directoryPicker
        self.importPicker = importPicker
    }
}

extension OnboardingModel {
    @MainActor func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await loadConfiguredRepository()
    }

    @MainActor func retryConfigurationLoad() async {
        await loadConfiguredRepository()
    }

    @MainActor func showWelcome() {
        route = .welcome; toastMessage = nil
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
        route = .validatePath; toastMessage = nil
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
        updateRepositoryPath(Self.defaultRepositoryPathDisplay); await continueFromChoosePath()
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
        validatePathAction = nil; await validateSelectedRepositoryPath()
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
            toastMessage = "正在暂停初始化，AreaMatrix 会等待 Core 到达安全点。"
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
    private func initializeRepositoryFromConfirmInit(mode: RepoInitModeSnapshot) async {
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
                repositoryPathError = "路径状态已变化，请返回重新校验"
                route = .validatePath
                return
            }

            try await recoverStartupResidue(repoPath: repoPath)
            if finishInitializationCancellationIfRequested() { return }
            startInitializationProgressPolling(repoPath: repoPath, mode: mode)
            try await initializeRepository(repoPath: repoPath, mode: mode)
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
    private func loadConfiguredRepository() async {
        guard let repoPath = settingsReader.configuredRepoPath() else { route = .welcome; return }
        let cancellationToken = UUID()
        openingCancellationToken = cancellationToken
        route = .mainLoading(MainLoadingState(
            repoPath: repoPath,
            startupRecovery: .checking,
            treeLoading: mainLoadingTreeLister != nil ? .loading : nil
        ))
        var loadingRefreshTask: Task<Void, Never>?

        do {
            try await recoverMainOpeningResidue(repoPath: repoPath, cancellationToken: cancellationToken)
            guard openingCancellationToken == cancellationToken else { return }
            loadingRefreshTask = makeMainLoadingRefreshTask(
                repoPath: repoPath,
                cancellationToken: cancellationToken,
                shouldLoadAdoptSession: true,
                shouldLoadTree: true
            )
            let opening = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: repoPath)
            guard openingCancellationToken == cancellationToken else { return }
            loadingRefreshTask?.cancel()
            finishSuccessfulRepositoryOpen(opening)
        } catch {
            guard openingCancellationToken == cancellationToken else { return }
            await loadingRefreshTask?.value
            await updateMainRepoExternalRemoval(from: error, repoPath: repoPath)
            await routeMainOpeningFailure(error, repoPath: repoPath, cancellationToken: cancellationToken)
        }
    }

    @MainActor
    private func finishInitializationCancellationIfRequested() -> Bool {
        guard isInitializationCancellationRequested else { return false }

        initializationScanSession = nil
        initializationRecoveryReport = nil
        initializationProgressWarning = nil
        initializationDiagnostics = .idle
        isInitializationCancellationRequested = false
        route = .welcome
        toastMessage = "初始化已在安全点停止。下次选择同一资料库时，" +
            "AreaMatrix 会继续或进入恢复。"
        return true
    }

    @MainActor
    func prepareRepositoryPathValidation() {
        isValidatingRepositoryPath = true
        choosePathAction = nil
        latestScanSession = nil
        existingRepositoryMetadata = nil
        repositoryPathErrorMapping = nil
        repositoryPathError = nil
    }

    @MainActor
    func finishRepositoryPathValidation() {
        isValidatingRepositoryPath = false
    }

    @MainActor
    func acceptExistingRepositoryMetadata(_ metadata: ExistingRepositoryMetadataSnapshot) {
        existingRepositoryMetadata = metadata
    }

    @MainActor
    func acceptContinueRequestedValidation(_ validation: RepoPathValidationSnapshot) {
        choosePathAction = .continueRequested(validation)
    }
}
