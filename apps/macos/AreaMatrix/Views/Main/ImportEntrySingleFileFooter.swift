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

        let shouldReportProgress = previewModel.shouldStartImportProgress
        let startingPath = previewModel.progressCurrentPath
        if let context = shouldReportProgress ? previewModel.progressRetryContext : nil {
            let entry = await previewModel.importSelectedFile()
            handleCompletedSingleFileImport(
                entry: entry,
                startingPath: startingPath,
                context: context,
                shouldReportProgress: shouldReportProgress
            )
            return
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
            if let context {
                onImportStartedWithRetryContext(
                    startingPath,
                    context.sourcePath,
                    context.storageMode,
                    context.overrideCategory,
                    context.overrideFilename,
                    context.duplicateStrategy.coreStrategy
                )
            } else if shouldReportProgress {
                onImportStarted(startingPath, previewModel.selectedStorageMode)
            }
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
