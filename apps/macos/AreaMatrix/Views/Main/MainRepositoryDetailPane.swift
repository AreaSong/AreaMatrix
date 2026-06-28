import SwiftUI

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
    let tagSuggestionPresentationRequest: TagSuggestionPresentationRequest?
    let detailTagUndoToast: DetailTagUndoToast?
    let detailTabRequest: MainDetailTabRequest?
    let selectedImportProgressRow: ImportProgressListRow?
    let semanticDetail: SemanticSearchDetailPresentation?
    let repoPath: String
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
    let tagActions: MainRepositoryDetailPaneTagActions
    let onCopyPaths: ([String]) -> Void
    let onOpenNoteFile: (String) -> Void
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
                detailMetadataPane(detail)
            } else if let error = detailErrorMapping {
                MainRepositoryDetailErrorPane(
                    error: error,
                    missingFile: missingErrorFile(),
                    selection: selection,
                    detailLogState: detailLogState,
                    detailLogDiagnosticsState: detailLogDiagnosticsState,
                    detailExternalCreateSyncState: detailExternalCreateSyncState,
                    onRetry: onRetrySelectedFileDetail,
                    onRefreshChangeLog: onRefreshChangeLog,
                    onRequestDetailLogDiagnostics: onRequestDetailLogDiagnostics,
                    onConfirmDetailLogDiagnostics: onConfirmDetailLogDiagnostics,
                    onCancelDetailLogDiagnostics: onCancelDetailLogDiagnostics,
                    onBeginDeleteFile: onBeginDeleteFile,
                    writeActionDisabledReason: writeActionDisabledReason
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
            Button("Cancel", role: .cancel) { pendingSummaryExitTab = nil }
            Button("Discard changes", role: .destructive) {
                summaryExitController.discardChanges()
                finishPendingSummaryExit()
            }
            Button("Save changes") { Task { await saveAndFinishPendingSummaryExit() } }
        } message: { Text("Save or discard the AI summary draft before leaving this file summary.") }
    }

    private func detailMetadataPane(_ detail: FileEntrySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.currentName)
                    .font(.headline)
                    .textSelection(.enabled)
                SyncConflictDetailBanner(conflict: syncConflict) { _ in
                    onBeginSyncConflictReview(detail)
                }
                semanticSearchDetailBanner
                Picker("Detail tab", selection: Binding(get: { selectedTab }, set: requestDetailTabChange)) {
                    ForEach(DetailPaneTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                detailTabContent(for: detail)
                MainRepositoryDetailFileActionMenu(
                    detail: detail,
                    disabledReason: writeActionDisabledReason(detail.id),
                    onBeginRenameFile: onBeginRenameFile,
                    onBeginChangeCategoryFile: onBeginChangeCategoryFile,
                    onBeginClassifierCorrectionFile: onBeginClassifierCorrectionFile,
                    onBeginAIClassificationSuggestionFile: onBeginAIClassificationSuggestionFile,
                    onBeginDeleteFile: onBeginDeleteFile,
                    onBeginICloudConflictResolution: onBeginICloudConflictResolution,
                    onBeginSyncConflictReview: onBeginSyncConflictReview
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func detailTabContent(for detail: FileEntrySnapshot) -> some View {
        switch selectedTab {
        case .meta:
            detailMetaTabContent(for: detail)
        case .summary:
            AISummaryEditor(
                repoPath: repoPath,
                fileID: detail.id,
                privacyContext: summaryPrivacyContext(for: detail),
                exitController: summaryExitController,
                onOpenAISettings: onOpenAISettings,
                onBackToDetail: { requestDetailTabChange(.meta) }
            )
        case .log:
            DetailLogTabView(
                selection: selection,
                detailLogState: detailLogState,
                diagnosticsState: detailLogDiagnosticsState,
                externalCreateSyncState: detailExternalCreateSyncState,
                onRefreshChangeLog: onRefreshChangeLog,
                onRequestDiagnostics: onRequestDetailLogDiagnostics,
                onConfirmDiagnostics: onConfirmDetailLogDiagnostics,
                onCancelDiagnostics: onCancelDetailLogDiagnostics
            )
        case .note:
            DetailNoteTabView(
                model: noteModel,
                file: detail,
                writeBlock: noteWriteBlock,
                onOpenNoteFile: onOpenNoteFile
            )
        }
    }

    private func summaryPrivacyContext(for detail: FileEntrySnapshot) -> AISummaryPrivacyContext {
        AISummaryPrivacyContext(file: detail, tags: summaryPrivacyTags(for: detail))
    }

    private func summaryPrivacyTags(for detail: FileEntrySnapshot) -> [String] {
        switch detailTagEditorState {
        case let .loaded(fileID, tagSet) where fileID == detail.id:
            tagSet.fileTags.map(\.value)
        case let .loading(fileID, tagSet?) where fileID == detail.id:
            tagSet.fileTags.map(\.value)
        case let .failed(fileID, _, _, tagSet?) where fileID == detail.id:
            tagSet.fileTags.map(\.value)
        case .notLoaded, .loading, .loaded, .failed:
            []
        }
    }

    @ViewBuilder
    private func detailMetaTabContent(for detail: FileEntrySnapshot) -> some View {
        detailStatusSection
        DetailTagSection(
            file: detail,
            repoPath: repoPath,
            state: detailTagEditorState,
            suggestionState: detailTagSuggestionState,
            suggestionPresentationRequest: tagSuggestionPresentationRequest,
            undoToast: detailTagUndoToast,
            disabledReason: writeActionDisabledReason(detail.id),
            tagActions: tagActions
        )
        DetailMetadataRows(detail: detail)
    }

    @ViewBuilder
    private var semanticSearchDetailBanner: some View {
        if let semanticDetail {
            SemanticSearchDetailBanner(detail: semanticDetail)
        }
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

    private var detailStatusSection: some View {
        MainRepositoryDetailStatusSection(
            error: detailErrorMapping,
            isLoading: isDetailLoading,
            selectedFile: selectedFileDetail,
            onRetry: onRetrySelectedFileDetail,
            onBeginDeleteFile: onBeginDeleteFile,
            writeActionDisabledReason: writeActionDisabledReason
        )
    }

    private func missingErrorFile() -> FileEntrySnapshot? {
        guard let selectedFileDetail, selectedFileDetail.availability == .missing else { return nil }
        return selectedFileDetail
    }
}
