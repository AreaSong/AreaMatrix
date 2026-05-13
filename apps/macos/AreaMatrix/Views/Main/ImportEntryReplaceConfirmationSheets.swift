import SwiftUI

enum ImportEntryReplaceConfirmationSheets {
    @MainActor
    static func batch(
        item: ImportBatchReplaceConfirmation,
        model: ImportBatchCopyImportModel,
        pending: Binding<ImportBatchReplaceConfirmation?>
    ) -> ReplaceConfirmSheet {
        ReplaceConfirmSheet(
            context: item.context,
            errorMessage: model.replaceConfirmationErrorMessage,
            diagnosticsMessage: model.replaceConfirmationDiagnosticsMessage,
            onCancel: {
                model.clearReplaceConfirmationRecovery()
                pending.wrappedValue = nil
            },
            onRetry: model.retryReplaceConfirmation,
            onCollectDiagnostics: model.collectReplaceConfirmationDiagnostics,
            onConfirm: { decision in
                if model.applyReplaceConfirmation(for: item.rowID, decision: decision) {
                    pending.wrappedValue = nil
                }
            }
        )
    }

    @MainActor
    static func singleFile(
        item: ImportSingleFileReplaceConfirmation,
        model: ImportSingleFilePreviewModel,
        pending: Binding<ImportSingleFileReplaceConfirmation?>
    ) -> ReplaceConfirmSheet {
        ReplaceConfirmSheet(
            context: item.context,
            errorMessage: model.replaceConfirmationErrorMessage,
            diagnosticsMessage: model.replaceConfirmationDiagnosticsMessage,
            onCancel: {
                model.cancelReplaceConfirmation()
                pending.wrappedValue = nil
            },
            onRetry: model.retryReplaceConfirmation,
            onCollectDiagnostics: model.collectReplaceConfirmationDiagnostics,
            onConfirm: { decision in
                model.applyReplaceConfirmation(decision)
                if model.pendingReplaceConfirmation == nil {
                    pending.wrappedValue = nil
                }
            }
        )
    }

    @MainActor
    static func folder(
        item: ImportFolderReplaceConfirmation,
        model: ImportFolderPreviewModel,
        pending: Binding<ImportFolderReplaceConfirmation?>
    ) -> ReplaceConfirmSheet {
        ReplaceConfirmSheet(
            context: item.context,
            errorMessage: model.replaceConfirmationErrorMessage,
            diagnosticsMessage: model.replaceConfirmationDiagnosticsMessage,
            onCancel: {
                model.clearReplaceConfirmationRecovery()
                pending.wrappedValue = nil
            },
            onRetry: model.retryReplaceConfirmation,
            onCollectDiagnostics: model.collectReplaceConfirmationDiagnostics,
            onConfirm: { decision in
                if model.applyReplaceConfirmation(for: item.rowID, decision: decision) {
                    pending.wrappedValue = nil
                }
            }
        )
    }
}
