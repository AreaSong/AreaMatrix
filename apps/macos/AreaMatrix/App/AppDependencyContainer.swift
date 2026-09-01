import AreaMatrixCoreBridgeContract
import AreaMatrixFeatureIngestion
import Foundation

/// Application composition root for feature dependencies.
///
/// The container is created by the App target and passed down the production
/// route. Feature initializers still accept individual protocols so tests can
/// inject focused doubles without constructing this whole graph.
struct AppDependencyContainer {
    struct Onboarding {
        let pathValidator: any CoreRepositoryPathValidating
        let initializedPathValidator: any CoreInitializedRepositoryPathValidating
        let repositoryInitializer: any CoreRepositoryInitializing
        let emptyRepositoryOpener: any CoreEmptyRepositoryOpening
        let importProgressImporter: any CoreFileImporting
        let importResultChangeLister: any CoreChangeLogListing
        let startupRecoverer: any CoreStartupRecovering
        let externalChangesSyncer: any CoreExternalChangesSyncing
        let repositoryWriteCoordinator: RepositoryWriteCoordinator
        let scanSessionReader: any CoreScanSessionReading
        let diagnosticsCollector: any CoreDiagnosticsCollecting
        let errorMapper: any CoreErrorMapping
        let actionLogger: any AppUIActionLogging
        let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
        let importProgressControlState: ImportProgressControlState
    }

    struct MainList {
        let treeLister: any CoreRepositoryTreeListing
        let savedSearchStore: any CoreSavedSearchCRUD
        let fileLister: any CoreFileListing
        let fileDetailer: any CoreFileDetailing
        let missingFileRecoverer: any CoreMissingFileRecovering
        let searchQuerying: any CoreSearchQuerying
        let semanticSearching: any CoreSemanticSearching
        let semanticFallbackReader: any CoreSemanticFallbackStatusReading
        let searchFiltering: any CoreSearchFiltering
        let commandIndexer: any CoreCommandIndexing
        let fileRenamer: any CoreFileRenaming
        let fileDeleter: any CoreFileDeleting
        let fileCategoryMover: any CoreFileCategoryMoving
        let categoryPredictor: any CoreCategoryPredicting
        let batchDeleter: any CoreBatchDeleting
        let batchCategoryChanger: any CoreBatchCategoryChanging
        let batchRenamer: any CoreBatchRenaming
        let syncConflictDetector: any CoreSyncConflictDetecting
        let iCloudConflictResolver: any ICloudConflictResolving
        let tagStore: any CoreTagCRUD
        let aiSettingsLoader: any CoreAISettingsLoading
        let aiTagSuggestionStore: any CoreAITagSuggestionManaging
        let aiPrivacyRules: any CoreAIPrivacyEvaluating
        let undoActionStore: any CoreUndoActionLogging
        let redoActionStore: any CoreRedoActionLogging
        let changeLogLister: any CoreChangeLogListing
        let externalChangesSyncer: any CoreExternalChangesSyncing
        let noteStore: any CoreNoteReadingWriting
        let errorMapper: any CoreErrorMapping
        let diagnosticsCollector: any CoreDiagnosticsCollecting
    }

    struct Platform {
        let settingsReader: any AppSettingsReading
        let settingsWriter: any AppSettingsWriting
        let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
        let finderOpener: any RepositoryFinderOpening
        let fileRevealer: any RepositoryFileRevealing
        let fileOpener: any RepositoryFileOpening
        let pathCopier: any RepositoryPathCopying
        let importResultExporter: any ImportResultDetailsExporting
        let importBatchSessionStore: any ImportBatchSessionPersisting
        let accessibilityAnnouncer: any AccessibilityAnnouncing
        let helpOpener: any WelcomeHelpOpening
        let directoryPicker: any RepositoryDirectoryPicking
        let importPicker: any RepositoryImportPicking
        let missingFilePicker: any RepositoryMissingFilePicking
        let windowCloser: any WindowClosing
        let interactionFeedback: any AppInteractionFeedbackPerforming
        let inFlightFileChangeTracker: any InFlightFileChangeTracking
    }

    let onboarding: Onboarding
    let mainList: MainList
    let platform: Platform
    let feature: AppFeatureDependencyContainer

    static func live(coreServices: AppCoreServices) -> Self {
        Self(
            onboarding: makeOnboarding(coreServices: coreServices),
            mainList: makeMainList(coreServices: coreServices),
            platform: makePlatform(),
            feature: .live(coreServices: coreServices)
        )
    }

    private static func makeOnboarding(coreServices: AppCoreServices) -> Onboarding {
        Onboarding(
            pathValidator: coreServices.repositoryPathValidator,
            initializedPathValidator: coreServices.initializedRepositoryPathValidator,
            repositoryInitializer: coreServices.repositoryInitializer,
            emptyRepositoryOpener: coreServices.emptyRepositoryOpener,
            importProgressImporter: coreServices.importProgressImporter,
            importResultChangeLister: coreServices.changeLogLister,
            startupRecoverer: coreServices.startupRecoverer,
            externalChangesSyncer: coreServices.externalChangesSyncer,
            repositoryWriteCoordinator: coreServices.repositoryWriteCoordinator,
            scanSessionReader: coreServices.scanSessionReader,
            diagnosticsCollector: coreServices.diagnosticsCollector,
            errorMapper: coreServices.errorMapper,
            actionLogger: AppLogger.shared,
            systemCapabilityChecker: AppPlatformServices.systemCapabilityChecker,
            importProgressControlState: ImportProgressControlState()
        )
    }

    private static func makeMainList(coreServices: AppCoreServices) -> MainList {
        MainList(
            treeLister: coreServices.treeLister,
            savedSearchStore: coreServices.savedSearchStore,
            fileLister: coreServices.fileLister,
            fileDetailer: coreServices.fileDetailer,
            missingFileRecoverer: coreServices.missingFileRecoverer,
            searchQuerying: coreServices.searchQuerying,
            semanticSearching: coreServices.semanticSearching,
            semanticFallbackReader: coreServices.semanticFallbackReader,
            searchFiltering: coreServices.searchFiltering,
            commandIndexer: coreServices.commandIndexer,
            fileRenamer: coreServices.fileRenamer,
            fileDeleter: coreServices.fileDeleter,
            fileCategoryMover: coreServices.fileCategoryMover,
            categoryPredictor: coreServices.categoryPredictor,
            batchDeleter: coreServices.batchDeleter,
            batchCategoryChanger: coreServices.batchCategoryChanger,
            batchRenamer: coreServices.batchRenamer,
            syncConflictDetector: coreServices.syncConflictDetector,
            iCloudConflictResolver: coreServices.iCloudConflictResolver,
            tagStore: coreServices.tagStore,
            aiSettingsLoader: coreServices.aiSettingsLoader,
            aiTagSuggestionStore: coreServices.aiTagSuggestionStore,
            aiPrivacyRules: coreServices.aiPrivacyRules,
            undoActionStore: coreServices.undoActionStore,
            redoActionStore: coreServices.redoActionStore,
            changeLogLister: coreServices.changeLogLister,
            externalChangesSyncer: coreServices.externalChangesSyncer,
            noteStore: coreServices.noteStore,
            errorMapper: coreServices.errorMapper,
            diagnosticsCollector: coreServices.diagnosticsCollector
        )
    }

    private static func makePlatform() -> Platform {
        Platform(
            settingsReader: AppPlatformServices.settingsReader,
            settingsWriter: AppPlatformServices.settingsWriter,
            existingRepositoryMetadataReader: AppPlatformServices.existingRepositoryMetadataReader,
            finderOpener: AppPlatformServices.finderOpener,
            fileRevealer: AppPlatformServices.fileRevealer,
            fileOpener: AppPlatformServices.fileOpener,
            pathCopier: AppPlatformServices.pathCopier,
            importResultExporter: AppPlatformServices.importResultExporter,
            importBatchSessionStore: AppPlatformServices.importBatchSessionStore,
            accessibilityAnnouncer: AppPlatformServices.accessibilityAnnouncer,
            helpOpener: AppPlatformServices.helpOpener,
            directoryPicker: AppPlatformServices.directoryPicker,
            importPicker: AppPlatformServices.importPicker,
            missingFilePicker: AppPlatformServices.missingFilePicker,
            windowCloser: AppPlatformServices.windowCloser,
            interactionFeedback: AppPlatformServices.interactionFeedback,
            inFlightFileChangeTracker: InFlightFileChangeTracker.shared
        )
    }
}
