import Foundation

enum AppCoreServices {
    static let repositoryWriteCoordinator = RepositoryWriteCoordinator.shared
    @MainActor static var overviewRegenerationCoordinator: OverviewRegenerationCoordinator {
        .shared
    }

    static var treeLister: any CoreRepositoryTreeListing {
        coreBridge()
    }

    static var savedSearchStore: any CoreSavedSearchCRUD {
        coreBridge()
    }

    static var configurationLoader: any CoreConfigurationLoading {
        coreBridge()
    }

    static var configurationUpdater: any CoreConfigurationUpdating {
        coreBridge()
    }

    static var emptyRepositoryOpener: any CoreEmptyRepositoryOpening {
        coreBridge()
    }

    static var repositoryPathValidator: any CoreRepositoryPathValidating {
        coreBridge()
    }

    static var initializedRepositoryPathValidator: any CoreInitializedRepositoryPathValidating {
        coreBridge()
    }

    static var scanSessionReader: any CoreScanSessionReading {
        coreBridge()
    }

    static var fileLister: any CoreFileListing {
        coreBridge()
    }

    static var fileDetailer: any CoreFileDetailing {
        coreBridge()
    }

    static var missingFileRecoverer: any CoreMissingFileRecovering {
        coreBridge()
    }

    static var searchQuerying: any CoreSearchQuerying {
        coreBridge()
    }

    static var semanticSearching: any CoreSemanticSearching {
        coreBridge()
    }

    static var semanticFallbackReader: any CoreSemanticFallbackStatusReading {
        coreBridge()
    }

    static var searchFiltering: any CoreSearchFiltering {
        coreBridge()
    }

    static var commandIndexer: any CoreCommandIndexing {
        coreBridge()
    }

    static var bindingContractInspector: any CoreBindingContractInspecting {
        coreBridge()
    }

    static var fileRenamer: any CoreFileRenaming {
        coreBridge()
    }

    static var fileDeleter: any CoreFileDeleting {
        coreBridge()
    }

    static var fileCategoryMover: any CoreFileCategoryMoving {
        coreBridge()
    }

    static var categoryPredictor: any CoreCategoryPredicting {
        coreBridge()
    }

    static var classifierRuleSaver: any CoreClassifierRuleSaving {
        coreBridge()
    }

    static var classifierImpactPreviewer: any CoreClassifierImpactPreviewing {
        coreBridge()
    }

    static var classifierRuleEditor: any CoreClassifierRuleEditing {
        coreBridge()
    }

    static var platformCapabilityLoader: any CorePlatformCapabilitiesLoading {
        coreBridge()
    }

    static var batchDeleter: any CoreBatchDeleting {
        coreBridge()
    }

    static var batchCategoryChanger: any CoreBatchCategoryChanging {
        coreBridge()
    }

    static var batchRenamer: any CoreBatchRenaming {
        coreBridge()
    }

    static var syncConflictDetector: any CoreSyncConflictDetecting {
        coreBridge()
    }

    static var iCloudConflictLister: any CoreICloudConflictListing {
        coreBridge()
    }

    static var iCloudConflictReviewer: any CoreICloudConflictReviewing {
        coreBridge()
    }

    static var iCloudConflictResolver: any ICloudConflictResolving {
        coreBridge()
    }

    static var tagStore: any CoreTagCRUD {
        coreBridge()
    }

    static var aiSettingsLoader: any CoreAISettingsLoading {
        coreBridge()
    }

    static var aiSettingsUpdater: any CoreAISettingsUpdating {
        coreBridge()
    }

    static var aiTagSuggestionStore: any CoreAITagSuggestionManaging {
        coreBridge()
    }

    static var aiClassificationSuggester: any CoreAIClassificationSuggesting {
        coreBridge()
    }

    static var aiClassificationFallbackReader: any CoreAIClassificationFallbackStatusReading {
        coreBridge()
    }

    static var remoteProviderConfigurer: any CoreRemoteProviderConfiguring {
        coreBridge()
    }

    static var aiCallLogLister: any CoreAICallLogListing {
        coreBridge()
    }

    static var aiCallLogClearer: any CoreAICallLogClearing {
        coreBridge()
    }

    static var aiSummaryStore: any CoreAISummaryManaging {
        coreBridge()
    }

    static var repositoryContentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting {
        coreBridge()
    }

    static var overviewRegenerator: any CoreOverviewRegenerating {
        coreBridge()
    }

    static var localModelStatusReader: any CoreLocalModelStatusReading {
        coreBridge()
    }

    static var aiPrivacyRules: any CoreAIPrivacyEvaluating {
        coreBridge()
    }

    static var aiPrivacyRulesManager: any CoreAIPrivacyRulesManaging {
        coreBridge()
    }

    static var undoActionStore: any CoreUndoActionLogging {
        coreBridge()
    }

    static var redoActionStore: any CoreRedoActionLogging {
        coreBridge()
    }

    static var changeLogLister: any CoreChangeLogListing {
        coreBridge()
    }

    static var externalChangesSyncer: any CoreExternalChangesSyncing {
        coreBridge()
    }

    static var coreVersionLoader: any CoreVersionLoading {
        coreBridge()
    }

    static var coreVersionReader: any CoreVersionReading {
        coreBridge()
    }

    static var noteStore: any CoreNoteReadingWriting {
        coreBridge()
    }

    static var errorMapper: any CoreErrorMapping {
        coreBridge()
    }

    static var diagnosticsCollector: any CoreDiagnosticsCollecting {
        coreBridge()
    }

    private static func coreBridge() -> CoreBridge {
        CoreBridge()
    }
}

@MainActor
struct MainRepositoryContentAssembly {
    let treeLister: any CoreRepositoryTreeListing
    let savedSearchStore: any CoreSavedSearchCRUD
    let batchRenamer: any CoreBatchRenaming
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let errorMapper: any CoreErrorMapping
    let makeFileListModel: () -> MainFileListModel
    let makeSyncConflictEntryModel: () -> SyncConflictEntryModel
    let makeDropPreviewModel: () -> ImportDropPreviewModel
    let makeDetailNoteModel: () -> DetailNoteModel
    let makeSummaryExitController: () -> AISummaryEditorExitController

    static func live(opening: RepositoryOpeningResult) -> Self {
        make(opening: opening)
    }

    // swiftlint:disable:next function_body_length
    static func make(
        opening: RepositoryOpeningResult,
        treeLister: any CoreRepositoryTreeListing = AppCoreServices.treeLister,
        savedSearchStore: any CoreSavedSearchCRUD = AppCoreServices.savedSearchStore,
        fileLister: any CoreFileListing = AppCoreServices.fileLister,
        fileDetailer: any CoreFileDetailing = AppCoreServices.fileDetailer,
        searchQuerying: any CoreSearchQuerying = AppCoreServices.searchQuerying,
        semanticSearching: any CoreSemanticSearching = AppCoreServices.semanticSearching,
        semanticFallbackReader: any CoreSemanticFallbackStatusReading = AppCoreServices.semanticFallbackReader,
        searchFiltering: any CoreSearchFiltering = AppCoreServices.searchFiltering,
        commandIndexer: any CoreCommandIndexing = AppCoreServices.commandIndexer,
        fileRenamer: any CoreFileRenaming = AppCoreServices.fileRenamer,
        fileDeleter: any CoreFileDeleting = AppCoreServices.fileDeleter,
        fileCategoryMover: any CoreFileCategoryMoving = AppCoreServices.fileCategoryMover,
        fileListCategoryPredictor: any CoreCategoryPredicting = AppCoreServices.categoryPredictor,
        batchDeleter: any CoreBatchDeleting = AppCoreServices.batchDeleter,
        batchCategoryChanger: any CoreBatchCategoryChanging = AppCoreServices.batchCategoryChanger,
        batchRenamer: any CoreBatchRenaming = AppCoreServices.batchRenamer,
        systemCapabilityChecker: any OnboardingSystemCapabilityChecking = AppPlatformServices.systemCapabilityChecker,
        syncConflictDetector: any CoreSyncConflictDetecting = AppCoreServices.syncConflictDetector,
        iCloudConflictResolver: any ICloudConflictResolving = AppCoreServices.iCloudConflictResolver,
        tagStore: any CoreTagCRUD = AppCoreServices.tagStore,
        aiSettingsLoader: any CoreAISettingsLoading = AppCoreServices.aiSettingsLoader,
        aiTagSuggestionStore: any CoreAITagSuggestionManaging = AppCoreServices.aiTagSuggestionStore,
        aiPrivacyRules: any CoreAIPrivacyEvaluating = AppCoreServices.aiPrivacyRules,
        undoActionStore: any CoreUndoActionLogging = AppCoreServices.undoActionStore,
        redoActionStore: any CoreRedoActionLogging = AppCoreServices.redoActionStore,
        changeLogLister: any CoreChangeLogListing = AppCoreServices.changeLogLister,
        externalChangesSyncer: any CoreExternalChangesSyncing = AppCoreServices.externalChangesSyncer,
        repositoryWriteCoordinator: RepositoryWriteCoordinator = AppCoreServices.repositoryWriteCoordinator,
        noteStore: any CoreNoteReadingWriting = AppCoreServices.noteStore,
        dropCategoryPredictor: any CoreCategoryPredicting = AppCoreServices.categoryPredictor,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector
    ) -> Self {
        Self(
            treeLister: treeLister,
            savedSearchStore: savedSearchStore,
            batchRenamer: batchRenamer,
            systemCapabilityChecker: systemCapabilityChecker,
            errorMapper: errorMapper,
            makeFileListModel: fileListModelFactory(
                opening: opening,
                fileLister: fileLister,
                fileDetailer: fileDetailer,
                searchQuerying: searchQuerying,
                semanticSearching: semanticSearching,
                semanticFallbackReader: semanticFallbackReader,
                searchFiltering: searchFiltering,
                commandIndexer: commandIndexer,
                fileRenamer: fileRenamer,
                fileDeleter: fileDeleter,
                fileCategoryMover: fileCategoryMover,
                categoryPredictor: fileListCategoryPredictor,
                batchDeleter: batchDeleter,
                batchCategoryChanger: batchCategoryChanger,
                iCloudConflictResolver: iCloudConflictResolver,
                tagStore: tagStore,
                aiSettingsLoader: aiSettingsLoader,
                aiTagSuggestionStore: aiTagSuggestionStore,
                aiPrivacyRules: aiPrivacyRules,
                undoActionStore: undoActionStore,
                redoActionStore: redoActionStore,
                changeLogLister: changeLogLister,
                externalChangesSyncer: externalChangesSyncer,
                repositoryWriteCoordinator: repositoryWriteCoordinator,
                errorMapper: errorMapper,
                diagnosticsCollector: diagnosticsCollector
            ),
            makeSyncConflictEntryModel: {
                SyncConflictEntryModel(
                    repoPath: opening.config.repoPath,
                    conflictDetector: syncConflictDetector,
                    errorMapper: errorMapper
                )
            },
            makeDropPreviewModel: {
                ImportDropPreviewModel(
                    repoPath: opening.config.repoPath,
                    predictor: dropCategoryPredictor
                )
            },
            makeDetailNoteModel: {
                DetailNoteModel(
                    repoPath: opening.config.repoPath,
                    noteStore: noteStore,
                    errorMapper: errorMapper
                )
            },
            makeSummaryExitController: AISummaryEditorExitController.init
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func fileListModelFactory(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
        searchQuerying: any CoreSearchQuerying,
        semanticSearching: any CoreSemanticSearching,
        semanticFallbackReader: any CoreSemanticFallbackStatusReading,
        searchFiltering: any CoreSearchFiltering,
        commandIndexer: any CoreCommandIndexing,
        fileRenamer: any CoreFileRenaming,
        fileDeleter: any CoreFileDeleting,
        fileCategoryMover: any CoreFileCategoryMoving,
        categoryPredictor: any CoreCategoryPredicting,
        batchDeleter: any CoreBatchDeleting,
        batchCategoryChanger: any CoreBatchCategoryChanging,
        iCloudConflictResolver: any ICloudConflictResolving,
        tagStore: any CoreTagCRUD,
        aiSettingsLoader: any CoreAISettingsLoading,
        aiTagSuggestionStore: any CoreAITagSuggestionManaging,
        aiPrivacyRules: any CoreAIPrivacyEvaluating,
        undoActionStore: any CoreUndoActionLogging,
        redoActionStore: any CoreRedoActionLogging,
        changeLogLister: any CoreChangeLogListing,
        externalChangesSyncer: any CoreExternalChangesSyncing,
        repositoryWriteCoordinator: RepositoryWriteCoordinator,
        errorMapper: any CoreErrorMapping,
        diagnosticsCollector: any CoreDiagnosticsCollecting
    ) -> () -> MainFileListModel {
        {
            MainFileListModel(
                opening: opening,
                fileLister: fileLister,
                fileDetailer: fileDetailer,
                searchQuerying: searchQuerying,
                semanticSearching: semanticSearching,
                semanticFallbackReader: semanticFallbackReader,
                searchFiltering: searchFiltering,
                commandIndexer: commandIndexer,
                fileRenamer: fileRenamer,
                fileDeleter: fileDeleter,
                fileCategoryMover: fileCategoryMover,
                categoryPredictor: categoryPredictor,
                batchDeleter: batchDeleter,
                batchCategoryChanger: batchCategoryChanger,
                iCloudConflictResolver: iCloudConflictResolver,
                tagStore: tagStore,
                aiSettingsLoader: aiSettingsLoader,
                aiTagSuggestionStore: aiTagSuggestionStore,
                aiPrivacyRules: aiPrivacyRules,
                undoActionStore: undoActionStore,
                redoActionStore: redoActionStore,
                changeLogLister: changeLogLister,
                externalChangesSyncer: externalChangesSyncer,
                repositoryWriteCoordinator: repositoryWriteCoordinator,
                errorMapper: errorMapper,
                diagnosticsCollector: diagnosticsCollector
            )
        }
    }
}
