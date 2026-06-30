import SwiftUI

struct MainRepositorySelectedFileDetailPane: View {
    let selection: MainFileSelectionState
    let detail: FileEntrySnapshot
    var syncConflict: SyncConflictSnapshot?
    let semanticDetail: SemanticSearchDetailPresentation?
    let selectedTab: DetailPaneTab
    let detailErrorMapping: CoreErrorMappingSnapshot?
    let isDetailLoading: Bool
    let noteWriteBlock: MainDetailNoteWriteBlock?
    let detailLogState: MainDetailLogState
    let detailLogDiagnosticsState: MainDetailLogDiagnosticsState
    let detailExternalCreateSyncState: MainDetailExternalCreateSyncState
    let detailTagEditorState: DetailTagEditorState
    let detailTagSuggestionState: DetailTagSuggestionState
    let tagSuggestionPresentationRequest: TagSuggestionPresentationRequest?
    let detailTagUndoToast: DetailTagUndoToast?
    let repoPath: String
    let tagActions: MainRepositoryDetailPaneTagActions
    let onRequestTabChange: (DetailPaneTab) -> Void
    let onRetrySelectedFileDetail: () -> Void
    let onRefreshChangeLog: () -> Void
    let onRequestDetailLogDiagnostics: () -> Void
    let onConfirmDetailLogDiagnostics: () -> Void
    let onCancelDetailLogDiagnostics: () -> Void
    let onOpenNoteFile: (String) -> Void
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
    @ObservedObject var summaryExitController: AISummaryEditorExitController
    @ObservedObject var noteModel: DetailNoteModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.currentName)
                    .font(.headline)
                    .textSelection(.enabled)
                SyncConflictDetailBanner(conflict: syncConflict) { _ in
                    onBeginSyncConflictReview(detail)
                }
                semanticSearchDetailBanner
                Picker("Detail tab", selection: Binding(get: { selectedTab }, set: onRequestTabChange)) {
                    ForEach(DetailPaneTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                detailTabContent
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
    private var detailTabContent: some View {
        switch selectedTab {
        case .meta:
            detailMetaTabContent
        case .summary:
            AISummaryEditor(
                repoPath: repoPath,
                fileID: detail.id,
                privacyContext: summaryPrivacyContext,
                exitController: summaryExitController,
                onOpenAISettings: onOpenAISettings,
                onBackToDetail: { onRequestTabChange(.meta) }
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

    private var summaryPrivacyContext: AISummaryPrivacyContext {
        AISummaryPrivacyContext(file: detail, tags: summaryPrivacyTags)
    }

    private var summaryPrivacyTags: [String] {
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
    private var detailMetaTabContent: some View {
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

    private var detailStatusSection: some View {
        MainRepositoryDetailStatusSection(
            error: detailErrorMapping,
            isLoading: isDetailLoading,
            selectedFile: detail,
            onRetry: onRetrySelectedFileDetail,
            onBeginDeleteFile: onBeginDeleteFile,
            canPerformWriteAction: canPerformWriteAction
        )
    }
}
