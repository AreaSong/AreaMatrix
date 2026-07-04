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
        let listRequests = await undoStore.listRequests()
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(listRequests, [batchRenameUndoRepoPath()])
        XCTAssertEqual(undoRequests, [])
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
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [])
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
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [])
    }
}

private typealias BatchRenameUndoStore = UndoActionRecordingTestStore
