import SwiftUI

@MainActor
struct ImportBatchCopyFooterSection: View {
    let request: ImportEntryRequest
    @ObservedObject var batchPreviewModel: ImportBatchPreviewModel
    @ObservedObject var batchImportModel: ImportBatchCopyImportModel
    let onCancel: () -> Void
    let onImportProgress: ImportBatchProgressHandler
    let onImportFailed: ImportBatchFailureHandler
    let onImportResults: ImportBatchProgressHandler
    let importProgressControlState: ImportProgressControlState
    let onImported: (String, FileEntrySnapshot) -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(L10n.string("Cancel"), action: onCancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
            Button(L10n.string("Import")) {
                Task { await importBatch() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(AreaMatrixPrimaryButtonStyle())
            .disabled(importButtonDisabled)
            .help(importButtonHelp)
        }
    }

    private var importButtonDisabled: Bool {
        if batchPreviewModel.status.isLoading {
            return true
        }
        return batchPreviewModel.importDisabledReason != nil || batchImportModel.importDisabledReason != nil
    }

    private var importButtonHelp: String {
        if batchPreviewModel.status.isLoading {
            return L10n.string("Preparing preview...")
        }
        return batchPreviewModel.importDisabledReason ?? batchImportModel.importDisabledReason ?? ""
    }

    @MainActor
    private func importBatch() async {
        prepareImport()
        importProgressControlState.reset()
        if let initialProgress = initialProgressSnapshot() {
            onImportProgress(initialProgress)
        }
        var lastProgress: ImportBatchProgressSnapshot?
        let outcome = await batchImportModel.importReadyFiles(
            selectedDestination: batchPreviewModel.selectedDestination,
            controlState: importProgressControlState
        ) { progress in
            let progressWithItems = progress.withItems(batchImportModel.progressItems())
            lastProgress = progressWithItems
            onImportProgress(progressWithItems)
        }

        guard let outcome else { return }
        if outcome.didStopAfterCurrentFile {
            onImportResults(
                outcome.progressSnapshot(currentPath: batchImportModel.currentImportPath ?? request.sheetTitle)
                    .withItems(batchImportModel.progressItems())
            )
            return
        }
        if outcome.pendingDuplicateCount > 0 {
            return
        }
        if let retryContext = outcome.fatalRetryContext,
           let failure = batchImportModel.lastFailureMapping,
           let progress = lastProgress
        {
            onImportFailed(progress, failure, retryContext, .checking)
            importProgressControlState.registerQueueContinuation(batchImportModel)
            return
        }
        if outcome.needsResultSummary {
            onImportResults(
                outcome.progressSnapshot(currentPath: batchImportModel.currentImportPath ?? request.sheetTitle)
                    .withItems(batchImportModel.progressItems())
            )
            return
        }
        guard outcome.failedCount == 0 else {
            return
        }

        guard let importedEntry = outcome.succeededEntries.last else {
            onCancel()
            return
        }

        onImported(request.repoPath, importedEntry)
    }

    @MainActor
    private func prepareImport() {
        guard !batchImportModel.hasPendingDuplicateResolution else { return }
        batchImportModel.applyPreviewRows(
            batchPreviewModel.rows,
            request: request,
            selectedDestination: batchPreviewModel.selectedDestination
        )
    }

    private func initialProgressSnapshot() -> ImportBatchProgressSnapshot? {
        guard batchImportModel.importDisabledReason == nil else { return nil }
        let total = batchImportModel.importableRows.count
        guard total > 0 else { return nil }
        return ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: total,
            remaining: total,
            currentPath: batchImportModel.currentImportPath ?? request.sheetTitle,
            items: batchImportModel.progressItems()
        )
    }
}

struct ImportBatchSummarySection: View {
    let totalSizeDescription: String?
    let sourceLabel: String
    let duplicateCount: Int
    let nameConflictCount: Int
    let iCloudPlaceholderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("批量导入摘要"))
                .font(.headline)
            HStack(spacing: 16) {
                if let totalSizeDescription {
                    LabeledContent(L10n.string("总大小"), value: totalSizeDescription)
                }
                LabeledContent(L10n.string("来源"), value: sourceLabel)
                LabeledContent(L10n.string("预计重复"), value: L10n.plural("import.batch.duplicate-count", count: duplicateCount))
                LabeledContent(
                    L10n.string("重名冲突"),
                    value: L10n.plural("import.batch.name-conflict-count", count: nameConflictCount)
                )
                LabeledContent(
                    L10n.string("iCloud"),
                    value: L10n.plural("import.batch.icloud-placeholder-count", count: iCloudPlaceholderCount)
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

struct ImportConflictBatchUndoStateView: View {
    let state: BatchTagUndoState
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .loading(token):
            undoStatus(L10n.format("import.undo.loading-action", token))
        case let .ready(action):
            HStack(spacing: 8) {
                undoStatus(action.summary)
                Button(L10n.string("Undo"), action: onUndo)
                    .keyboardShortcut("z", modifiers: [.command])
            }
            .accessibilityLabel(L10n.format("import.undo.available", action.summary))
        case let .disabled(action, reason):
            undoStatus(L10n.format("import.undo.unavailable", action.summary, reason))
        case let .unavailable(reason):
            undoStatus(reason)
        case let .undoing(action):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                undoStatus(L10n.format("import.undo.in-progress", action.summary))
            }
        case let .undone(result):
            HStack(spacing: 8) {
                undoStatus(result.summary)
                Button(L10n.string("Dismiss"), action: onDismiss)
            }
            .accessibilityLabel(L10n.format("import.undo.completed", result.summary))
        case let .failed(mapping, previous):
            HStack(spacing: 8) {
                undoStatus(mapping.userMessage)
                    .foregroundStyle(.red)
                if previous != nil {
                    Button(L10n.string("Dismiss"), action: onDismiss)
                }
            }
            .accessibilityLabel(L10n.format("import.undo.failed", mapping.userMessage))
        }
    }

    private func undoStatus(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
