import SwiftUI

struct ImportBatchCopyFooterSection: View {
    let request: ImportEntryRequest
    let batchPreviewModel: ImportBatchPreviewModel
    let batchImportModel: ImportBatchCopyImportModel
    let onCancel: () -> Void
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
        return batchImportModel.importDisabledReason != nil
    }

    private var importButtonHelp: String {
        if batchPreviewModel.status.isLoading {
            return "Preparing preview..."
        }
        return batchImportModel.importDisabledReason ?? ""
    }

    @MainActor
    private func importBatch() async {
        prepareImport()
        let outcome = await batchImportModel.importReadyFiles(selectedDestination: batchPreviewModel.selectedDestination)

        guard let outcome else { return }
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
        batchImportModel.applyPreviewRows(
            batchPreviewModel.rows,
            request: request,
            selectedDestination: batchPreviewModel.selectedDestination
        )
    }
}
