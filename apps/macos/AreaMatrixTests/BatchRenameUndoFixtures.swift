@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func batchRenameUndoUndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .conflict,
            userMessage: "Could not load rename undo action.",
            severity: .medium,
            suggestedAction: "Open Undo History and refresh.",
            recoverability: .refreshRequired,
            rawContext: "batch-rename undo-action-log undo-action-log"
        )
    }
}

extension UndoActionRecordSnapshot {
    static func batchRenameUndoPendingBatchRename() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot.testFixture(
            actionID: "undo-rename-files",
            kind: "rename_files",
            summary: "Renamed 2 files.",
            affectedCount: 2,
            affectedFileNames: ["old-a.pdf", "old-b.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_300,
            updatedAt: 1_700_000_300
        )
    }
}
