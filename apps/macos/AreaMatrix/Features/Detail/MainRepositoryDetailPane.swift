import AreaMatrixFeatureLibrary
import AreaMatrixFeatureOperation
import SwiftUI

extension DetailPaneTab {
    var title: String {
        switch self {
        case .meta:
            L10n.string("Meta")
        case .summary:
            L10n.string("Summary")
        case .log:
            L10n.string("Log")
        case .note:
            L10n.string("Note")
        }
    }
}

struct MainRepositoryDetailPane: View {
    let selection: MainFileSelectionState
    let multiSelectionSummary: MultiSelectionDetailSummary
    let detailErrorMapping: CoreErrorMappingSnapshot?
    var syncConflict: SyncConflictSnapshot?
    let isDetailLoading: Bool
    let selectedFileDetail: FileEntrySnapshot?
    let noteWriteBlock: MainDetailNoteWriteBlock?
    let detailLogState: MainDetailLogState
    let detailLogDiagnosticsState: MainDetailLogDiagnosticsState
    let detailExternalCreateSyncState: MainDetailExternalCreateSyncState
    let detailTagEditorState: DetailTagEditorState
    let detailTagSuggestionState: DetailTagSuggestionState
    let missingFileRelinkState: MainMissingFileRelinkState
    let tagSuggestionPresentationRequest: TagSuggestionPresentationRequest?
    let detailTagUndoToast: DetailTagUndoToast?
    let detailTabRequest: MainDetailTabRequest?
    let selectedImportProgressRow: ImportProgressListRow?
    let semanticDetail: SemanticSearchDetailPresentation?
    let repoPath: String
    let aiDependencies: AIFeatureDependencies
    let batchTagStore: any CoreTagCRUD
    let batchTagUndoStore: any CoreUndoActionLogging
    let batchTagErrorMapper: any CoreErrorMapping
    let batchDeleter: any CoreBatchDeleting
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let batchRenamer: any CoreBatchRenaming
    let categoryRows: [RepositorySidebarRowSnapshot]
    let onBatchCategoryApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onBatchDeleteApplied: (BatchDeleteReportSnapshot) -> Void
    let onBatchRenameApplied: (BatchRenameReportSnapshot) -> Void
    let onBatchCategoryCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void
    let onRetrySelectedFileDetail: () -> Void
    let onRetryExternalSync: () -> Void
    let tagActions: MainRepositoryDetailPaneTagActions
    let onCopyPaths: ([String]) -> Void
    let onOpenNoteFile: (String) -> Void
    let onLocateMissingFile: (Int64) -> Void
    let onRefreshChangeLog: () -> Void
    let onRequestDetailLogDiagnostics: () -> Void
    let onConfirmDetailLogDiagnostics: () -> Void
    let onCancelDetailLogDiagnostics: () -> Void
    let onDetailTabRequestConsumed: (MainDetailTabRequest) -> Void
    let onBeginRenameFile: (Int64) -> Void
    let onBeginChangeCategoryFile: (Int64) -> Void
    let onBeginClassifierCorrectionFile: (Int64) -> Void
    let onBeginAIClassificationSuggestionFile: (Int64) -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let onBeginICloudConflictResolution: (Int64) -> Void
    let onBeginSyncConflictReview: (FileEntrySnapshot) -> Void
    let onOpenAISettings: () -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    let canPerformWriteAction: (Int64) -> Bool

    @State private var selectedTab: DetailPaneTab = .meta
    @State private var pendingSummaryExitTab: DetailPaneTab?
    @ObservedObject var summaryExitController: AISummaryEditorExitController
    @ObservedObject var noteModel: DetailNoteModel
}

extension MainRepositoryDetailPane {
    var body: some View {
        Group {
            if let selectedImportProgressRow {
                ImportProgressDetailPane(row: selectedImportProgressRow)
            } else if selection.isMultiple {
                multiSelectionDetailPane
            } else if let detail = selectedFileDetail {
                selectedFileDetailPane(detail)
            } else if let error = detailErrorMapping {
                MainRepositoryDetailErrorPane(
                    error: error,
                    missingFile: missingErrorFile(),
                    selection: selection,
                    detailLogState: detailLogState,
                    detailLogDiagnosticsState: detailLogDiagnosticsState,
                    detailExternalCreateSyncState: detailExternalCreateSyncState,
                    onRetry: onRetrySelectedFileDetail,
                    onRetryExternalSync: onRetryExternalSync,
                    onRefreshChangeLog: onRefreshChangeLog,
                    onRequestDetailLogDiagnostics: onRequestDetailLogDiagnostics,
                    onConfirmDetailLogDiagnostics: onConfirmDetailLogDiagnostics,
                    onCancelDetailLogDiagnostics: onCancelDetailLogDiagnostics,
                    missingFileRelinkState: missingFileRelinkState,
                    onLocateMissingFile: onLocateMissingFile,
                    onBeginDeleteFile: onBeginDeleteFile,
                    canPerformWriteAction: canPerformWriteAction
                )
            } else if isDetailLoading {
                MainRepositoryDetailLoadingPane()
            } else {
                MainRepositoryEmptyDetailPane()
            }
        }
        .onChange(of: detailTabRequest) { _, request in
            guard let request else { return }
            applyDetailTabRequest(request)
        }
        .confirmationDialog(
            "Save AI summary changes?",
            isPresented: Binding(
                get: { pendingSummaryExitTab != nil },
                set: { if !$0 { pendingSummaryExitTab = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("Cancel"), role: .cancel) { pendingSummaryExitTab = nil }
            Button(L10n.string("Discard changes"), role: .destructive) {
                summaryExitController.discardChanges()
                finishPendingSummaryExit()
            }
            Button(L10n.string("Save changes")) { Task { await saveAndFinishPendingSummaryExit() } }
        } message: { Text(L10n.string("Save or discard the AI summary draft before leaving this file summary.")) }
    }

    private func selectedFileDetailPane(_ detail: FileEntrySnapshot) -> some View {
        MainRepositorySelectedFileDetailPane(
            selection: selection,
            detail: detail,
            syncConflict: syncConflict,
            semanticDetail: semanticDetail,
            selectedTab: selectedTab,
            detailErrorMapping: detailErrorMapping,
            isDetailLoading: isDetailLoading,
            noteWriteBlock: noteWriteBlock,
            detailLogState: detailLogState,
            detailLogDiagnosticsState: detailLogDiagnosticsState,
            detailExternalCreateSyncState: detailExternalCreateSyncState,
            detailTagEditorState: detailTagEditorState,
            detailTagSuggestionState: detailTagSuggestionState,
            missingFileRelinkState: missingFileRelinkState,
            tagSuggestionPresentationRequest: tagSuggestionPresentationRequest,
            detailTagUndoToast: detailTagUndoToast,
            repoPath: repoPath,
            aiDependencies: aiDependencies,
            errorMapper: batchTagErrorMapper,
            tagActions: tagActions,
            onRequestTabChange: requestDetailTabChange,
            onRetrySelectedFileDetail: onRetrySelectedFileDetail,
            onRetryExternalSync: onRetryExternalSync,
            onRefreshChangeLog: onRefreshChangeLog,
            onRequestDetailLogDiagnostics: onRequestDetailLogDiagnostics,
            onConfirmDetailLogDiagnostics: onConfirmDetailLogDiagnostics,
            onCancelDetailLogDiagnostics: onCancelDetailLogDiagnostics,
            onOpenNoteFile: onOpenNoteFile,
            onLocateMissingFile: onLocateMissingFile,
            onBeginRenameFile: onBeginRenameFile,
            onBeginChangeCategoryFile: onBeginChangeCategoryFile,
            onBeginClassifierCorrectionFile: onBeginClassifierCorrectionFile,
            onBeginAIClassificationSuggestionFile: onBeginAIClassificationSuggestionFile,
            onBeginDeleteFile: onBeginDeleteFile,
            onBeginICloudConflictResolution: onBeginICloudConflictResolution,
            onBeginSyncConflictReview: onBeginSyncConflictReview,
            onOpenAISettings: onOpenAISettings,
            writeActionDisabledReason: writeActionDisabledReason,
            canPerformWriteAction: canPerformWriteAction,
            summaryExitController: summaryExitController,
            noteModel: noteModel
        )
    }

    private func applyDetailTabRequest(_ request: MainDetailTabRequest) {
        switch request {
        case let .automatic(tab):
            requestDetailTabChange(tab)
        }
        onDetailTabRequestConsumed(request)
    }

    private func requestDetailTabChange(_ tab: DetailPaneTab) {
        guard selectedTab == .summary, tab != .summary, summaryExitController.needsConfirmation else {
            selectedTab = tab
            return
        }
        pendingSummaryExitTab = tab
    }

    private func saveAndFinishPendingSummaryExit() async {
        guard await summaryExitController.saveChanges() else { return }
        finishPendingSummaryExit()
    }

    private func finishPendingSummaryExit() {
        guard let tab = pendingSummaryExitTab else { return }
        pendingSummaryExitTab = nil
        selectedTab = tab
    }

    private func missingErrorFile() -> FileEntrySnapshot? {
        guard let selectedFileDetail, selectedFileDetail.availability == .missing else { return nil }
        return selectedFileDetail
    }
}
