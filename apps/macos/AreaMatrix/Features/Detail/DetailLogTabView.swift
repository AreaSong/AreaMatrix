import AreaMatrixFeatureLibrary
import SwiftUI

struct DetailLogTabView: View {
    let selection: MainFileSelectionState
    let detailLogState: MainDetailLogState
    let diagnosticsState: MainDetailLogDiagnosticsState
    let externalCreateSyncState: MainDetailExternalCreateSyncState
    let onRetryExternalSync: () -> Void
    let onRefreshChangeLog: () -> Void
    let onRequestDiagnostics: () -> Void
    let onConfirmDiagnostics: () -> Void
    let onCancelDiagnostics: () -> Void

    var body: some View {
        let currentExternalCreateSyncState = externalCreateSyncState.isolated(to: selection.singleFileID)
        VStack(alignment: .leading, spacing: 12) {
            header
            DetailExternalCreateSyncStatusView(
                state: currentExternalCreateSyncState,
                onRetry: onRetryExternalSync
            )
            content
        }
        .task(id: selection.singleFileID) {
            onRefreshChangeLog()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Change Log"))
                    .font(.headline)
                Text(L10n.string("该文件的导入、移动、重命名和外部修改都会记录在这里。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(L10n.string("Refresh"), action: onRefreshChangeLog)
                .disabled(
                    detailLogState.isLoading ||
                        externalCreateSyncState.isolated(to: selection.singleFileID).isSyncing
                )
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
            Text(L10n.string("Loading change log"))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func loadedState(_ entries: [ChangeLogEntrySnapshot]) -> some View {
        if entries.isEmpty {
            Text(L10n.string("暂无改动记录"))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    ChangeTimelineRow(
                        action: entry.actionDisplayName,
                        occurredAt: entry.occurredAtDisplay,
                        summary: entry.detailSummary,
                        detail: entry.detailJSON
                    )
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
                Label(L10n.string("无法加载改动记录"), systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                Text(mapping.userMessage)
                    .foregroundStyle(.secondary)
                Text(mapping.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.string("Retry"), action: onRefreshChangeLog)
                    Button(L10n.string("Collect Diagnostics..."), action: onRequestDiagnostics)
                        .disabled(isCollectingDiagnostics)
                }
                Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                diagnosticsStatus(fileID: fileID)
                DisclosureGroup(L10n.string("Technical Details")) {
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
                Text(L10n.string("diagnostics.errorSnapshotPrivacyDetail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.string("Create diagnostics"), action: onConfirmDiagnostics)
                    Button(L10n.string("Cancel"), action: onCancelDiagnostics)
                }
            }
        case let .collecting(stateFileID) where stateFileID == fileID:
            Label(L10n.string("Preparing repository diagnostics..."), systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .collected(stateFileID, snapshot) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.string("Diagnostics collected"), systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.caption)
        case let .failed(stateFileID, mapping) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.string("Diagnostics could not be collected"), systemImage: "exclamationmark.triangle")
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
