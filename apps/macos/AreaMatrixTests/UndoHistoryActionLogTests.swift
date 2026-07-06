@testable import AreaMatrix
import XCTest

final class UndoHistoryActionLogTests: XCTestCase {
    @MainActor
    func testUndoHistoryUndoActionLogCoreLoadsUndoHistorySnapshotAndSelectsFocusedAction() async {
        let latest = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let older = UndoActionRecordSnapshot.undoHistoryRenamedFiles()
        let undoStore = UndoHistoryRecordingUndoStore(results: [.list(.success([latest, older]))])
        let redoStore = RedoActionLogRecordingRedoStore(results: [.list(.success([]))])
        let state = await UndoHistoryActionLog.load(
            repoPath: importProgressRepoPath(),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        XCTAssertEqual(state.actions, [latest, older])
        XCTAssertEqual(UndoHistoryActionLog.action(in: state.actions, focusedActionID: older.actionID), older)
        XCTAssertNil(state.failure)
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [importProgressRepoPath()])
        let redoListRequests = await redoStore.listRequests()
        XCTAssertEqual(redoListRequests, [importProgressRepoPath()])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreUndoLatestExecutesOnlyTopActionAndRefreshesSnapshot() async {
        let latest = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let older = UndoActionRecordSnapshot.undoHistoryRenamedFiles()
        let redo = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let undoStore = UndoHistoryRecordingUndoStore(results: [
            .undo(.success(.undoHistoryUndoneTrashMove())),
            .list(.success([.undoHistoryExecutedTrashMove(), older]))
        ])
        let redoStore = RedoActionLogRecordingRedoStore(results: [.list(.success([redo]))])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: importProgressRepoPath(),
            snapshot: .testFixture(undoActions: [latest, older]),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        XCTAssertEqual(state.actions, [.undoHistoryExecutedTrashMove(), older])
        XCTAssertEqual(state.snapshot.redoActions, [redo])
        let undoRequests = await undoStore.undoRequests()
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(undoRequests, ["\(importProgressRepoPath())|\(latest.actionID)"])
        XCTAssertEqual(listRequests, [importProgressRepoPath()])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreUndoLatestReportsRefreshFailureWithoutSwallowingIt() async {
        let latest = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let undoStore = UndoHistoryRecordingUndoStore(results: [
            .undo(.success(.undoHistoryUndoneTrashMove())),
            .list(.failure(CoreError.Db(message: "refresh failed")))
        ])
        let redoStore = RedoActionLogRecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: importProgressRepoPath(),
            snapshot: .testFixture(undoActions: [latest]),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        guard case let .refreshFailed(mapping, previous) = state else {
            return XCTFail("expected refreshFailed, got \(state)")
        }
        XCTAssertEqual(mapping.kind, .db)
        XCTAssertEqual(previous.undoActions, [latest])
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [importProgressRepoPath()])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreBlockedLatestDoesNotCallUndoAction() async {
        let blocked = UndoActionRecordSnapshot.undoHistoryBlockedRename()
        let undoStore = UndoHistoryRecordingUndoStore(results: [])
        let redoStore = RedoActionLogRecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: importProgressRepoPath(),
            snapshot: .testFixture(undoActions: [blocked]),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        XCTAssertEqual(state.actions, [blocked])
        XCTAssertEqual(state.failure?.userMessage, "External change prevents undo.")
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(undoRequests, [])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCorePanelShowsActionStatesAndDisabledRedoWithoutRedoActionLogCoreCall() {
        let ready = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let blocked = UndoActionRecordSnapshot.undoHistoryBlockedRename()
        let panel = UndoHistoryPanel(
            repoPath: importProgressRepoPath(),
            focusedActionID: ready.actionID,
            initialFailure: nil,
            undoStore: UndoHistoryRecordingUndoStore(results: [.list(.success([ready, blocked]))]),
            redoStore: RedoActionLogRecordingRedoStore(results: [.list(.success([.redoActionLogAvailableMoveRedo()]))]),
            errorMapper: RecordingCoreErrorMapper.undoHistory(),
            onClose: {},
            onUndoCompleted: { _ in },
            onRedoCompleted: { _ in }
        )
        assertTestMirrorDescription(of: panel.body, contains: [
            "Undo History",
            "Undo latest",
            "Redo latest"
        ])
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "undo-history-undo-action-log-undo-history-panel")
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreMenuAndShortcutRequestsShareUndoHistoryPanelRoute() {
        let action = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let failure = CoreErrorMappingSnapshot.undoActionLogHistoryFailure
        let menuRequest = UndoHistoryActionLog.menuRequest(state: .ready(action), failure: nil)
        let shortcutRequest = UndoHistoryActionLog.shortcutRequest(state: .ready(action), failure: nil)
        let redoShortcutRequest = UndoHistoryActionLog.redoShortcutRequest(state: .ready(action), failure: failure)

        XCTAssertEqual(menuRequest.source, .viewHistory)
        XCTAssertEqual(shortcutRequest.source, .viewHistory)
        XCTAssertEqual(redoShortcutRequest.source, .viewHistory)
        XCTAssertEqual(menuRequest.focusedActionID, action.actionID)
        XCTAssertEqual(shortcutRequest.focusedActionID, action.actionID)
        XCTAssertEqual(redoShortcutRequest.failureMapping, failure)
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "undo-history-undo-action-log-undo-history-panel")
    }

    func testRedoActionLogUndoActionLogCoreRedoSourceUsesLoadedUndoActionLogSummary() {
        let undo = UndoActionRecordSnapshot.undoHistoryExecutedTrashMove()
        let redo = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let presentation = RedoUndoSourcePresentation(redoAction: redo, undoActions: [undo])

        XCTAssertEqual(presentation.sourceText, "Source undo: Moved 3 files to Trash.")
        XCTAssertEqual(presentation.statusText, "Available until the next file operation")
        let history = UndoHistorySnapshot.testFixture(undoActions: [undo], redoActions: [redo])
        XCTAssertEqual(history.sourceUndoAction(for: redo), undo)
    }
}

private extension UndoActionRecordSnapshot {
    static func undoHistoryMovedFilesToTrash() -> UndoActionRecordSnapshot {
        testMovedFilesToTrashUndoAction()
    }

    static func undoHistoryBlockedRename() -> UndoActionRecordSnapshot {
        testBlockedRenameUndoAction()
    }

    static func undoHistoryRenamedFiles() -> UndoActionRecordSnapshot {
        testRenamedFilesUndoAction()
    }

    static func undoHistoryExecutedTrashMove() -> UndoActionRecordSnapshot {
        testExecutedTrashMoveUndoAction()
    }
}

private extension UndoActionResultSnapshot {
    static func undoHistoryUndoneTrashMove() -> UndoActionResultSnapshot {
        testUndoneTrashMoveUndoResult()
    }
}

private typealias UndoHistoryRecordingUndoStore = LenientUndoActionRecordingTestStore
