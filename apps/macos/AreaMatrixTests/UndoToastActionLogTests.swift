@testable import AreaMatrix
import XCTest

final class UndoToastActionLogTests: XCTestCase {
    @MainActor
    func testUndoToastViewHistoryRequestBuildsSharedUndoHistoryPanelRoute() {
        let action = UndoActionRecordSnapshot.undoToastHistoryFixture()
        let request = UndoToastHistoryRequest(source: .viewHistory, state: .ready(action), actionLogRefreshFailure: nil)
        let content = MainRepositoryContentView(
            opening: .importSingleFileFixture(repoPath: importProgressRepoPath()),
            state: .list,
            assembly: .make(
                opening: .importSingleFileFixture(repoPath: importProgressRepoPath()),
                errorMapper: StaticCoreErrorMapper(mapping: .undoActionLogHistoryFailure)
            ),
            onImport: {},
            onDropImport: { _, _ in }
        )

        assertTestMirrorDescription(
            of: content.undoHistorySheet(request),
            contains: "UndoHistoryPanel",
            doesNotContain: "UndoToastHistoryRouteSheet"
        )
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "undo-history-undo-action-log-undo-history-panel")
        XCTAssertEqual(request.focusedActionID, action.actionID)
    }

    @MainActor
    func testUndoToastViewDetailsRequestCarriesFailedActionContext() {
        let action = UndoActionRecordSnapshot.undoToastHistoryFixture()
        let failure = CoreErrorMappingSnapshot.undoActionLogHistoryFailure
        let request = UndoToastHistoryRequest(
            source: .viewDetails,
            state: .failed(failure, previous: action),
            actionLogRefreshFailure: nil
        )

        XCTAssertEqual(request.focusedActionID, action.actionID)
        XCTAssertEqual(request.failureMapping, failure)
    }

    @MainActor
    func testUndoToastUndoActionLogCoreLoadsLatestUndoActionFromCoreActionLog() async {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let undoStore = UndoToastRecordingUndoStore(results: [.list(.success([action]))])
        let result = await BatchTagUndoAction.loadLatestAction(
            repoPath: importProgressRepoPath(),
            undoStore: undoStore,
            errorMapper: RecordingCoreErrorMapper.undoToast()
        )

        XCTAssertEqual(result.toastState, .ready(action))
        await undoStore.assertUndoActionListRequests([importProgressRepoPath()])
        XCTAssertEqual(action.summary, "Moved 3 files to Trash.")
    }

    @MainActor
    func testUndoToastUndoActionLogCoreRefreshLatestToastCoversUndoableWriteSummaries() async {
        let actions: [UndoActionRecordSnapshot] = [
            .undoToastRenamedFiles(),
            .undoToastMovedFilesToCategory(),
            .undoToastMovedFilesToTrash(),
            .undoToastAddedTags()
        ]

        for action in actions {
            let undoStore = UndoToastRecordingUndoStore(results: [.list(.success([action]))])
            let state = await BatchTagUndoAction.refreshLatestToastState(
                repoPath: importProgressRepoPath(),
                undoStore: undoStore,
                errorMapper: RecordingCoreErrorMapper.undoToast()
            )

            XCTAssertEqual(state, .ready(action))
            await undoStore.assertUndoActionListRequests([importProgressRepoPath()])
        }
    }

    @MainActor
    func testUndoToastUndoActionLogCoreExecutesUndoAndUsesRefreshTargets() async {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let undoStore = UndoToastRecordingUndoStore(results: [
            .undo(.success(.undoToastUndoneTrashMove())),
            .list(.success([.undoToastExecutedTrashMove()]))
        ])

        let applied = await BatchTagUndoAction.undo(
            repoPath: importProgressRepoPath(),
            action: action,
            undoStore: undoStore,
            errorMapper: RecordingCoreErrorMapper.undoToast()
        )
        let plan = BatchTagUndoRefreshPlan(refreshTargets: applied.result?.refreshTargets ?? [])
        let refreshed = await BatchTagUndoAction.refreshActionLog(
            repoPath: importProgressRepoPath(),
            actionID: action.actionID,
            undoStore: undoStore,
            errorMapper: RecordingCoreErrorMapper.undoToast()
        )

        XCTAssertEqual(applied.result, .undoToastUndoneTrashMove())
        XCTAssertTrue(plan.refreshesCurrentList)
        XCTAssertTrue(plan.refreshesUndoActions)
        XCTAssertEqual(refreshed.action, .undoToastExecutedTrashMove())
        await undoStore.assertUndoActionRequests(["\(importProgressRepoPath())|\(action.actionID)"])
        await undoStore.assertUndoActionListRequests([importProgressRepoPath()])
    }

    @MainActor
    func testUndoToastUndoActionLogCoreBlockedUndoKeepsVisibleReasonWithoutExecuting() async {
        let action = UndoActionRecordSnapshot.undoToastBlockedRename()
        let undoStore = UndoToastRecordingUndoStore(results: [.list(.success([action]))])
        let result = await BatchTagUndoAction.loadLatestAction(
            repoPath: importProgressRepoPath(),
            undoStore: undoStore,
            errorMapper: RecordingCoreErrorMapper.undoToast()
        )

        XCTAssertEqual(result.toastState, .disabled(action, reason: "External change prevents undo."))
        await undoStore.assertUndoActionRequests([])
    }

    func testUndoToastUndoActionLogCoreViewHistoryCreatesToastScopedRequest() {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let request = UndoToastHistoryRequest(source: .viewHistory, state: .ready(action), actionLogRefreshFailure: nil)

        XCTAssertTrue(request.id.contains("viewHistory:\(action.actionID)"))
        XCTAssertEqual(request.source, .viewHistory)
        XCTAssertEqual(request.state, .ready(action))
    }

    func testUndoToastUndoActionLogCoreViewDetailsCreatesToastScopedFailureRequest() {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let failure = CoreErrorMappingSnapshot.undoToastUndoFailure()
        let request = UndoToastHistoryRequest(
            source: .viewDetails,
            state: .failed(failure, previous: action),
            actionLogRefreshFailure: nil
        )

        XCTAssertTrue(request.id.contains("viewDetails:failed:\(action.actionID):\(failure.kind.rawValue)"))
        XCTAssertEqual(request.source, .viewDetails)
        XCTAssertEqual(request.state, .failed(failure, previous: action))
    }
}

private extension UndoActionRecordSnapshot {
    static func undoToastHistoryFixture() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot.testFixture(
            actionID: "undo-history-1",
            kind: "batch_add_tags",
            summary: #"Added tag "finance" to 3 files."#,
            affectedCount: 3,
            affectedFileNames: ["invoice.pdf", "receipt.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_010
        )
    }
}
