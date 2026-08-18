import Foundation

/// Construction-only grouping for the models owned by the Library surface.
///
/// Keeping this assembly separate leaves `MainFileListModel` responsible for
/// repository state and actions while the App composition layer still controls
/// every concrete dependency.
@MainActor
struct MainFileListOwnedModels {
    let diagnostics: MainListDiagnosticsModel
    let search: SearchModel
    let detailTag: DetailTagModel
    let syncConflict: SyncConflictCoordinator
    let fileAction: FileActionCoordinator

    init(repoPath: String, dependencies: MainListFeatureDependencies) {
        diagnostics = MainListDiagnosticsModel(
            repoPath: repoPath,
            diagnosticsCollector: dependencies.diagnosticsCollector,
            errorMapper: dependencies.errorMapper
        )
        search = SearchModel(
            repoPath: repoPath,
            dependencies: SearchModelDependencies(
                searchQuerying: dependencies.searchQuerying,
                semanticSearching: dependencies.semanticSearching,
                semanticFallbackReader: dependencies.semanticFallbackReader,
                searchFiltering: dependencies.searchFiltering,
                aiPrivacyRules: dependencies.aiPrivacyRules,
                errorMapper: dependencies.errorMapper
            )
        )
        detailTag = DetailTagModel(
            repoPath: repoPath,
            tagStore: dependencies.tagStore,
            aiSettingsLoader: dependencies.aiSettingsLoader,
            aiTagSuggestionStore: dependencies.aiTagSuggestionStore,
            aiPrivacyRules: dependencies.aiPrivacyRules,
            undoActionStore: dependencies.undoActionStore,
            errorMapper: dependencies.errorMapper
        )
        syncConflict = SyncConflictCoordinator(
            repoPath: repoPath,
            resolver: dependencies.iCloudConflictResolver,
            errorMapper: dependencies.errorMapper
        )
        fileAction = FileActionCoordinator(
            repoPath: repoPath,
            fileRenamer: dependencies.fileRenamer,
            fileDeleter: dependencies.fileDeleter,
            fileCategoryMover: dependencies.fileCategoryMover,
            categoryPredictor: dependencies.categoryPredictor,
            errorMapper: dependencies.errorMapper
        )
    }
}
