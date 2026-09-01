import AreaMatrixFeatureOperation
import SwiftUI

extension MainRepositoryContentView {
    var detailPane: some View {
        MainRepositoryDetailPane(
            selection: fileListModel.selection,
            multiSelectionSummary: MultiSelectionDetailSummary(
                selection: fileListModel.selection,
                files: mainListPresentation.visibleFiles,
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
            detailTagEditorState: detailTagModel.editorState,
            detailTagSuggestionState: detailTagModel.suggestionState,
            missingFileRelinkState: fileListModel.missingFileRelinkState,
            tagSuggestionPresentationRequest: detailTagModel.presentationRequest,
            detailTagUndoToast: detailTagModel.undoToast,
            detailTabRequest: fileListModel.detailTabRequest,
            selectedImportProgressRow: selectedImportProgressRow,
            semanticDetail: semanticDetailPresentationForSelectedFile,
            repoPath: opening.config.repoPath,
            aiDependencies: aiDependencies,
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
            onRetryExternalSync: fileListModel.retryExternalSync,
            tagActions: detailTagActions,
            onCopyPaths: onCopyPaths,
            onOpenNoteFile: onOpenNoteFile,
            onLocateMissingFile: { fileID in
                Task { await fileListModel.locateMissingFile(fileID: fileID) }
            },
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
            syncConflictCoordinator.reviewRoutingState.route = syncConflictEntryModel.reviewRoute(for: conflict)
            return
        }
        syncConflictCoordinator.reviewRoutingState.route = .fileDetail(repoPath: opening.config.repoPath, file: file)
    }

    func handleSyncConflictResolved(_: SyncConflictResolveReportSnapshot) async {
        syncConflictCoordinator.reviewRoutingState.route = nil
        await syncConflictEntryModel.refresh()
        await fileListModel.retryCurrentCategory()
    }

    // swiftlint:disable:next identifier_name
    private var semanticDetailPresentationForSelectedFile: SemanticSearchDetailPresentation? {
        guard let fileID = selectionModel.fileIDs.first, selectionModel.fileIDs.count == 1 else { return nil }
        return searchModel.searchState.page?.semanticPage?.detailPresentation(for: fileID)
    }
}
