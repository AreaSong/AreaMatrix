@testable import AreaMatrix

extension MainRepositoryDetailPaneTagActions {
    static var noop: MainRepositoryDetailPaneTagActions {
        let noAction: () -> Void = {}
        let noStringAction: (String) -> Void = { _ in }
        let noEditAction: (String, String) -> Void = { _, _ in }
        let noBatchAction: (BatchTagUndoState) -> Void = { _ in }
        return MainRepositoryDetailPaneTagActions(
            aiSuggestionState: .idle,
            aiBatchSuggestionState: .idle,
            onLoadTags: noAction,
            onRetryTags: noAction,
            onAddTag: noStringAction,
            onRemoveTag: noStringAction,
            onLoadSuggestions: noAction,
            onRetrySuggestions: noAction,
            onToggleSuggestion: noStringAction,
            onSelectAllSuggestions: noAction,
            onClearSuggestions: noAction,
            onStartEditingSuggestions: noAction,
            onCancelEditingSuggestions: noAction,
            onEditSuggestionDisplayName: noEditAction,
            onEditSuggestionSlug: noEditAction,
            onRegenerateSuggestionSlug: noStringAction,
            onApplySuggestions: noAction,
            onApplyEditedSuggestions: noAction,
            onRetryFailedSuggestions: noAction,
            onLoadAISuggestions: noAction,
            onRetryAISuggestions: noAction,
            onToggleAISuggestion: noStringAction,
            onApplySingleAISuggestion: noStringAction,
            onSelectHighConfidenceAISuggestions: noAction,
            onClearAISuggestions: noAction,
            onStartEditingAISuggestions: noAction,
            onCancelEditingAISuggestions: noAction,
            onEditAISuggestionDisplayName: noEditAction,
            onEditAISuggestionSlug: noEditAction,
            onRegenerateAISuggestionSlug: noStringAction,
            onApplyAISuggestions: noAction,
            onApplyEditedAISuggestions: noAction,
            onRetryFailedAISuggestions: noAction,
            aiBatchActions: .noop,
            onOpenAISettings: noAction,
            onSuggestionPresentationConsumed: { _ in },
            onUndoTagChange: noAction,
            onDismissTagUndoToast: noAction,
            onBatchTagUndoStateChange: noBatchAction
        )
    }
}

actor DetailTagFileDetailer: CoreFileDetailing {
    private let filesByID: [Int64: FileEntrySnapshot]

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }
}

extension MainFileListModel {
    @MainActor
    static func makeTagSuggestionsModel(
        detail: FileEntrySnapshot,
        tagStore: any CoreTagCRUD = DetailTagRecordingStore()
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )
    }
}
