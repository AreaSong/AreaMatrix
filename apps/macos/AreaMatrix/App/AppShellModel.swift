import AreaMatrixCoreBridgeContract
import Combine
import Foundation

final class OnboardingModel: ObservableObject {
    static let defaultRepositoryPathDisplay = "~/AreaMatrix/"
    @Published var route: Route = .loadingConfiguration
    @Published var toastMessage: LocalizedMessage?
    @Published var settingsGeneralSelectedTab: String? = "general"
    @Published var isAppLanguageSettingsPresented = false
    @Published var choosePathAction: ChoosePathAction?
    @Published var validatePathAction: ValidatePathAction?
    @Published var repositoryPathText = OnboardingModel.defaultRepositoryPathDisplay
    @Published var repositoryPathError: LocalizedMessage?
    @Published var repositoryPathErrorMapping: CoreErrorMappingSnapshot?
    @Published var repositoryPathValidation: RepoPathValidationSnapshot?
    @Published var existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    @Published var latestScanSession: ScanSessionSnapshot?
    @Published var initializationScanSession: ScanSessionSnapshot?
    @Published var initializationRecoveryReport: RecoveryReportSnapshot?
    @Published var initializationProgressWarning: LocalizedMessage?
    @Published var initializationOpenErrorMapping: CoreErrorMappingSnapshot?
    @Published var mainRepoRecoveryValidation: RepoPathValidationSnapshot?
    @Published var mainRepoRecoveryErrorMapping: CoreErrorMappingSnapshot?
    @Published var mainRepoExternalRemoval: MainRepoExternalRemovalState = .unavailable
    @Published var mainRepoDiagnostics: MainRepoDiagnosticsState = .idle
    var mainRepoDiagnosticsGeneration = 0
    @Published var mainRepoLastOpenedAt: Int64?
    @Published var pendingExternalSyncWindows: [MainExternalSyncWindow] = []
    @Published var pendingTagSuggestionFocus: TagSuggestionPresentationRequest?
    @Published var isRetryingMainRepository = false
    var openingCancellationToken: UUID?
    @Published var initializationDiagnostics: InitializationDiagnosticsState = .idle
    var initializationDiagnosticsGeneration = 0
    var importProgressDiagnosticsGeneration = 0
    @Published var pendingImportEntry: ImportEntryRequest?
    @Published var isInitializationCancellationRequested = false
    @Published private(set) var isValidatingRepositoryPath = false
    @Published var isICloudRiskAccepted = false
    @Published var isSetupQuitConfirmationPresented = false

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
        repositoryPathValidation?.isInitialized == true
            ? L10n.string("onboarding.validate.openRepository")
            : L10n.string("onboarding.validate.continue")
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
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    let scanSessionReader: any CoreScanSessionReading
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    let errorMapper: any CoreErrorMapping
    let actionLogger: any AppUIActionLogging
    let finderOpener: any RepositoryFinderOpening
    let fileRevealer: any RepositoryFileRevealing
    let fileOpener: any RepositoryFileOpening
    let pathCopier: any RepositoryPathCopying
    let importResultExporter: any ImportResultDetailsExporting
    let importBatchSessionStore: any ImportBatchSessionPersisting
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let importProgressControlState: ImportProgressControlState
    let accessibilityAnnouncer: any AccessibilityAnnouncing
    let helpOpener: any WelcomeHelpOpening
    let directoryPicker: any RepositoryDirectoryPicking
    let importPicker: any RepositoryImportPicking
    let importFileResourceAccess: any ImportFileResourceAccessing
    var didBootstrap = false
    var queuedDockImportBatches: [[URL]] = []
    var validatePathReturnRoute: Route = .choosePath
    var initializationProgressTask: Task<Void, Never>?
    var pendingWatcherRescanSeed: (repoPath: String, eventID: Int64)?
    init(
        settingsReader: any AppSettingsReading = AppPlatformServices.settingsReader,
        settingsWriter: any AppSettingsWriting = AppPlatformServices.settingsWriter,
        configLoader _: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        pathValidator: any CoreRepositoryPathValidating = AppCoreServices.repositoryPathValidator,
        initializedPathValidator: any CoreInitializedRepositoryPathValidating =
            AppCoreServices.initializedRepositoryPathValidator,
        repositoryInitializer: any CoreRepositoryInitializing = AppCoreServices.repositoryInitializer,
        emptyRepositoryOpener: any CoreEmptyRepositoryOpening = AppCoreServices.emptyRepositoryOpener,
        importProgressImporter: any CoreFileImporting = AppCoreServices.importProgressImporter,
        importResultChangeLister: any CoreChangeLogListing = AppCoreServices.changeLogLister,
        mainLoadingTreeLister: (any CoreRepositoryTreeListing)? = nil,
        startupRecoverer: any CoreStartupRecovering = AppCoreServices.startupRecoverer,
        externalChangesSyncer: any CoreExternalChangesSyncing = AppCoreServices.externalChangesSyncer,
        repositoryWriteCoordinator: RepositoryWriteCoordinator = AppCoreServices.repositoryWriteCoordinator,
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            AppPlatformServices.existingRepositoryMetadataReader,
        scanSessionReader: any CoreScanSessionReading = AppCoreServices.scanSessionReader,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        finderOpener: any RepositoryFinderOpening = AppPlatformServices.finderOpener,
        fileRevealer: any RepositoryFileRevealing = AppPlatformServices.fileRevealer,
        fileOpener: any RepositoryFileOpening = AppPlatformServices.fileOpener,
        pathCopier: any RepositoryPathCopying = AppPlatformServices.pathCopier,
        importResultExporter: any ImportResultDetailsExporting = AppPlatformServices.importResultExporter,
        importBatchSessionStore: any ImportBatchSessionPersisting = AppPlatformServices.importBatchSessionStore,
        systemCapabilityChecker: any OnboardingSystemCapabilityChecking =
            AppPlatformServices.systemCapabilityChecker,
        importProgressControlState: ImportProgressControlState = ImportProgressControlState(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = AppPlatformServices.accessibilityAnnouncer,
        helpOpener: any WelcomeHelpOpening = AppPlatformServices.helpOpener,
        directoryPicker: any RepositoryDirectoryPicking = AppPlatformServices.directoryPicker,
        importPicker: any RepositoryImportPicking = AppPlatformServices.importPicker,
        importFileResourceAccess: any ImportFileResourceAccessing = ImportPlatformServices.fileResourceAccess,
        actionLogger: any AppUIActionLogging = NoopAppUIActionLogger()
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
        self.repositoryWriteCoordinator = repositoryWriteCoordinator
        self.existingRepositoryMetadataReader = existingRepositoryMetadataReader
        self.scanSessionReader = scanSessionReader
        self.diagnosticsCollector = diagnosticsCollector
        self.errorMapper = errorMapper
        self.actionLogger = actionLogger
        self.finderOpener = finderOpener
        self.fileRevealer = fileRevealer
        self.fileOpener = fileOpener
        self.pathCopier = pathCopier
        self.importResultExporter = importResultExporter
        self.importBatchSessionStore = importBatchSessionStore
        self.systemCapabilityChecker = systemCapabilityChecker
        self.importProgressControlState = importProgressControlState
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.helpOpener = helpOpener
        self.directoryPicker = directoryPicker
        self.importPicker = importPicker
        self.importFileResourceAccess = importFileResourceAccess
    }

    @MainActor
    convenience init(dependencies: AppDependencyContainer) {
        self.init(
            settingsReader: dependencies.platform.settingsReader,
            settingsWriter: dependencies.platform.settingsWriter,
            pathValidator: dependencies.onboarding.pathValidator,
            initializedPathValidator: dependencies.onboarding.initializedPathValidator,
            repositoryInitializer: dependencies.onboarding.repositoryInitializer,
            emptyRepositoryOpener: dependencies.onboarding.emptyRepositoryOpener,
            importProgressImporter: dependencies.onboarding.importProgressImporter,
            importResultChangeLister: dependencies.onboarding.importResultChangeLister,
            startupRecoverer: dependencies.onboarding.startupRecoverer,
            externalChangesSyncer: dependencies.onboarding.externalChangesSyncer,
            repositoryWriteCoordinator: dependencies.onboarding.repositoryWriteCoordinator,
            existingRepositoryMetadataReader: dependencies.platform.existingRepositoryMetadataReader,
            scanSessionReader: dependencies.onboarding.scanSessionReader,
            diagnosticsCollector: dependencies.onboarding.diagnosticsCollector,
            errorMapper: dependencies.onboarding.errorMapper,
            finderOpener: dependencies.platform.finderOpener,
            fileRevealer: dependencies.platform.fileRevealer,
            fileOpener: dependencies.platform.fileOpener,
            pathCopier: dependencies.platform.pathCopier,
            importResultExporter: dependencies.platform.importResultExporter,
            importBatchSessionStore: dependencies.platform.importBatchSessionStore,
            systemCapabilityChecker: dependencies.onboarding.systemCapabilityChecker,
            importProgressControlState: dependencies.onboarding.importProgressControlState,
            accessibilityAnnouncer: dependencies.platform.accessibilityAnnouncer,
            helpOpener: dependencies.platform.helpOpener,
            directoryPicker: dependencies.platform.directoryPicker,
            importPicker: dependencies.platform.importPicker,
            importFileResourceAccess: dependencies.feature.import.fileResourceAccess,
            actionLogger: dependencies.onboarding.actionLogger
        )
    }
}

extension OnboardingModel {
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
