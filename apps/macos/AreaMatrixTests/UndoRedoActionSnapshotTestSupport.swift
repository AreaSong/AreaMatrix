@testable import AreaMatrix

actor UndoActionRecordingTestStore: CoreUndoActionLogging {
    enum Result {
        case list(Swift.Result<[UndoActionRecordSnapshot], Error>)
        case undo(Swift.Result<UndoActionResultSnapshot, Error>)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        do {
            guard case let .list(result) = try consumeResult() else {
                throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
            }
            return try result.get()
        } catch UndoActionRecordingTestStoreError.missingResult {
            throw CoreError.Db(message: "missing undo action result")
        }
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        do {
            guard case let .undo(result) = try consumeResult() else {
                throw CoreError.Internal(message: "expected undo_action result")
            }
            return try result.get()
        } catch UndoActionRecordingTestStoreError.missingResult {
            throw CoreError.Db(message: "missing undo action result")
        }
    }

    func listRequests() -> [String] {
        recordedListRequests
    }

    func undoRequests() -> [String] {
        recordedUndoRequests
    }

    fileprivate func listUndoActionsLenient(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard case let .list(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
        }
        return try result.get()
    }

    fileprivate func undoActionLenient(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard case let .undo(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected undo_action result")
        }
        return try result.get()
    }

    private func consumeResult() throws -> Result {
        guard !results.isEmpty else { throw UndoActionRecordingTestStoreError.missingResult }
        return results.removeFirst()
    }
}

private enum UndoActionRecordingTestStoreError: Error {
    case missingResult
}

actor LenientUndoActionRecordingTestStore: CoreUndoActionLogging {
    private let store: UndoActionRecordingTestStore

    init(results: [UndoActionRecordingTestStore.Result]) {
        store = UndoActionRecordingTestStore(results: results)
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        do {
            return try await store.listUndoActionsLenient(repoPath: repoPath)
        } catch UndoActionRecordingTestStoreError.missingResult {
            return []
        }
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        do {
            return try await store.undoActionLenient(repoPath: repoPath, actionID: actionID)
        } catch UndoActionRecordingTestStoreError.missingResult {
            throw CoreError.FileNotFound(path: actionID)
        }
    }

    func listRequests() async -> [String] {
        await store.listRequests()
    }

    func undoRequests() async -> [String] {
        await store.undoRequests()
    }
}

actor RedoActionLogRecordingRedoStore: CoreRedoActionLogging {
    enum Result {
        case list(Swift.Result<[RedoActionRecordSnapshot], Error>)
        case redo(Swift.Result<RedoActionResultSnapshot, Error>)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedRedoRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listRedoActions(repoPath: String) async throws -> [RedoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard !results.isEmpty else { return [] }
        guard case let .list(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected listRedoActions")
        }
        return try result.get()
    }

    func redoAction(repoPath: String, actionID: String) async throws -> RedoActionResultSnapshot {
        recordedRedoRequests.append("\(repoPath)|\(actionID)")
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: actionID)
        }
        guard case let .redo(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected redoAction")
        }
        return try result.get()
    }

    func listRequests() -> [String] {
        recordedListRequests
    }

    func redoRequests() -> [String] {
        recordedRedoRequests
    }
}

extension UndoActionRecordSnapshot {
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

    static func testImportConflictBatchUndoAction() -> UndoActionRecordSnapshot {
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

    static func testExecutedImportConflictBatchUndoResult() -> UndoActionResultSnapshot {
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
