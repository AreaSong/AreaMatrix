@testable import AreaMatrix
import XCTest

private func batchRenameUndoRepoPath() -> String {
    "/tmp/repo"
}

final class BatchRenameUndoPageFeatureTests: XCTestCase {
    @MainActor
    func testBatchRenameUndoUndoActionLogCoreBatchRenameLoadsUndoActionFromCoreActionLog() async {
        let action = UndoActionRecordSnapshot.batchRenameUndoPendingBatchRename()
        let undoStore = BatchRenameUndoStore(results: [.list(.success([action]))])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: batchRenameUndoRepoPath(),
            report: .report(token: action.actionID),
            failure: nil,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertEqual(state, .ready(action))
        await undoStore.assertUndoActionListRequests([batchRenameUndoRepoPath()])
        await undoStore.assertUndoActionRequests([])
    }

    @MainActor
    func testBatchRenameUndoUndoActionLogCoreBatchRenameReportsUnavailableWhenUndoTokenIsMissing() async {
        let undoStore = BatchRenameUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: batchRenameUndoRepoPath(),
            report: .report(token: nil),
            failure: nil,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertEqual(state, .unavailable(reason: "Undo is unavailable for this rename result."))
        await undoStore.assertUndoActionListRequests([])
    }

    @MainActor
    func testBatchRenameUndoUndoActionLogCoreBatchRenameDoesNotFakeUndoStateOnApplyFailure() async {
        let undoStore = BatchRenameUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: batchRenameUndoRepoPath(),
            report: nil,
            failure: .batchRenameUndoUndoFailure(),
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertNil(state)
        await undoStore.assertUndoActionListRequests([])
    }
}

private typealias BatchRenameUndoStore = UndoActionRecordingTestStore
