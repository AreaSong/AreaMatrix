import AreaMatrixCoreBridgeContract
import AreaMatrixFeatureIngestion
import Foundation

/// Dependencies consumed by the content shell itself and its supporting routes.
struct MainRepositoryContentSupportDeps {
    let treeLister: any CoreRepositoryTreeListing
    let savedSearchStore: any CoreSavedSearchCRUD
    let batchRenamer: any CoreBatchRenaming
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let errorMapper: any CoreErrorMapping
    let syncConflictDetector: any CoreSyncConflictDetecting
    let noteStore: any CoreNoteReadingWriting
    let inFlightFileChangeTracker: any InFlightFileChangeTracking
    let dropCategoryPredictor: any CoreCategoryPredicting
}

/// Core collaborators used to construct the main list model.
struct MainRepositoryContentListDependencies {
    let fileLister: any CoreFileListing
    let fileDetailer: any CoreFileDetailing
    let missingFileRecoverer: any CoreMissingFileRecovering
    let missingFilePicker: any RepositoryMissingFilePicking
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
    let iCloudConflictResolver: any ICloudConflictResolving
    let tagStore: any CoreTagCRUD
    let aiSettingsLoader: any CoreAISettingsLoading
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let undoActionStore: any CoreUndoActionLogging
    let redoActionStore: any CoreRedoActionLogging
    let changeLogLister: any CoreChangeLogListing
    let externalChangesSyncer: any CoreExternalChangesSyncing
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let errorMapper: any CoreErrorMapping
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    let fileResourceAccess: any ImportFileResourceAccessing
}

/// Feature-owned scopes passed to the content shell.
struct MainRepositoryContentFeatureDependencies {
    let aiFeature: AIFeatureDependencies
    let fileActions: FileActionsFeatureDependencies
    let settings: SettingsFeatureDependencies
    let syncConflicts: SyncConflictsFeatureDependencies
}

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
    let makeCommandPaletteModel: () -> CommandPaletteModel
    let makeSyncConflictEntryModel: () -> SyncConflictEntryModel
    let makeDropPreviewModel: () -> ImportDropPreviewModel
    let makeDetailNoteModel: () -> DetailNoteModel
    let makeSummaryExitController: () -> AISummaryEditorExitController

    /// Composes the production assembly from the App-owned dependency graph.
    ///
    /// The explicit name keeps this boundary distinct from test factories and
    /// prevents `.live` convenience calls from becoming a feature dependency
    /// escape hatch.
    static func makeForProduction(
        session: RepositorySession,
        opening: RepositoryOpeningResult,
        dependencies: AppDependencyContainer
    ) -> Self {
        let core = dependencies.mainList
        let supporting = MainRepositoryContentSupportDeps(
            treeLister: core.treeLister,
            savedSearchStore: core.savedSearchStore,
            batchRenamer: core.batchRenamer,
            systemCapabilityChecker: dependencies.onboarding.systemCapabilityChecker,
            errorMapper: core.errorMapper,
            syncConflictDetector: core.syncConflictDetector,
            noteStore: core.noteStore,
            inFlightFileChangeTracker: dependencies.platform.inFlightFileChangeTracker,
            dropCategoryPredictor: core.categoryPredictor
        )
        let list = MainRepositoryContentListDependencies(
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
            categoryPredictor: core.categoryPredictor,
            batchDeleter: core.batchDeleter,
            batchCategoryChanger: core.batchCategoryChanger,
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
            errorMapper: core.errorMapper,
            diagnosticsCollector: core.diagnosticsCollector,
            fileResourceAccess: dependencies.feature.import.fileResourceAccess
        )
        let features = MainRepositoryContentFeatureDependencies(
            aiFeature: dependencies.feature.aiFeature,
            fileActions: dependencies.feature.fileActions,
            settings: dependencies.feature.settings,
            syncConflicts: dependencies.feature.syncConflicts
        )
        return make(session: session, opening: opening, supporting: supporting, list: list, features: features)
    }

    static func make(
        session: RepositorySession,
        opening: RepositoryOpeningResult,
        supporting: MainRepositoryContentSupportDeps,
        list: MainRepositoryContentListDependencies,
        features: MainRepositoryContentFeatureDependencies
    ) -> Self {
        Self(
            treeLister: supporting.treeLister,
            savedSearchStore: supporting.savedSearchStore,
            batchRenamer: supporting.batchRenamer,
            systemCapabilityChecker: supporting.systemCapabilityChecker,
            errorMapper: supporting.errorMapper,
            aiDependencies: features.aiFeature,
            fileActionsDependencies: features.fileActions,
            settingsDependencies: features.settings,
            syncConflictsDependencies: features.syncConflicts,
            makeFileListModel: fileListModelFactory(
                session: session,
                opening: opening,
                dependencies: list
            ),
            makeCommandPaletteModel: {
                CommandPaletteModel(
                    repoPath: opening.config.repoPath,
                    commandIndexer: list.commandIndexer,
                    errorMapper: supporting.errorMapper
                )
            },
            makeSyncConflictEntryModel: {
                SyncConflictEntryModel(
                    repoPath: opening.config.repoPath,
                    conflictDetector: supporting.syncConflictDetector,
                    errorMapper: supporting.errorMapper
                )
            },
            makeDropPreviewModel: {
                ImportDropPreviewModel(
                    repoPath: opening.config.repoPath,
                    predictor: supporting.dropCategoryPredictor,
                    resourceAccess: list.fileResourceAccess
                )
            },
            makeDetailNoteModel: {
                DetailNoteModel(
                    repoPath: opening.config.repoPath,
                    noteStore: supporting.noteStore,
                    errorMapper: supporting.errorMapper,
                    inFlightTracker: supporting.inFlightFileChangeTracker
                )
            },
            makeSummaryExitController: AISummaryEditorExitController.init
        )
    }

    private static func fileListModelFactory(
        session: RepositorySession,
        opening: RepositoryOpeningResult,
        dependencies: MainRepositoryContentListDependencies
    ) -> () -> MainFileListModel {
        let featureDependencies = MainListFeatureDependencies(
            fileResourceAccess: dependencies.fileResourceAccess,
            fileLister: dependencies.fileLister,
            fileDetailer: dependencies.fileDetailer,
            aiPrivacyRules: dependencies.aiPrivacyRules,
            aiSettingsLoader: dependencies.aiSettingsLoader,
            aiTagSuggestionStore: dependencies.aiTagSuggestionStore,
            batchCategoryChanger: dependencies.batchCategoryChanger,
            batchDeleter: dependencies.batchDeleter,
            categoryPredictor: dependencies.categoryPredictor,
            changeLogLister: dependencies.changeLogLister,
            externalChangesSyncer: dependencies.externalChangesSyncer,
            fileCategoryMover: dependencies.fileCategoryMover,
            fileDeleter: dependencies.fileDeleter,
            fileRenamer: dependencies.fileRenamer,
            iCloudConflictResolver: dependencies.iCloudConflictResolver,
            missingFileRecoverer: dependencies.missingFileRecoverer,
            missingFilePicker: dependencies.missingFilePicker,
            redoActionStore: dependencies.redoActionStore,
            searchFiltering: dependencies.searchFiltering,
            searchQuerying: dependencies.searchQuerying,
            semanticFallbackReader: dependencies.semanticFallbackReader,
            semanticSearching: dependencies.semanticSearching,
            tagStore: dependencies.tagStore,
            undoActionStore: dependencies.undoActionStore,
            repositoryWriteCoordinator: dependencies.repositoryWriteCoordinator,
            errorMapper: dependencies.errorMapper,
            diagnosticsCollector: dependencies.diagnosticsCollector
        )

        return {
            MainFileListModel(session: session, opening: opening, dependencies: featureDependencies)
        }
    }
}
