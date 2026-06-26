import SwiftUI

struct MainRepositoryMultiSelectionActions: View {
    let selection: MainFileSelectionState
    let summary: MultiSelectionDetailSummary
    let detailErrorMapping: CoreErrorMappingSnapshot?
    let repoPath: String
    let categoryRows: [RepositorySidebarRowSnapshot]
    let batchTagStore: any CoreTagCRUD
    let batchTagUndoStore: any CoreUndoActionLogging
    let batchTagErrorMapper: any CoreErrorMapping
    let batchDeleter: any CoreBatchDeleting
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let batchRenamer: any CoreBatchRenaming
    let tagActions: MainRepositoryDetailPaneTagActions
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    let onCopyPaths: ([String]) -> Void
    let onRetrySelectedFileDetail: () -> Void
    let onRefreshChangeLog: () -> Void
    let onBatchCategoryApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onBatchDeleteApplied: (BatchDeleteReportSnapshot) -> Void
    let onBatchRenameApplied: (BatchRenameReportSnapshot) -> Void
    let onBatchCategoryCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Show in Finder") {}
                .disabled(true)
                .help("Open one file at a time")
            Text("Open one file at a time")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Copy Paths") {
                onCopyPaths(summary.paths)
            }
            .disabled(summary.paths.isEmpty)
            BatchAddTagsTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedCount: summary.selectedCount,
                disabledReason: batchAddTagsDisabledReason,
                tagStore: batchTagStore,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onRefreshSelection: onRetrySelectedFileDetail,
                onRefreshChangeLog: onRefreshChangeLog,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchAITagSuggestionTrigger(
                repoPath: repoPath,
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchAddTagsDisabledReason,
                state: tagActions.aiBatchSuggestionState,
                actions: tagActions.aiBatchActions,
                onOpenAISettings: tagActions.onOpenAISettings
            )
            BatchChangeCategoryTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchChangeCategoryDisabledReason,
                categoryRows: categoryRows,
                changer: batchCategoryChanger,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchCategoryApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange,
                onCreateNewCategory: onBatchCategoryCreateNewCategory
            )
            BatchRenameTrigger(
                repoPath: repoPath,
                fileIDs: BatchRenameEntryPolicy.fileIDsForPreview(summary: summary),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchRenameDisabledReason,
                renamer: batchRenamer,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchRenameApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchDeleteTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchDeleteDisabledReason,
                deleter: batchDeleter,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchDeleteApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            if detailErrorMapping != nil {
                Button("Retry Metadata", action: onRetrySelectedFileDetail)
            }
        }
    }

    private var batchAddTagsDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        return writeDisabledReason
    }

    private var batchChangeCategoryDisabledReason: String? {
        batchAddTagsDisabledReason
    }

    private var batchDeleteDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if summary.isUpdating { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        return writeDisabledReason
    }

    private var batchRenameDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if summary.isUpdating { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        return writeDisabledReason
    }

    private var writeDisabledReason: String? {
        summary.files.compactMap { writeActionDisabledReason($0.id)?.rawValue }.first
    }
}
