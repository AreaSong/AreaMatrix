@testable import AreaMatrix
import XCTest

final class S214BatchRenameUndoPageFeatureTests: XCTestCase {
    @MainActor
    func testS214C207BatchRenameLoadsUndoActionFromCoreActionLog() async {
        let action = UndoActionRecordSnapshot.s214PendingBatchRename()
        let undoStore = S214BatchRenameRecordingUndoStore(results: [.list(.success([action]))])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .report(token: action.actionID),
            failure: nil,
            undoStore: undoStore,
            errorMapper: BatchRenameErrorMapper(mapping: .s214UndoFailure())
        )

        XCTAssertEqual(state, .ready(action))
        XCTAssertEqual(await undoStore.listRequests(), ["/tmp/repo"])
        XCTAssertEqual(await undoStore.undoRequests(), [])
    }

    @MainActor
    func testS214C207BatchRenameReportsUnavailableWhenUndoTokenIsMissing() async {
        let undoStore = S214BatchRenameRecordingUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .report(token: nil),
            failure: nil,
            undoStore: undoStore,
            errorMapper: BatchRenameErrorMapper(mapping: .s214UndoFailure())
        )

        XCTAssertEqual(state, .unavailable(reason: "Undo is unavailable for this rename result."))
        XCTAssertEqual(await undoStore.listRequests(), [])
    }

    @MainActor
    func testS214C207BatchRenameDoesNotFakeUndoStateOnApplyFailure() async {
        let undoStore = S214BatchRenameRecordingUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: nil,
            failure: .s214UndoFailure(),
            undoStore: undoStore,
            errorMapper: BatchRenameErrorMapper(mapping: .s214UndoFailure())
        )

        XCTAssertNil(state)
        XCTAssertEqual(await undoStore.listRequests(), [])
    }
}

private actor S214BatchRenameRecordingUndoStore: CoreUndoActionLogging {
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
        guard case let .list(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
        }
        return try result.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard case let .undo(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected undo_action result")
        }
        return try result.get()
    }

    func listRequests() -> [String] { recordedListRequests }

    func undoRequests() -> [String] { recordedUndoRequests }

    private func consumeResult() throws -> Result {
        guard !results.isEmpty else { throw CoreError.Db(message: "missing undo action result") }
        return results.removeFirst()
    }
}

private extension UndoActionRecordSnapshot {
    static func s214PendingBatchRename() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
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

private extension CoreErrorMappingSnapshot {
    static func s214UndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Could not load rename undo action.",
            severity: .medium,
            suggestedAction: "Open Undo History and refresh.",
            recoverability: .refreshRequired,
            rawContext: "S2-14 C2-07 undo-action-log"
        )
    }
}
