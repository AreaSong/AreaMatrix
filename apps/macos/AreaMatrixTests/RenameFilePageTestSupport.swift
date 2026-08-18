@testable import AreaMatrix
import AreaMatrixFeatureOperation

extension BatchRenameValidation {
    static func batchRenameUndoCanApply(
        fileIDs: [Int64],
        preview: BatchRenamePreviewReportSnapshot?,
        rule: BatchRenameRuleSnapshot,
        disabledReason: String? = nil,
        isApplying: Bool = false
    ) -> Bool {
        canApply(
            fileIDs: fileIDs,
            preview: preview,
            rule: rule,
            disabledReason: disabledReason,
            isApplying: isApplying
        )
    }
}

extension BatchRenameAction {
    static func batchRenameUndoPreview(
        rule: BatchRenameRuleSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenamePreviewState {
        await preview(repoPath: "/repo", fileIDs: [11, 12], rule: rule, renamer: renamer, errorMapper: errorMapper)
    }

    static func batchRenameUndoApply(
        preview: BatchRenamePreviewReportSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenameApplyResult {
        await apply(repoPath: "/repo", fileIDs: [11, 12], preview: preview, renamer: renamer, errorMapper: errorMapper)
    }
}
