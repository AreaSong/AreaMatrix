import Combine
import Foundation

final class OnboardingModel: ObservableObject {
    static let defaultRepositoryPathDisplay = "~/AreaMatrix/"
    @Published var route: Route = .loadingConfiguration
    @Published var toastMessage: String?
    @Published var settingsGeneralSelectedTab: String? = "general"
    @Published var choosePathAction: ChoosePathAction?
    @Published var validatePathAction: ValidatePathAction?
    @Published var repositoryPathText = OnboardingModel.defaultRepositoryPathDisplay
    @Published var repositoryPathError: String?
    @Published var repositoryPathErrorMapping: CoreErrorMappingSnapshot?
    @Published var repositoryPathValidation: RepoPathValidationSnapshot?
    @Published var existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
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
    @Published var pendingTagSuggestionFocus: TagSuggestionPresentationRequest?
    @Published var isRetryingMainRepository = false
    var openingCancellationToken: UUID?
    @Published var initializationDiagnostics: InitializationDiagnosticsState = .idle
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
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let importProgressControlState: ImportProgressControlState
    let accessibilityAnnouncer: any AccessibilityAnnouncing
    let helpOpener: any WelcomeHelpOpening
    let directoryPicker: any RepositoryDirectoryPicking
    let importPicker: any RepositoryImportPicking
    var didBootstrap = false
    var queuedDockImportBatches: [[URL]] = []
    var validatePathReturnRoute: Route = .choosePath
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
        systemCapabilityChecker: any OnboardingSystemCapabilityChecking = LocalOnboardingCapabilities(),
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
        self.systemCapabilityChecker = systemCapabilityChecker
        self.importProgressControlState = importProgressControlState
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.helpOpener = helpOpener
        self.directoryPicker = directoryPicker
        self.importPicker = importPicker
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
