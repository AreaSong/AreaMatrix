import SwiftUI

struct MainRepositoryEmptyDetailPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("选择一个文件查看详情"))
                .font(.headline)
            Text(L10n.string("文件的元数据、改动时间线和伴生笔记会显示在这里。"))
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
            Text(L10n.string("Loading file details"))
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
    let onRetryExternalSync: () -> Void
    let onRefreshChangeLog: () -> Void
    let onRequestDetailLogDiagnostics: () -> Void
    let onConfirmDetailLogDiagnostics: () -> Void
    let onCancelDetailLogDiagnostics: () -> Void
    let missingFileRelinkState: MainMissingFileRelinkState
    let onLocateMissingFile: (Int64) -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let canPerformWriteAction: (Int64) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.string("File details cannot be loaded"), systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L10n.string("Retry"), action: onRetry)
                MainRepositoryDetailLocateButton(
                    file: missingFile,
                    state: missingFileRelinkState,
                    onLocateMissingFile: onLocateMissingFile,
                    canPerformWriteAction: canPerformWriteAction
                )
                MainRepositoryDetailIndexRemovalButton(
                    file: missingFile,
                    style: .primary,
                    onBeginDeleteFile: onBeginDeleteFile,
                    canPerformWriteAction: canPerformWriteAction
                )
            }
            MissingFileRecoveryMessage(file: missingFile, state: missingFileRelinkState)
            DisclosureGroup(L10n.string("Technical Details")) {
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
                onRetryExternalSync: onRetryExternalSync,
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
    let missingFileRelinkState: MainMissingFileRelinkState
    let onLocateMissingFile: (Int64) -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let canPerformWriteAction: (Int64) -> Bool

    var body: some View {
        if let error {
            MainRepositoryDetailInlineErrorBanner(
                error: error,
                selectedFile: selectedFile,
                onRetry: onRetry,
                missingFileRelinkState: missingFileRelinkState,
                onLocateMissingFile: onLocateMissingFile,
                onBeginDeleteFile: onBeginDeleteFile,
                canPerformWriteAction: canPerformWriteAction
            )
        } else if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("Refreshing file details"))
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
    let missingFileRelinkState: MainMissingFileRelinkState
    let onLocateMissingFile: (Int64) -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let canPerformWriteAction: (Int64) -> Bool

    var body: some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10,
            backgroundOpacity: 0.12
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("无法加载文件详情"), systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                Text(error.userMessage)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(L10n.string("Retry"), action: onRetry)
                    MainRepositoryDetailLocateButton(
                        file: selectedFile,
                        state: missingFileRelinkState,
                        onLocateMissingFile: onLocateMissingFile,
                        canPerformWriteAction: canPerformWriteAction
                    )
                    MainRepositoryDetailIndexRemovalButton(
                        file: selectedFile,
                        style: .secondary,
                        onBeginDeleteFile: onBeginDeleteFile,
                        canPerformWriteAction: canPerformWriteAction
                    )
                }
                MissingFileRecoveryMessage(file: selectedFile, state: missingFileRelinkState)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct MainRepositoryDetailLocateButton: View {
    let file: FileEntrySnapshot?
    let state: MainMissingFileRelinkState
    let onLocateMissingFile: (Int64) -> Void
    let canPerformWriteAction: (Int64) -> Bool

    var body: some View {
        if let file, MainRepositoryDetailFileActionPolicy.shouldShowLocate(for: file) {
            Button(state.isBusy(for: file.id) ? L10n.string("Locating...") : L10n.string("Locate...")) {
                onLocateMissingFile(file.id)
            }
            .disabled(!canPerformWriteAction(file.id) || state.isBusy(for: file.id))
            .accessibilityIdentifier("file-detail-missing-locate")
        }
    }
}

struct MissingFileRecoveryMessage: View {
    let file: FileEntrySnapshot?
    let state: MainMissingFileRelinkState

    var body: some View {
        if let file, let message = state.message(for: file.id) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("file-detail-missing-relink-message")
        }
    }
}

struct MainRepositoryDetailIndexRemovalButton: View {
    let file: FileEntrySnapshot?
    let style: DetailIndexRemovalButtonStyle
    let onBeginDeleteFile: (Int64) -> Void
    let canPerformWriteAction: (Int64) -> Bool

    var body: some View {
        if let file, MainRepositoryDetailFileActionPolicy.shouldShowRemoveFromIndex(for: file) {
            Button(L10n.string("Remove from Index"), role: .destructive) {
                onBeginDeleteFile(file.id)
            }
            .disabled(!canPerformWriteAction(file.id))
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
