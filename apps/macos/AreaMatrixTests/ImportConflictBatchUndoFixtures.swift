@testable import AreaMatrix

extension ChangeLogEntrySnapshot {
    static func importConflictFixture(filename: String) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: 27,
            fileID: 117,
            filename: filename,
            category: "finance",
            action: "imported",
            detailJSON: #"{"source":"/tmp/\#(filename)","mode":"copy","category":"finance"}"#,
            occurredAt: 1_700_000_000
        )
    }
}

extension UndoActionRecordSnapshot {
    static func importConflictBatchUndoAction() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-import-conflict-batch",
            kind: "import_conflict_batch",
            summary: "Replaced 1 import conflict.",
            affectedCount: 1,
            affectedFileNames: ["Invoice_2026Q1.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }
}

extension UndoActionResultSnapshot {
    static func importConflictBatchUndoResult() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-import-conflict-batch",
            status: .executed,
            summary: "Undone: replaced 1 import conflict.",
            affectedCount: 1,
            refreshTargets: ["files", "change_log", "undo_actions"],
            completedAt: 1_700_000_420
        )
    }
}
