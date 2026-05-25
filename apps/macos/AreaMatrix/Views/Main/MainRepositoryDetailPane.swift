import SwiftUI

struct MainRepositoryDetailPane: View {
    let selection: MainFileSelectionState
    let multiSelectionSummary: MultiSelectionDetailSummary
    let detailErrorMapping: CoreErrorMappingSnapshot?
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
    let onBeginDeleteFile: (Int64) -> Void
    let onBeginICloudConflictResolution: (Int64) -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?

    @State private var selectedTab: DetailPaneTab = .meta
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
                detailErrorPane(error)
            } else if isDetailLoading {
                detailLoadingPane
            } else {
                emptyDetailPane
            }
        }
        .onChange(of: detailTabRequest) { _, request in
            guard let request else { return }
            applyDetailTabRequest(request)
        }
    }

    private var multiSelectionDetailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                multiSelectionHeader
                multiSelectionWarnings
                multiSelectionStatistics
                multiSelectionFileTypes
                multiSelectionActions
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
    }

    private var multiSelectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(multiSelectionSummary.title)
                .font(.headline)
            Text(multiSelectionSummary.subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if multiSelectionSummary.isUpdating {
                Label("Updating selection...", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let detailErrorMapping {
                Label(detailErrorMapping.userMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var multiSelectionWarnings: some View {
        if !multiSelectionSummary.warningMessages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(multiSelectionSummary.warningMessages, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.12))
        }
    }

    private var multiSelectionStatistics: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(multiSelectionSummary.statisticRows) { row in
                metadataRow(row.label, row.value)
            }
        }
    }

    @ViewBuilder
    private var multiSelectionFileTypes: some View {
        if !multiSelectionSummary.fileTypeRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("File types")
                    .font(.callout.weight(.semibold))
                ForEach(multiSelectionSummary.fileTypeRows) { row in
                    metadataRow(row.label, row.value)
                }
            }
        }
    }

    private var multiSelectionActions: some View {
        MainRepositoryMultiSelectionActions(
            selection: selection,
            summary: multiSelectionSummary,
            detailErrorMapping: detailErrorMapping,
            repoPath: repoPath,
            categoryRows: categoryRows,
            batchTagStore: batchTagStore,
            batchTagUndoStore: batchTagUndoStore,
            batchTagErrorMapper: batchTagErrorMapper,
            batchDeleter: batchDeleter,
            batchCategoryChanger: batchCategoryChanger,
            batchRenamer: batchRenamer,
            tagActions: tagActions,
            writeActionDisabledReason: writeActionDisabledReason,
            onCopyPaths: onCopyPaths,
            onRetrySelectedFileDetail: onRetrySelectedFileDetail,
            onRefreshChangeLog: onRefreshChangeLog,
            onBatchCategoryApplied: onBatchCategoryApplied,
            onBatchDeleteApplied: onBatchDeleteApplied,
            onBatchRenameApplied: onBatchRenameApplied,
            onBatchCategoryCreateNewCategory: onBatchCategoryCreateNewCategory
        )
    }

    private var emptyDetailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择一个文件查看详情")
                .font(.headline)
            Text("文件的元数据、改动时间线和伴生笔记会显示在这里。")
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var detailLoadingPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading file details")
                .font(.headline)
        }
        .padding(18)
    }

    private func detailErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File details cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Retry", action: onRetrySelectedFileDetail)
                removeFromIndexButton(for: missingErrorFile(), style: .primary)
            }
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Divider()
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
        }
        .padding(18)
        .accessibilityElement(children: .contain)
    }

    private func detailMetadataPane(_ detail: FileEntrySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.currentName)
                    .font(.headline)
                    .textSelection(.enabled)
                Picker("Detail tab", selection: $selectedTab) {
                    ForEach(DetailPaneTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                detailTabContent(for: detail)
                detailFileActions(for: detail)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func detailTabContent(for detail: FileEntrySnapshot) -> some View {
        switch selectedTab {
        case .meta:
            detailStatusSection
            DetailTagSection(
                file: detail,
                state: detailTagEditorState,
                suggestionState: detailTagSuggestionState,
                suggestionPresentationRequest: tagSuggestionPresentationRequest,
                undoToast: detailTagUndoToast,
                disabledReason: writeActionDisabledReason(detail.id),
                onLoadTags: tagActions.onLoadTags,
                onRetryTags: tagActions.onRetryTags,
                onAddTag: tagActions.onAddTag,
                onRemoveTag: tagActions.onRemoveTag,
                onLoadSuggestions: tagActions.onLoadSuggestions,
                onRetrySuggestions: tagActions.onRetrySuggestions,
                onToggleSuggestion: tagActions.onToggleSuggestion,
                onSelectAllSuggestions: tagActions.onSelectAllSuggestions,
                onClearSuggestions: tagActions.onClearSuggestions,
                onStartEditingSuggestions: tagActions.onStartEditingSuggestions,
                onCancelEditingSuggestions: tagActions.onCancelEditingSuggestions,
                onEditSuggestionDisplayName: tagActions.onEditSuggestionDisplayName,
                onEditSuggestionSlug: tagActions.onEditSuggestionSlug,
                onRegenerateSuggestionSlug: tagActions.onRegenerateSuggestionSlug,
                onApplySuggestions: tagActions.onApplySuggestions,
                onApplyEditedSuggestions: tagActions.onApplyEditedSuggestions,
                onSuggestionPresentationConsumed: tagActions.onSuggestionPresentationConsumed,
                onUndoTagChange: tagActions.onUndoTagChange,
                onDismissUndoToast: tagActions.onDismissTagUndoToast
            )
            metadataRows(for: detail)
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

    private func detailFileActions(for detail: FileEntrySnapshot) -> some View {
        let disabledReason = writeActionDisabledReason(detail.id)
        return HStack(spacing: 10) {
            Spacer()
            Menu {
                Button("Rename...") {
                    onBeginRenameFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("S1-12-rename-file")
                Button("Change Category...") {
                    onBeginChangeCategoryFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("S1-12-change-category")
                Button("Correct Classification...") {
                    onBeginClassifierCorrectionFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("S2-16-correct-classification")
                if detail.hasICloudConflictCopySignal {
                    Button("Resolve iCloud Conflict...") {
                        onBeginICloudConflictResolution(detail.id)
                    }
                    .disabled(disabledReason != nil)
                    .accessibilityIdentifier("S1-25-resolve-icloud-conflict")
                }
                if shouldShowRemoveFromIndex(for: detail) {
                    Button("Remove from Index", role: .destructive) {
                        onBeginDeleteFile(detail.id)
                    }
                    .disabled(disabledReason != nil)
                    .accessibilityIdentifier("S1-12-remove-from-index")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help(disabledReason?.rawValue ?? "File actions")
            .accessibilityIdentifier("S1-12-file-action-menu")
        }
    }

    private func applyDetailTabRequest(_ request: MainDetailTabRequest) {
        switch request {
        case let .automatic(tab):
            selectedTab = tab
        }
        onDetailTabRequestConsumed(request)
    }

    @ViewBuilder
    private var detailStatusSection: some View {
        if let error = detailErrorMapping {
            detailInlineError(error)
        } else if isDetailLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing file details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func detailInlineError(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法加载文件详情", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Retry", action: onRetrySelectedFileDetail)
                removeFromIndexButton(for: selectedFileDetail, style: .secondary)
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func removeFromIndexButton(for file: FileEntrySnapshot?,
                                       style: DetailRemoveFromIndexButtonStyle) -> some View {
        if let file, shouldShowRemoveFromIndex(for: file) {
            Button("Remove from Index", role: .destructive) {
                onBeginDeleteFile(file.id)
            }
            .disabled(writeActionDisabledReason(file.id) != nil)
            .accessibilityIdentifier(style.accessibilityIdentifier)
        }
    }

    private func missingErrorFile() -> FileEntrySnapshot? {
        guard let selectedFileDetail, selectedFileDetail.availability == .missing else { return nil }
        return selectedFileDetail
    }

    private func shouldShowRemoveFromIndex(for detail: FileEntrySnapshot) -> Bool {
        MainFileDeleteOperation.recommended(for: detail) == .removeFromIndex
    }

    private func metadataRows(for detail: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(detailMetaMetadataRows(for: detail)) { row in
                metadataRow(row.label, row.value)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private enum DetailRemoveFromIndexButtonStyle {
    case primary
    case secondary

    var accessibilityIdentifier: String {
        switch self {
        case .primary:
            "S1-12-missing-remove-from-index"
        case .secondary:
            "S1-12-inline-remove-from-index"
        }
    }
}
