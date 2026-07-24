@testable import AreaMatrix
import XCTest

private func batchRenameRedoRepoPath() -> String {
    "/tmp/repo"
}

final class BatchRenameRedoActionLogTests: XCTestCase {
    @MainActor
    func testRedoActionLogRedoActionLogCoreRedoLatestUsesRealRedoActionLogAndRefreshesSnapshot() async {
        let undo = UndoActionRecordSnapshot.batchRenameUndoPendingBatchRename()
        let redo = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let redoStore = RedoActionLogRecordingRedoStore(results: [
            .redo(.success(.redoActionLogRedoneMove())),
            .list(.success([.redoActionLogExecutedMoveRedo()]))
        ])
        let undoStore = BatchRenameRedoUndoStore(results: [.list(.success([undo]))])

        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: batchRenameRedoRepoPath(),
            snapshot: .testFixture(undoActions: [undo], redoActions: [redo]),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        guard case let .redone(result, refreshed) = state else {
            return XCTFail("expected redone, got \(state)")
        }
        XCTAssertEqual(result, .redoActionLogRedoneMove())
        XCTAssertEqual(refreshed.redoActions, [.redoActionLogExecutedMoveRedo()])
        await redoStore.assertRedoActionRequests(["\(batchRenameRedoRepoPath())|\(redo.actionID)"])
    }

    @MainActor
    func testRedoActionLogRedoActionLogCoreClearedRedoShowsReasonWithoutExecuting() async {
        let cleared = RedoActionRecordSnapshot.redoActionLogClearedMoveRedo()
        let redoStore = RedoActionLogRecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: batchRenameRedoRepoPath(),
            snapshot: .testFixture(redoActions: [cleared]),
            undoStore: BatchRenameRedoUndoStore(results: []),
            redoStore: redoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertEqual(state.failure?.kind, .conflict)
        XCTAssertEqual(state.failure?.userMessage, "Redo action is currently unavailable.")
        XCTAssertEqual(state.failure?.technicalDetails, "Redo was cleared by the next file operation.")
        XCTAssertEqual(state.failure?.rawContext, "Redo was cleared by the next file operation.")
        await redoStore.assertRedoActionRequests([])
    }

    @MainActor
    func testRedoActionLogRedoActionLogCoreFeedbackLoadsLatestRedoAndExecutesThroughStore() async {
        let action = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let redoStore = RedoActionLogRecordingRedoStore(results: [
            .list(.success([action])),
            .redo(.success(.redoActionLogRedoneMove()))
        ])
        let errorMapper = StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())

        let loaded = await RedoActionFeedback.loadLatestAction(
            repoPath: batchRenameRedoRepoPath(),
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        XCTAssertEqual(loaded.feedbackState(), .available(action))

        let applied = await RedoActionFeedback.redo(
            repoPath: batchRenameRedoRepoPath(),
            action: action,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        XCTAssertEqual(applied.result, .redoActionLogRedoneMove())
        XCTAssertNil(applied.failure)
        await redoStore.assertRedoActionRequests(["\(batchRenameRedoRepoPath())|\(action.actionID)"])
    }
}

private typealias BatchRenameRedoUndoStore = UndoActionRecordingTestStore
