import AreaMatrixCoreBridgeContract
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

    static let live = AppDependencyContainer(
        onboarding: Onboarding(
            pathValidator: AppCoreServices.repositoryPathValidator,
            initializedPathValidator: AppCoreServices.initializedRepositoryPathValidator,
            repositoryInitializer: AppCoreServices.repositoryInitializer,
            emptyRepositoryOpener: AppCoreServices.emptyRepositoryOpener,
            importProgressImporter: AppCoreServices.importProgressImporter,
            importResultChangeLister: AppCoreServices.changeLogLister,
            startupRecoverer: AppCoreServices.startupRecoverer,
            externalChangesSyncer: AppCoreServices.externalChangesSyncer,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator,
            scanSessionReader: AppCoreServices.scanSessionReader,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector,
            errorMapper: AppCoreServices.errorMapper,
            actionLogger: AppLogger.shared,
            systemCapabilityChecker: AppPlatformServices.systemCapabilityChecker,
            importProgressControlState: ImportProgressControlState()
        ),
        mainList: MainList(
            treeLister: AppCoreServices.treeLister,
            savedSearchStore: AppCoreServices.savedSearchStore,
            fileLister: AppCoreServices.fileLister,
            fileDetailer: AppCoreServices.fileDetailer,
            missingFileRecoverer: AppCoreServices.missingFileRecoverer,
            searchQuerying: AppCoreServices.searchQuerying,
            semanticSearching: AppCoreServices.semanticSearching,
            semanticFallbackReader: AppCoreServices.semanticFallbackReader,
            searchFiltering: AppCoreServices.searchFiltering,
            commandIndexer: AppCoreServices.commandIndexer,
            fileRenamer: AppCoreServices.fileRenamer,
            fileDeleter: AppCoreServices.fileDeleter,
            fileCategoryMover: AppCoreServices.fileCategoryMover,
            categoryPredictor: AppCoreServices.categoryPredictor,
            batchDeleter: AppCoreServices.batchDeleter,
            batchCategoryChanger: AppCoreServices.batchCategoryChanger,
            batchRenamer: AppCoreServices.batchRenamer,
            syncConflictDetector: AppCoreServices.syncConflictDetector,
            iCloudConflictResolver: AppCoreServices.iCloudConflictResolver,
            tagStore: AppCoreServices.tagStore,
            aiSettingsLoader: AppCoreServices.aiSettingsLoader,
            aiTagSuggestionStore: AppCoreServices.aiTagSuggestionStore,
            aiPrivacyRules: AppCoreServices.aiPrivacyRules,
            undoActionStore: AppCoreServices.undoActionStore,
            redoActionStore: AppCoreServices.redoActionStore,
            changeLogLister: AppCoreServices.changeLogLister,
            externalChangesSyncer: AppCoreServices.externalChangesSyncer,
            noteStore: AppCoreServices.noteStore,
            errorMapper: AppCoreServices.errorMapper,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector
        ),
        platform: Platform(
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
        ),
        feature: .live
    )
}
