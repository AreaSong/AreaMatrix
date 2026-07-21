import SwiftUI

@MainActor
struct ImportFolderFooterSection: View {
    let request: ImportEntryRequest
    let model: ImportFolderPreviewModel
    let importDisabledReason: String?
    let onCancel: () -> Void
    let onImportProgress: ImportBatchProgressHandler
    let onImportFailed: ImportBatchFailureHandler
    let onImportResults: ImportBatchProgressHandler
    let importProgressControlState: ImportProgressControlState
    let onImported: (String, FileEntrySnapshot) -> Void
    let onRetryScan: () -> Void

    var body: some View {
        HStack {
            if let importDisabledReason {
                Text(importDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry scan", action: onRetryScan)
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
            Button("Import Folder") {
                Task { await importFolder() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(AreaMatrixPrimaryButtonStyle())
            .disabled(importDisabledReason != nil)
        }
    }

    @MainActor
    private func importFolder() async {
        importProgressControlState.reset()
        if let initialProgress = initialProgressSnapshot() {
            onImportProgress(initialProgress)
        }

        var lastProgress: ImportBatchProgressSnapshot?
        let outcome = await model.importReadyFiles(controlState: importProgressControlState) { progress in
            lastProgress = progress
            if progress.completed > 0 || progress.failed > 0 {
                onImportProgress(progress)
            }
        }

        guard let outcome else { return }
        if let retryContext = outcome.fatalRetryContext,
           let failure = model.lastFailureMapping,
           let progress = lastProgress {
            onImportFailed(progress, failure, retryContext, .checking)
            importProgressControlState.registerQueueContinuation(model)
            return
        }
        if outcome.didStopAfterCurrentFile {
            onImportResults(
                outcome.progressSnapshot(currentPath: model.currentImportPath ?? request.sheetTitle)
                    .withItems(model.progressItems())
            )
            return
        }
        if outcome.needsResultSummary {
            onImportResults(
                outcome.progressSnapshot(currentPath: model.currentImportPath ?? request.sheetTitle)
                    .withItems(model.progressItems())
            )
            return
        }
        guard outcome.failedCount == 0 else { return }
        guard let importedEntry = outcome.succeededEntries.last else {
            onCancel()
            return
        }

        onImported(request.repoPath, importedEntry)
    }

    private func initialProgressSnapshot() -> ImportBatchProgressSnapshot? {
        guard importDisabledReason == nil else { return nil }
        let total = model.importableRows.count
        guard total > 0 else { return nil }
        return ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: total,
            remaining: total,
            currentPath: model.currentImportPath ?? request.sheetTitle,
            items: model.progressItems()
        )
    }
}
