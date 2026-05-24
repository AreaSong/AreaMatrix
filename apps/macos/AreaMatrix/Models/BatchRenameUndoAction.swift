import Foundation

enum BatchRenameUndoAction {
    static func stateAfterBatchApply(
        repoPath: String,
        report: BatchRenameReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        guard failure == nil, let report, report.shouldRefreshConsumerAfterApply else { return nil }
        guard let token = normalizedToken(report.undoToken) else {
            return .unavailable(reason: "Undo is unavailable for this rename result.")
        }

        let loadResult = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: "Undo action is no longer available.")
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }
}
