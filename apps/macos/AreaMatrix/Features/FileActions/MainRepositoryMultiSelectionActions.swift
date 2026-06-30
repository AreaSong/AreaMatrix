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
        let defaultContext = MainFileBatchActionTriggerContext.defaultAction(
            selection: selection,
            summary: summary,
            writeActionDisabledReason: writeActionDisabledReason
        )
        let updatingBlockedContext = MainFileBatchActionTriggerContext.updatingBlockedAction(
            selection: selection,
            summary: summary,
            writeActionDisabledReason: writeActionDisabledReason
        )
        let renameContext = MainFileBatchActionTriggerContext.renamePreview(
            summary: summary,
            writeActionDisabledReason: writeActionDisabledReason
        )

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
                fileIDs: defaultContext.fileIDs,
                selectedCount: defaultContext.selectedCount,
                disabledReason: defaultContext.disabledReason,
                tagStore: batchTagStore,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onRefreshSelection: onRetrySelectedFileDetail,
                onRefreshChangeLog: onRefreshChangeLog,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchAITagSuggestionTrigger(
                repoPath: repoPath,
                selectedFiles: defaultContext.selectedFiles,
                selectedCount: defaultContext.selectedCount,
                disabledReason: defaultContext.disabledReason,
                state: tagActions.aiBatchSuggestionState,
                actions: tagActions.aiBatchActions,
                onOpenAISettings: tagActions.onOpenAISettings
            )
            BatchChangeCategoryTrigger(
                repoPath: repoPath,
                fileIDs: defaultContext.fileIDs,
                selectedFiles: defaultContext.selectedFiles,
                selectedCount: defaultContext.selectedCount,
                disabledReason: defaultContext.disabledReason,
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
                fileIDs: renameContext.fileIDs,
                selectedFiles: renameContext.selectedFiles,
                selectedCount: renameContext.selectedCount,
                disabledReason: renameContext.disabledReason,
                renamer: batchRenamer,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchRenameApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchDeleteTrigger(
                repoPath: repoPath,
                fileIDs: updatingBlockedContext.fileIDs,
                selectedFiles: updatingBlockedContext.selectedFiles,
                selectedCount: updatingBlockedContext.selectedCount,
                disabledReason: updatingBlockedContext.disabledReason,
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
}
