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
    let detailTabRequest: MainDetailTabRequest?
    let selectedImportProgressRow: ImportProgressListRow?
    let onRetrySelectedFileDetail: () -> Void
    let onCopyPaths: ([String]) -> Void
    let onOpenNoteFile: (String) -> Void
    let onRefreshChangeLog: () -> Void
    let onRequestDetailLogDiagnostics: () -> Void
    let onConfirmDetailLogDiagnostics: () -> Void
    let onCancelDetailLogDiagnostics: () -> Void
    let onDetailTabRequestConsumed: (MainDetailTabRequest) -> Void
    let onBeginRenameFile: (Int64) -> Void
    let onBeginChangeCategoryFile: (Int64) -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let onBeginICloudConflictResolution: (Int64) -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?

    @State private var selectedTab: DetailPaneTab = .meta
    @ObservedObject private var noteModel: DetailNoteModel

    init(
        selection: MainFileSelectionState,
        multiSelectionSummary: MultiSelectionDetailSummary,
        detailErrorMapping: CoreErrorMappingSnapshot?,
        isDetailLoading: Bool,
        selectedFileDetail: FileEntrySnapshot?,
        noteWriteBlock: MainDetailNoteWriteBlock?,
        detailLogState: MainDetailLogState,
        detailLogDiagnosticsState: MainDetailLogDiagnosticsState,
        detailExternalCreateSyncState: MainDetailExternalCreateSyncState,
        detailTabRequest: MainDetailTabRequest?,
        selectedImportProgressRow: ImportProgressListRow?,
        onRetrySelectedFileDetail: @escaping () -> Void,
        onCopyPaths: @escaping ([String]) -> Void,
        onOpenNoteFile: @escaping (String) -> Void,
        onRefreshChangeLog: @escaping () -> Void,
        onRequestDetailLogDiagnostics: @escaping () -> Void,
        onConfirmDetailLogDiagnostics: @escaping () -> Void,
        onCancelDetailLogDiagnostics: @escaping () -> Void,
        onDetailTabRequestConsumed: @escaping (MainDetailTabRequest) -> Void,
        onBeginRenameFile: @escaping (Int64) -> Void,
        onBeginChangeCategoryFile: @escaping (Int64) -> Void,
        onBeginDeleteFile: @escaping (Int64) -> Void,
        onBeginICloudConflictResolution: @escaping (Int64) -> Void,
        writeActionDisabledReason: @escaping (Int64) -> MainFileWriteActionDisabledReason?,
        noteModel: DetailNoteModel
    ) {
        self.selection = selection
        self.multiSelectionSummary = multiSelectionSummary
        self.detailErrorMapping = detailErrorMapping
        self.isDetailLoading = isDetailLoading
        self.selectedFileDetail = selectedFileDetail
        self.noteWriteBlock = noteWriteBlock
        self.detailLogState = detailLogState
        self.detailLogDiagnosticsState = detailLogDiagnosticsState
        self.detailExternalCreateSyncState = detailExternalCreateSyncState
        self.detailTabRequest = detailTabRequest
        self.selectedImportProgressRow = selectedImportProgressRow
        self.onRetrySelectedFileDetail = onRetrySelectedFileDetail
        self.onCopyPaths = onCopyPaths
        self.onOpenNoteFile = onOpenNoteFile
        self.onRefreshChangeLog = onRefreshChangeLog
        self.onRequestDetailLogDiagnostics = onRequestDetailLogDiagnostics
        self.onConfirmDetailLogDiagnostics = onConfirmDetailLogDiagnostics
        self.onCancelDetailLogDiagnostics = onCancelDetailLogDiagnostics
        self.onDetailTabRequestConsumed = onDetailTabRequestConsumed
        self.onBeginRenameFile = onBeginRenameFile
        self.onBeginChangeCategoryFile = onBeginChangeCategoryFile
        self.onBeginDeleteFile = onBeginDeleteFile
        self.onBeginICloudConflictResolution = onBeginICloudConflictResolution
        self.writeActionDisabledReason = writeActionDisabledReason
        self.noteModel = noteModel
    }

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
        VStack(alignment: .leading, spacing: 10) {
            Button("Show in Finder") {}
                .disabled(true)
                .help("Open one file at a time")
            Text("Open one file at a time")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Copy Paths") {
                onCopyPaths(multiSelectionSummary.paths)
            }
            .disabled(multiSelectionSummary.paths.isEmpty)
            if detailErrorMapping != nil {
                Button("Retry Metadata", action: onRetrySelectedFileDetail)
            }
        }
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
        case .automatic(let tab):
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
    private func removeFromIndexButton(for file: FileEntrySnapshot?, style: DetailRemoveFromIndexButtonStyle) -> some View {
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

struct DetailMetaMetadataRow: Equatable, Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

private enum DetailRemoveFromIndexButtonStyle {
    case primary
    case secondary

    var accessibilityIdentifier: String {
        switch self {
        case .primary:
            return "S1-12-missing-remove-from-index"
        case .secondary:
            return "S1-12-inline-remove-from-index"
        }
    }
}

func detailMetaMetadataRows(for detail: FileEntrySnapshot) -> [DetailMetaMetadataRow] {
    [
        DetailMetaMetadataRow(label: "Category", value: detail.category),
        DetailMetaMetadataRow(label: "Path", value: detail.path),
        DetailMetaMetadataRow(label: "Size", value: detail.sizeDisplay),
        DetailMetaMetadataRow(label: "Storage", value: detail.storageMode),
        DetailMetaMetadataRow(label: "Origin", value: detail.origin),
        DetailMetaMetadataRow(label: "Imported", value: detail.importedAtDisplay),
        DetailMetaMetadataRow(label: "Modified", value: detail.updatedAtDisplay),
        DetailMetaMetadataRow(label: "SHA-256", value: detail.hashSha256),
        DetailMetaMetadataRow(label: "Source", value: detailMetaDisplayValue(detail.sourcePath)),
        DetailMetaMetadataRow(label: "Status", value: detail.statusDisplay),
    ]
}

private func detailMetaDisplayValue(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not available" }
    return value
}
