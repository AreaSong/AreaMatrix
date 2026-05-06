import SwiftUI

struct ImportBatchCopyFooterSection: View {
    let request: ImportEntryRequest
    let batchPreviewModel: ImportBatchPreviewModel
    let batchImportModel: ImportBatchCopyImportModel
    let onCancel: () -> Void
    let onImportProgress: (ImportBatchProgressSnapshot) -> Void
    let onImportFailed: (ImportBatchProgressSnapshot, CoreErrorMappingSnapshot) -> Void
    let onImported: (String, FileEntrySnapshot) -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Import") {
                Task { await importBatch() }
            }
            .keyboardShortcut(.defaultAction)
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
            return "Preparing preview..."
        }
        return batchPreviewModel.importDisabledReason ?? batchImportModel.importDisabledReason ?? ""
    }

    @MainActor
    private func importBatch() async {
        prepareImport()
        if let initialProgress = initialProgressSnapshot() {
            onImportProgress(initialProgress)
        }
        var lastProgress: ImportBatchProgressSnapshot?
        let outcome = await batchImportModel.importReadyFiles(selectedDestination: batchPreviewModel.selectedDestination) { progress in
            lastProgress = progress
            if progress.completed > 0 || progress.failed > 0 {
                onImportProgress(progress)
            }
        }

        guard let outcome else { return }
        if outcome.pendingDuplicateCount > 0 {
            return
        }
        if outcome.failedCount > 0, let failure = batchImportModel.lastFailureMapping, let progress = lastProgress {
            onImportFailed(progress, failure)
            return
        }
        guard outcome.failedCount == 0 else {
            return
        }
        if outcome.needsResultSummary {
            onImportProgress(outcome.progressSnapshot(currentPath: batchImportModel.currentImportPath ?? request.sheetTitle))
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
            currentPath: batchImportModel.currentImportPath ?? request.sheetTitle
        )
    }
}
