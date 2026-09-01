@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreUndoRedoContractTests: XCTestCase {
    func testUndoAndRedoStatusWireValuesAreStable() {
        XCTAssertEqual(UndoActionStatusSnapshot.pending.rawValue, "Pending")
        XCTAssertEqual(UndoActionStatusSnapshot.blocked.rawValue, "Blocked")
        XCTAssertEqual(RedoActionStatusSnapshot.available.rawValue, "Available")
        XCTAssertEqual(RedoActionStatusSnapshot.executed.rawValue, "Executed")
    }

    func testUndoAndRedoSnapshotsPreserveIdentityAndSafetyState() {
        let undo = UndoActionRecordSnapshot(
            actionID: "undo-1",
            kind: "rename",
            summary: "Rename note",
            affectedCount: 1,
            affectedFileNames: ["note.md"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 10,
            updatedAt: 11
        )
        let redo = RedoActionRecordSnapshot(
            actionID: "redo-1",
            kind: "rename",
            summary: "Rename note",
            affectedCount: 1,
            affectedFileNames: ["note.md"],
            status: .available,
            canRedo: true,
            disabledReason: nil,
            sourceUndoActionID: undo.actionID,
            createdAt: 12,
            updatedAt: 13
        )

        XCTAssertEqual(undo.id, "undo-1")
        XCTAssertEqual(redo.id, "redo-1")
        XCTAssertEqual(redo.sourceUndoActionID, undo.actionID)
        XCTAssertTrue(undo.canUndo)
        XCTAssertTrue(redo.canRedo)
        XCTAssertEqual(undo, undo)
        XCTAssertEqual(redo, redo)
    }

    func testUndoAndRedoCapabilityProtocolsCanBeImplementedWithoutGeneratedBindings() async throws {
        let logging = UndoRedoContractDouble()
        let undoActions = try await logging.listUndoActions(repoPath: "/tmp/repository")
        let undoResult = try await logging.undoAction(repoPath: "/tmp/repository", actionID: "undo-1")
        let redoActions = try await logging.listRedoActions(repoPath: "/tmp/repository")
        let redoResult = try await logging.redoAction(repoPath: "/tmp/repository", actionID: "redo-1")

        XCTAssertEqual(undoActions.map(\.id), ["undo-1"])
        XCTAssertEqual(undoResult.actionID, "undo-1")
        XCTAssertEqual(redoActions.map(\.id), ["redo-1"])
        XCTAssertEqual(redoResult.actionID, "redo-1")
    }
}

private struct UndoRedoContractDouble: CoreUndoActionLogging, CoreRedoActionLogging {
    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        [
            UndoActionRecordSnapshot(
                actionID: "undo-1",
                kind: "rename",
                summary: "Rename note",
                affectedCount: 1,
                affectedFileNames: ["note.md"],
                status: .pending,
                canUndo: true,
                disabledReason: nil,
                createdAt: 1,
                updatedAt: 2
            )
        ]
    }

    func undoAction(repoPath _: String, actionID: String) async throws -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: actionID,
            status: .executed,
            summary: "Rename note undone",
            affectedCount: 1,
            refreshTargets: ["library"],
            completedAt: 3
        )
    }

    func listRedoActions(repoPath _: String) async throws -> [RedoActionRecordSnapshot] {
        [
            RedoActionRecordSnapshot(
                actionID: "redo-1",
                kind: "rename",
                summary: "Rename note",
                affectedCount: 1,
                affectedFileNames: ["note.md"],
                status: .available,
                canRedo: true,
                disabledReason: nil,
                sourceUndoActionID: "undo-1",
                createdAt: 4,
                updatedAt: 5
            )
        ]
    }

    func redoAction(repoPath _: String, actionID: String) async throws -> RedoActionResultSnapshot {
        RedoActionResultSnapshot(
            actionID: actionID,
            status: .executed,
            summary: "Rename note redone",
            affectedCount: 1,
            refreshTargets: ["library"],
            undoToken: "undo-2",
            completedAt: 6
        )
    }
}
