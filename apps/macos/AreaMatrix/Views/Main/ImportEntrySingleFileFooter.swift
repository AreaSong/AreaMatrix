import SwiftUI

extension ImportEntrySheetView {
    var singleFileFooter: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(previewModel.singleFilePrimaryActionTitle) {
                Task { await runSingleFileImportAction() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(previewModel.primaryActionDisabledReason != nil)
        }
    }

    @MainActor
    func runSingleFileImportAction() async {
        if let confirmation = ImportEntrySingleFilePrimaryActionGate.pendingReplaceConfirmation(for: previewModel) {
            pendingSingleFileReplaceConfirmation = confirmation
            return
        }

        let runner = ImportEntrySingleFileImportRunner(
            request: request,
            previewModel: previewModel,
            onImportStarted: onImportStarted,
            onImportStartedWithRetryContext: onImportStartedWithRetryContext,
            onImportFailed: onImportFailed,
            onImported: onImported
        )
        await runner.run()
    }
}

struct ImportEntrySingleFileImportRunner {
    let request: ImportEntryRequest
    let previewModel: ImportSingleFilePreviewModel
    let onImportStarted: (String, ImportSingleFileStorageMode) -> Void
    let onImportStartedWithRetryContext: (
        String,
        String,
        ImportSingleFileStorageMode,
        String,
        String,
        DuplicateStrategy
    ) -> Void
    let onImportFailed: (String, CoreErrorMappingSnapshot) -> Void
    let onImported: (String, FileEntrySnapshot) -> Void

    @MainActor
    func run() async {
        let shouldReportProgress = previewModel.shouldStartImportProgress
        let startingPath = previewModel.progressCurrentPath
        if let context = shouldReportProgress ? previewModel.progressRetryContext : nil {
            onImportStartedWithRetryContext(
                startingPath,
                context.sourcePath,
                context.storageMode,
                context.overrideCategory,
                context.overrideFilename,
                context.duplicateStrategy.coreStrategy
            )
            let entry = await previewModel.importSelectedFile()
            handleCompletedSingleFileImport(
                entry: entry,
                startingPath: startingPath,
                context: context,
                shouldReportProgress: shouldReportProgress
            )
            return
        }

        if shouldReportProgress {
            onImportStarted(startingPath, previewModel.selectedStorageMode)
        }
        let entry = await previewModel.importSelectedFile()
        handleCompletedSingleFileImport(
            entry: entry,
            startingPath: startingPath,
            context: nil,
            shouldReportProgress: shouldReportProgress
        )
    }

    @MainActor
    private func handleCompletedSingleFileImport(
        entry: FileEntrySnapshot?,
        startingPath: String,
        context: ImportProgressRetryContext?,
        shouldReportProgress: Bool
    ) {
        if let entry {
            onImported(request.repoPath, entry)
        } else if let mapping = previewModel.importFailureMapping {
            onImportFailed(startingPath, mapping)
        }
    }
}

enum ImportEntrySingleFilePrimaryActionGate {
    @MainActor
    static func pendingReplaceConfirmation(
        for previewModel: ImportSingleFilePreviewModel
    ) -> ImportSingleFileReplaceConfirmation? {
        guard previewModel.isPendingReplaceConfirmation else { return nil }
        previewModel.beginReplaceConfirmation()
        guard let context = previewModel.pendingReplaceConfirmation else { return nil }
        return ImportSingleFileReplaceConfirmation(context: context)
    }
}
