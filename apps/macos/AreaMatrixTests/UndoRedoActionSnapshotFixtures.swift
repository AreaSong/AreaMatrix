@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static var undoActionLogHistoryFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Undo history could not be loaded",
            severity: .medium,
            suggestedAction: "Retry from Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }

    static func undoToastUndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }
}

extension UndoActionRecordSnapshot {
    static func undoToastMovedFilesToTrash() -> UndoActionRecordSnapshot {
        testMovedFilesToTrashUndoAction()
    }

    static func undoToastBlockedRename() -> UndoActionRecordSnapshot {
        testBlockedRenameUndoAction()
    }

    static func undoToastRenamedFiles() -> UndoActionRecordSnapshot {
        testRenamedFilesUndoAction()
    }

    static func undoToastMovedFilesToCategory() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-move-finance-5",
            kind: "move_files",
            summary: "Moved 5 files to finance.",
            affectedCount: 5,
            affectedFileNames: ["statement.pdf", "invoice.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_030,
            updatedAt: 1_700_000_030
        )
    }

    static func undoToastAddedTags() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-tags-24",
            kind: "batch_add_tags",
            summary: #"Added tag "finance" to 24 files."#,
            affectedCount: 24,
            affectedFileNames: ["invoice.pdf", "receipt.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_040,
            updatedAt: 1_700_000_040
        )
    }

    static func undoToastExecutedTrashMove() -> UndoActionRecordSnapshot {
        testExecutedTrashMoveUndoAction()
    }

    static func testMovedFilesToTrashUndoAction() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-trash-3",
            kind: "trash_delete",
            summary: "Moved 3 files to Trash.",
            affectedCount: 3,
            affectedFileNames: ["a.pdf", "b.pdf", "c.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_010
        )
    }

    static func testRenamedFilesUndoAction() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-rename-12",
            kind: "rename_files",
            summary: "Renamed 12 files.",
            affectedCount: 12,
            affectedFileNames: ["a.pdf", "b.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_020,
            updatedAt: 1_700_000_020
        )
    }

    static func testBlockedRenameUndoAction() -> UndoActionRecordSnapshot {
        var action = testRenamedFilesUndoAction()
        action.actionID = "undo-rename-blocked"
        action.status = .blocked
        action.canUndo = false
        action.disabledReason = "External change prevents undo."
        return action
    }

    static func testExecutedTrashMoveUndoAction() -> UndoActionRecordSnapshot {
        var action = testMovedFilesToTrashUndoAction()
        action.status = .executed
        action.canUndo = false
        action.updatedAt = 1_700_000_030
        return action
    }
}

extension UndoActionResultSnapshot {
    static func undoToastUndoneTrashMove() -> UndoActionResultSnapshot {
        testUndoneTrashMoveUndoResult()
    }

    static func testUndoneTrashMoveUndoResult() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-trash-3",
            status: .executed,
            summary: "Undone: moved 3 files to Trash.",
            affectedCount: 3,
            refreshTargets: ["files", "undo_actions", "change_log"],
            completedAt: 1_700_000_040
        )
    }
}

extension RedoActionRecordSnapshot {
    static func redoActionLogAvailableMoveRedo() -> RedoActionRecordSnapshot {
        RedoActionRecordSnapshot(
            actionID: "redo-move-3",
            kind: "move_files",
            summary: "Redo: Move 3 files to Documents",
            affectedCount: 3,
            affectedFileNames: ["a.pdf", "b.pdf", "c.pdf"],
            status: .available,
            canRedo: true,
            disabledReason: nil,
            sourceUndoActionID: "undo-trash-3",
            createdAt: 1_700_000_045,
            updatedAt: 1_700_000_045
        )
    }

    static func redoActionLogClearedMoveRedo() -> RedoActionRecordSnapshot {
        var action = redoActionLogAvailableMoveRedo()
        action.status = .cleared
        action.canRedo = false
        action.disabledReason = "Redo was cleared by the next file operation."
        return action
    }

    static func redoActionLogExecutedMoveRedo() -> RedoActionRecordSnapshot {
        var action = redoActionLogAvailableMoveRedo()
        action.status = .executed
        action.canRedo = false
        action.updatedAt = 1_700_000_060
        return action
    }
}

extension RedoActionResultSnapshot {
    static func redoActionLogRedoneMove() -> RedoActionResultSnapshot {
        RedoActionResultSnapshot(
            actionID: "redo-move-3",
            status: .executed,
            summary: "Redone: moved 3 files to Documents.",
            affectedCount: 3,
            refreshTargets: ["files", "undo_actions", "redo_actions", "change_log"],
            undoToken: "undo-redone-move-3",
            completedAt: 1_700_000_070
        )
    }
}
