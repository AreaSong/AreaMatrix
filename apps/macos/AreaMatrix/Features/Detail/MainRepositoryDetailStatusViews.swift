import SwiftUI

struct MainRepositoryEmptyDetailPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择一个文件查看详情")
                .font(.headline)
            Text("文件的元数据、改动时间线和伴生笔记会显示在这里。")
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }
}

struct MainRepositoryDetailLoadingPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading file details")
                .font(.headline)
        }
        .padding(18)
    }
}

struct MainRepositoryDetailErrorPane: View {
    let error: CoreErrorMappingSnapshot
    let missingFile: FileEntrySnapshot?
    let selection: MainFileSelectionState
    let detailLogState: MainDetailLogState
    let detailLogDiagnosticsState: MainDetailLogDiagnosticsState
    let detailExternalCreateSyncState: MainDetailExternalCreateSyncState
    let onRetry: () -> Void
    let onRefreshChangeLog: () -> Void
    let onRequestDetailLogDiagnostics: () -> Void
    let onConfirmDetailLogDiagnostics: () -> Void
    let onCancelDetailLogDiagnostics: () -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File details cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Retry", action: onRetry)
                MainRepositoryDetailIndexRemovalButton(
                    file: missingFile,
                    style: .primary,
                    onBeginDeleteFile: onBeginDeleteFile,
                    writeActionDisabledReason: writeActionDisabledReason
                )
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
}

struct MainRepositoryDetailStatusSection: View {
    let error: CoreErrorMappingSnapshot?
    let isLoading: Bool
    let selectedFile: FileEntrySnapshot?
    let onRetry: () -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?

    var body: some View {
        if let error {
            MainRepositoryDetailInlineErrorBanner(
                error: error,
                selectedFile: selectedFile,
                onRetry: onRetry,
                onBeginDeleteFile: onBeginDeleteFile,
                writeActionDisabledReason: writeActionDisabledReason
            )
        } else if isLoading {
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
}

struct MainRepositoryDetailInlineErrorBanner: View {
    let error: CoreErrorMappingSnapshot
    let selectedFile: FileEntrySnapshot?
    let onRetry: () -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?

    var body: some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10,
            backgroundOpacity: 0.12
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label("无法加载文件详情", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                Text(error.userMessage)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Retry", action: onRetry)
                    MainRepositoryDetailIndexRemovalButton(
                        file: selectedFile,
                        style: .secondary,
                        onBeginDeleteFile: onBeginDeleteFile,
                        writeActionDisabledReason: writeActionDisabledReason
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct MainRepositoryDetailIndexRemovalButton: View {
    let file: FileEntrySnapshot?
    let style: DetailIndexRemovalButtonStyle
    let onBeginDeleteFile: (Int64) -> Void
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?

    var body: some View {
        if let file, MainRepositoryDetailFileActionPolicy.shouldShowRemoveFromIndex(for: file) {
            Button("Remove from Index", role: .destructive) {
                onBeginDeleteFile(file.id)
            }
            .disabled(writeActionDisabledReason(file.id) != nil)
            .accessibilityIdentifier(style.accessibilityIdentifier)
        }
    }
}

enum DetailIndexRemovalButtonStyle {
    case primary, secondary

    var accessibilityIdentifier: String {
        self == .primary ? "file-detail-missing-remove-from-index" : "file-detail-inline-remove-from-index"
    }
}
