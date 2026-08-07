enum ImportSingleFileConflictRecoveryUpdate {
    case blockImport(AppDisplayText)
    case pendingReplaceConfirmation(SingleFileReplaceConfirmationContext?)
    case replaceConfirmationFailure(LocalizedMessage)
    case collectReplaceConfirmationDiagnostics
    case clearReplaceConfirmationRecovery
    case markReplaceConfirmed(Bool)
    case resetReplaceState
    case nameConflictResolution(ImportSingleFileNameConflictResolution)
    case resetNameConflictResolution
}

extension ImportSingleFilePreviewModel {
    func blockImportForDuplicateResolution(_ message: AppDisplayText) {
        applyConflictRecoveryUpdate(.blockImport(message))
    }

    func setPendingReplaceConfirmation(_ context: SingleFileReplaceConfirmationContext?) {
        applyConflictRecoveryUpdate(.pendingReplaceConfirmation(context))
    }

    func setReplaceConfirmationFailure(_ message: LocalizedMessage) {
        applyConflictRecoveryUpdate(.replaceConfirmationFailure(message))
    }

    func collectReplaceConfirmationDiagnostics() {
        applyConflictRecoveryUpdate(.collectReplaceConfirmationDiagnostics)
    }

    func clearReplaceConfirmationRecovery() {
        applyConflictRecoveryUpdate(.clearReplaceConfirmationRecovery)
    }

    func markReplaceConfirmed(_ isConfirmed: Bool) {
        applyConflictRecoveryUpdate(.markReplaceConfirmed(isConfirmed))
    }

    func resetReplaceStateForPreflight() {
        applyConflictRecoveryUpdate(.resetReplaceState)
    }

    func setNameConflictResolution(_ resolution: ImportSingleFileNameConflictResolution) {
        applyConflictRecoveryUpdate(.nameConflictResolution(resolution))
    }

    func resetNameConflictResolutionForPreflight() {
        applyConflictRecoveryUpdate(.resetNameConflictResolution)
    }
}
