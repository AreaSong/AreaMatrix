import SwiftUI

extension MainRepositoryContentView {
    var detailPane: some View {
        MainRepositoryDetailPane(
            selection: fileListModel.selection,
            multiSelectionSummary: MultiSelectionDetailSummary(
                selection: fileListModel.selection,
                files: visibleFiles,
                isUpdating: fileListModel.isLoading || fileListModel.isDetailLoading
            ),
            detailErrorMapping: fileListModel.detailErrorMapping,
            syncConflict: syncConflictEntryModel.detailConflict(for: fileListModel.selectedFileDetail),
            isDetailLoading: fileListModel.isDetailLoading,
            selectedFileDetail: fileListModel.selectedFileDetail,
            noteWriteBlock: fileListModel.selectedFileNoteWriteBlock,
            detailLogState: fileListModel.detailLogState,
            detailLogDiagnosticsState: fileListModel.detailLogDiagnosticsState,
            detailExternalCreateSyncState: fileListModel.detailExternalCreateSyncState,
            detailTagEditorState: fileListModel.detailTagEditorState,
            detailTagSuggestionState: fileListModel.detailTagSuggestionState,
            tagSuggestionPresentationRequest: fileListModel.tagSuggestionPresentationRequest,
            detailTagUndoToast: fileListModel.detailTagUndoToast,
            detailTabRequest: fileListModel.detailTabRequest,
            selectedImportProgressRow: selectedImportProgressRow,
            semanticDetail: semanticDetailPresentationForSelectedFile,
            repoPath: opening.config.repoPath,
            batchTagStore: fileListModel.tagStore,
            batchTagUndoStore: fileListModel.undoActionStore,
            batchTagErrorMapper: fileListModel.errorMapper,
            batchDeleter: fileListModel.batchDeleter, batchCategoryChanger: fileListModel.batchCategoryChanger,
            batchRenamer: batchRenamer,
            categoryRows: repositoryTree.sidebarRows,
            onBatchCategoryApplied: applyBatchCategoryChangeResult,
            onBatchDeleteApplied: applyBatchDeleteResult, onBatchRenameApplied: applyBatchRenameResult,
            onBatchCategoryCreateNewCategory: { handoff in
                openClassifierRuleEditorFromBatchCategory(handoff, route: commandPaletteBatchChangeCategoryRoute())
            },
            onRetrySelectedFileDetail: { Task { await fileListModel.retrySelectedFileDetail() } },
            tagActions: detailTagActions,
            onCopyPaths: onCopyPaths,
            onOpenNoteFile: onOpenNoteFile,
            onRefreshChangeLog: {
                Task {
                    await fileListModel.loadSelectedFileChangeLog()
                }
            },
            onRequestDetailLogDiagnostics: fileListModel.requestDetailLogDiagnosticsPrivacyConfirmation,
            onConfirmDetailLogDiagnostics: {
                Task {
                    await fileListModel.collectDetailLogDiagnostics()
                }
            },
            onCancelDetailLogDiagnostics: fileListModel.cancelDetailLogDiagnosticsPrivacyConfirmation,
            onDetailTabRequestConsumed: fileListModel.consumeDetailTabRequest,
            onBeginRenameFile: fileListModel.beginRename,
            onBeginChangeCategoryFile: fileListModel.beginChangeCategory,
            onBeginClassifierCorrectionFile: fileListModel.beginClassifierCorrection,
            onBeginAIClassificationSuggestionFile: fileListModel.beginAIClassificationSuggestion,
            onBeginDeleteFile: fileListModel.beginDelete,
            onBeginICloudConflictResolution: fileListModel.beginICloudConflictResolution,
            onBeginSyncConflictReview: beginSyncConflictReview,
            onOpenAISettings: onOpenAISettings,
            writeActionDisabledReason: fileListModel.writeActionDisabledReason,
            canPerformWriteAction: fileListModel.canPerformWriteAction,
            summaryExitController: summaryExitController,
            noteModel: detailNoteModel
        )
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
    }

    func beginSyncConflictReview(file: FileEntrySnapshot) {
        if let conflict = syncConflictEntryModel.detailConflict(for: file) {
            pendingSyncConflictReviewRoute = syncConflictEntryModel.reviewRoute(for: conflict)
            return
        }
        pendingSyncConflictReviewRoute = .fileDetail(repoPath: opening.config.repoPath, file: file)
    }

    func syncConflictReviewSheet(_ route: SyncConflictReviewRoute) -> some View {
        SyncConflictReviewView(
            model: SyncConflictReviewModel(
                repoPath: route.repoPath,
                conflictID: route.conflictID,
                primaryPath: route.primaryPath
            ),
            onBackToNeedsReview: { pendingSyncConflictReviewRoute = nil },
            onClose: { pendingSyncConflictReviewRoute = nil },
            onResolved: handleSyncConflictResolved
        )
    }

    func handleSyncConflictResolved(_: SyncConflictResolveReportSnapshot) async {
        pendingSyncConflictReviewRoute = nil
        await syncConflictEntryModel.refresh()
        await fileListModel.retryCurrentCategory()
    }

    // swiftlint:disable:next identifier_name
    private var semanticDetailPresentationForSelectedFile: SemanticSearchDetailPresentation? {
        guard let fileID = selectedFileIDs.first, selectedFileIDs.count == 1 else { return nil }
        return fileListModel.searchState.page?.semanticPage?.detailPresentation(for: fileID)
    }
}
