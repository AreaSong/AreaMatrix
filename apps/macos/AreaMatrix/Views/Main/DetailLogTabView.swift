import SwiftUI

struct DetailLogTabView: View {
    let selection: MainFileSelectionState
    let detailLogState: MainDetailLogState
    let diagnosticsState: MainDetailLogDiagnosticsState
    let externalCreateSyncState: MainDetailExternalCreateSyncState
    let onRefreshChangeLog: () -> Void
    let onRequestDiagnostics: () -> Void
    let onConfirmDiagnostics: () -> Void
    let onCancelDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            DetailExternalCreateSyncStatusView(state: externalCreateSyncState)
            content
        }
        .task(id: selection.singleFileID) {
            onRefreshChangeLog()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change Log")
                    .font(.headline)
                Text("该文件的导入、移动、重命名和外部修改都会记录在这里。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Refresh", action: onRefreshChangeLog)
                .disabled(detailLogState.isLoading || externalCreateSyncState.isSyncing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch detailLogState {
        case .notLoaded, .loading:
            loadingState
        case let .loaded(_, entries):
            loadedState(entries)
        case let .failed(fileID, mapping):
            errorState(fileID: fileID, mapping)
        }
    }

    private var isCollectingDiagnostics: Bool {
        diagnosticsState.isCollecting
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading change log")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func loadedState(_ entries: [ChangeLogEntrySnapshot]) -> some View {
        if entries.isEmpty {
            Text("暂无改动记录")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    ChangeTimelineRow(entry: entry)
                }
            }
        }
    }

    private func errorState(fileID: Int64, _ mapping: CoreErrorMappingSnapshot) -> some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10,
            backgroundOpacity: 0.12
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label("无法加载改动记录", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                Text(mapping.userMessage)
                    .foregroundStyle(.secondary)
                Text(mapping.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Retry", action: onRefreshChangeLog)
                    Button("Collect Diagnostics...", action: onRequestDiagnostics)
                        .disabled(isCollectingDiagnostics)
                }
                Text("Diagnostics redact paths and usernames, exclude user file contents, and are not uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                diagnosticsStatus(fileID: fileID)
                DisclosureGroup("Technical Details") {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func diagnosticsStatus(fileID: Int64) -> some View {
        switch diagnosticsState {
        case .idle:
            EmptyView()
        case let .confirmingPrivacy(stateFileID) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 6) {
                Text("Create a redacted diagnostics package for this change log error?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Create diagnostics", action: onConfirmDiagnostics)
                    Button("Cancel", action: onCancelDiagnostics)
                }
            }
        case let .collecting(stateFileID) where stateFileID == fileID:
            Label("Preparing redacted diagnostics...", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .collected(stateFileID, snapshot) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.caption)
        case let .failed(stateFileID, mapping) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        case .confirmingPrivacy, .collecting, .collected, .failed:
            EmptyView()
        }
    }
}

extension MainFileListModel {
    var loadingStatusText: String? {
        guard isLoading else { return nil }
        if searchState.isActive { return "Searching..." }
        return "正在加载 \(currentCategoryDisplayName)..."
    }

    var loadingAccessibilityText: String? {
        guard let loadingStatusText else { return nil }
        return "Loading files. \(loadingStatusText)"
    }

    func canApplyDetailLogDiagnosticsResult(fileID: Int64) -> Bool {
        guard selection.singleFileID == fileID,
              case let .failed(failedFileID, _) = detailLogState else { return false }
        return failedFileID == fileID
    }

    func canApplyMultiSelectionDetailResult(generation: Int, ids: Set<Int64>) -> Bool {
        generation == detailGeneration && selection.multipleFileIDs == ids
    }
}
