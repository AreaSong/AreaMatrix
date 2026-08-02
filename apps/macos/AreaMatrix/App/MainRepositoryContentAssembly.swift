import Foundation

@MainActor
struct MainRepositoryContentAssembly {
    let treeLister: any CoreRepositoryTreeListing
    let savedSearchStore: any CoreSavedSearchCRUD
    let batchRenamer: any CoreBatchRenaming
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let errorMapper: any CoreErrorMapping
    let aiDependencies: AIFeatureDependencies
    let fileActionsDependencies: FileActionsFeatureDependencies
    let settingsDependencies: SettingsFeatureDependencies
    let syncConflictsDependencies: SyncConflictsFeatureDependencies
    let makeFileListModel: () -> MainFileListModel
    let makeSyncConflictEntryModel: () -> SyncConflictEntryModel
    let makeDropPreviewModel: () -> ImportDropPreviewModel
    let makeDetailNoteModel: () -> DetailNoteModel
    let makeSummaryExitController: () -> AISummaryEditorExitController

    static func live(
        opening: RepositoryOpeningResult,
        dependencies: AppDependencyContainer
    ) -> Self {
        let core = dependencies.mainList
        return make(
            opening: opening,
            treeLister: core.treeLister,
            savedSearchStore: core.savedSearchStore,
            fileLister: core.fileLister,
            fileDetailer: core.fileDetailer,
            missingFileRecoverer: core.missingFileRecoverer,
            missingFilePicker: dependencies.platform.missingFilePicker,
            searchQuerying: core.searchQuerying,
            semanticSearching: core.semanticSearching,
            semanticFallbackReader: core.semanticFallbackReader,
            searchFiltering: core.searchFiltering,
            commandIndexer: core.commandIndexer,
            fileRenamer: core.fileRenamer,
            fileDeleter: core.fileDeleter,
            fileCategoryMover: core.fileCategoryMover,
            fileListCategoryPredictor: core.categoryPredictor,
            batchDeleter: core.batchDeleter,
            batchCategoryChanger: core.batchCategoryChanger,
            batchRenamer: core.batchRenamer,
            systemCapabilityChecker: dependencies.onboarding.systemCapabilityChecker,
            syncConflictDetector: core.syncConflictDetector,
            iCloudConflictResolver: core.iCloudConflictResolver,
            tagStore: core.tagStore,
            aiSettingsLoader: core.aiSettingsLoader,
            aiTagSuggestionStore: core.aiTagSuggestionStore,
            aiPrivacyRules: core.aiPrivacyRules,
            undoActionStore: core.undoActionStore,
            redoActionStore: core.redoActionStore,
            changeLogLister: core.changeLogLister,
            externalChangesSyncer: core.externalChangesSyncer,
            repositoryWriteCoordinator: dependencies.onboarding.repositoryWriteCoordinator,
            noteStore: core.noteStore,
            dropCategoryPredictor: core.categoryPredictor,
            errorMapper: core.errorMapper,
            diagnosticsCollector: core.diagnosticsCollector,
            aiDependencies: dependencies.feature.ai,
            fileActionsDependencies: dependencies.feature.fileActions,
            settingsDependencies: dependencies.feature.settings,
            syncConflictsDependencies: dependencies.feature.syncConflicts
        )
    }

    // swiftlint:disable:next function_body_length
    static func make(
        opening: RepositoryOpeningResult,
        treeLister: any CoreRepositoryTreeListing = AppCoreServices.treeLister,
        savedSearchStore: any CoreSavedSearchCRUD = AppCoreServices.savedSearchStore,
        fileLister: any CoreFileListing = AppCoreServices.fileLister,
        fileDetailer: any CoreFileDetailing = AppCoreServices.fileDetailer,
        missingFileRecoverer: any CoreMissingFileRecovering = AppCoreServices.missingFileRecoverer,
        missingFilePicker: any RepositoryMissingFilePicking = AppPlatformServices.missingFilePicker,
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
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector,
        aiDependencies: AIFeatureDependencies,
        fileActionsDependencies: FileActionsFeatureDependencies,
        settingsDependencies: SettingsFeatureDependencies,
        syncConflictsDependencies: SyncConflictsFeatureDependencies
    ) -> Self {
        Self(
            treeLister: treeLister,
            savedSearchStore: savedSearchStore,
            batchRenamer: batchRenamer,
            systemCapabilityChecker: systemCapabilityChecker,
            errorMapper: errorMapper,
            aiDependencies: aiDependencies,
            fileActionsDependencies: fileActionsDependencies,
            settingsDependencies: settingsDependencies,
            syncConflictsDependencies: syncConflictsDependencies,
            makeFileListModel: fileListModelFactory(
                opening: opening,
                fileLister: fileLister,
                fileDetailer: fileDetailer,
                missingFileRecoverer: missingFileRecoverer,
                missingFilePicker: missingFilePicker,
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
        missingFileRecoverer: any CoreMissingFileRecovering,
        missingFilePicker: any RepositoryMissingFilePicking,
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
        let dependencies = MainListFeatureDependencies(
            fileLister: fileLister,
            fileDetailer: fileDetailer,
            aiPrivacyRules: aiPrivacyRules,
            aiSettingsLoader: aiSettingsLoader,
            aiTagSuggestionStore: aiTagSuggestionStore,
            batchCategoryChanger: batchCategoryChanger,
            batchDeleter: batchDeleter,
            categoryPredictor: categoryPredictor,
            changeLogLister: changeLogLister,
            commandIndexer: commandIndexer,
            externalChangesSyncer: externalChangesSyncer,
            fileCategoryMover: fileCategoryMover,
            fileDeleter: fileDeleter,
            fileRenamer: fileRenamer,
            iCloudConflictResolver: iCloudConflictResolver,
            missingFileRecoverer: missingFileRecoverer,
            missingFilePicker: missingFilePicker,
            redoActionStore: redoActionStore,
            searchFiltering: searchFiltering,
            searchQuerying: searchQuerying,
            semanticFallbackReader: semanticFallbackReader,
            semanticSearching: semanticSearching,
            tagStore: tagStore,
            undoActionStore: undoActionStore,
            repositoryWriteCoordinator: repositoryWriteCoordinator,
            errorMapper: errorMapper,
            diagnosticsCollector: diagnosticsCollector
        )

        return {
            MainFileListModel(
                opening: opening,
                dependencies: dependencies
            )
        }
    }
}
