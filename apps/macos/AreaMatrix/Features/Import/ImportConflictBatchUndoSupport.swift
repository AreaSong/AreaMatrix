import Foundation

enum ImportConflictBatchUndoAction {
    static func stateAfterBatchApply(
        repoPath: String,
        report: ImportConflictBatchApplyReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        guard failure == nil, let report, report.shouldRefreshUndoActionLogAfterApply else { return nil }
        guard let token = normalizedToken(report.undoToken) else {
            return .unavailable(reason: L10n.string("Undo is unavailable for this import conflict result."))
        }

        let loadResult = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: L10n.string("Undo action is no longer available."))
    }

    static func undo(
        repoPath: String,
        state: BatchTagUndoState,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState {
        guard let action = state.executableAction else { return state }
        let result = await BatchTagUndoAction.undo(
            repoPath: repoPath,
            action: action,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let undoResult = result.result {
            return .undone(undoResult)
        }
        if let failure = result.failure {
            return .failed(failure, previous: action)
        }
        return .failed(fallbackMapping(), previous: action)
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    private static func fallbackMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.internalFailure(rawContext: "undo_action returned no result")
    }
}

extension ImportConflictBatchApplyReportSnapshot {
    var shouldRefreshUndoActionLogAfterApply: Bool {
        resolvedCount > 0 || !changeLogActions.isEmpty || undoToken != nil
    }
}

@MainActor
extension ImportBatchCopyImportModel {
    func resetConflictBatchOutcome() {
        conflictBatchApplyResult = nil
        conflictBatchUndoState = .idle
        conflictBatchPerItemQueue = nil
    }

    func refreshConflictBatchUndoState(
        report: ImportConflictBatchApplyReportSnapshot?,
        failure: CoreErrorMappingSnapshot?
    ) async {
        if let state = await ImportConflictBatchUndoAction.stateAfterBatchApply(
            repoPath: request?.repoPath ?? "",
            report: report,
            failure: failure,
            undoStore: undoActionStore,
            errorMapper: errorMapper
        ) {
            conflictBatchUndoState = state
        } else {
            conflictBatchUndoState = .idle
        }
    }

    func undoImportConflictBatchAction() async {
        let currentState = conflictBatchUndoState
        if let action = currentState.executableAction {
            conflictBatchUndoState = .undoing(action)
        }
        let state = await ImportConflictBatchUndoAction.undo(
            repoPath: request?.repoPath ?? "",
            state: currentState,
            undoStore: undoActionStore,
            errorMapper: errorMapper
        )
        conflictBatchUndoState = state
    }
}
