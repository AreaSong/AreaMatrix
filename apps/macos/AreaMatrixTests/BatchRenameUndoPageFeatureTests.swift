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
        await undoStore.assertListRequests([batchRenameUndoRepoPath()])
        await undoStore.assertUndoRequests([])
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
        await undoStore.assertListRequests([])
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
        await undoStore.assertListRequests([])
    }
}

private typealias BatchRenameUndoStore = UndoActionRecordingTestStore
