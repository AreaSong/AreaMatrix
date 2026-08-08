import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreUndoActionLogging = AreaMatrixCoreBridgeContract.CoreUndoActionLogging
typealias CoreRedoActionLogging = AreaMatrixCoreBridgeContract.CoreRedoActionLogging
typealias UndoActionStatusSnapshot = AreaMatrixCoreBridgeContract.UndoActionStatusSnapshot
typealias RedoActionStatusSnapshot = AreaMatrixCoreBridgeContract.RedoActionStatusSnapshot
typealias UndoActionRecordSnapshot = AreaMatrixCoreBridgeContract.UndoActionRecordSnapshot
typealias UndoActionResultSnapshot = AreaMatrixCoreBridgeContract.UndoActionResultSnapshot
typealias RedoActionRecordSnapshot = AreaMatrixCoreBridgeContract.RedoActionRecordSnapshot
typealias RedoActionResultSnapshot = AreaMatrixCoreBridgeContract.RedoActionResultSnapshot

extension CoreBridge: CoreUndoActionLogging {
    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.listUndoActions(repoPath: repoPath).map(UndoActionRecordSnapshot.init(coreRecord:))
        }.value
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try UndoActionResultSnapshot(coreResult: AreaMatrix.undoAction(repoPath: repoPath, actionId: actionID))
        }.value
    }
}

extension CoreBridge: CoreRedoActionLogging {
    func listRedoActions(repoPath: String) async throws -> [RedoActionRecordSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.listRedoActions(repoPath: repoPath).map(RedoActionRecordSnapshot.init(coreRecord:))
        }.value
    }

    func redoAction(repoPath: String, actionID: String) async throws -> RedoActionResultSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try RedoActionResultSnapshot(coreResult: AreaMatrix.redoAction(repoPath: repoPath, actionId: actionID))
        }.value
    }
}

private extension UndoActionRecordSnapshot {
    init(coreRecord: UndoActionRecord) {
        self.init(
            actionID: coreRecord.actionId,
            kind: coreRecord.kind,
            summary: coreRecord.summary,
            affectedCount: coreRecord.affectedCount,
            affectedFileNames: coreRecord.affectedFileNames,
            status: UndoActionStatusSnapshot(coreStatus: coreRecord.status),
            canUndo: coreRecord.canUndo,
            disabledReason: coreRecord.disabledReason,
            createdAt: coreRecord.createdAt,
            updatedAt: coreRecord.updatedAt
        )
    }
}

private extension UndoActionResultSnapshot {
    init(coreResult: UndoActionResult) {
        self.init(
            actionID: coreResult.actionId,
            status: UndoActionStatusSnapshot(coreStatus: coreResult.status),
            summary: coreResult.summary,
            affectedCount: coreResult.affectedCount,
            refreshTargets: coreResult.refreshTargets,
            completedAt: coreResult.completedAt
        )
    }
}

private extension RedoActionRecordSnapshot {
    init(coreRecord: RedoActionRecord) {
        self.init(
            actionID: coreRecord.actionId,
            kind: coreRecord.kind,
            summary: coreRecord.summary,
            affectedCount: coreRecord.affectedCount,
            affectedFileNames: coreRecord.affectedFileNames,
            status: RedoActionStatusSnapshot(coreStatus: coreRecord.status),
            canRedo: coreRecord.canRedo,
            disabledReason: coreRecord.disabledReason,
            sourceUndoActionID: coreRecord.sourceUndoActionId,
            createdAt: coreRecord.createdAt,
            updatedAt: coreRecord.updatedAt
        )
    }
}

private extension RedoActionResultSnapshot {
    init(coreResult: RedoActionResult) {
        self.init(
            actionID: coreResult.actionId,
            status: RedoActionStatusSnapshot(coreStatus: coreResult.status),
            summary: coreResult.summary,
            affectedCount: coreResult.affectedCount,
            refreshTargets: coreResult.refreshTargets,
            undoToken: coreResult.undoToken,
            completedAt: coreResult.completedAt
        )
    }
}

private extension UndoActionStatusSnapshot {
    init(coreStatus: UndoActionStatus) {
        switch coreStatus {
        case .pending:
            self = .pending
        case .executed:
            self = .executed
        case .expired:
            self = .expired
        case .blocked:
            self = .blocked
        }
    }
}

private extension RedoActionStatusSnapshot {
    init(coreStatus: RedoActionStatus) {
        switch coreStatus {
        case .available:
            self = .available
        case .cleared:
            self = .cleared
        case .blocked:
            self = .blocked
        case .expired:
            self = .expired
        case .executed:
            self = .executed
        }
    }
}
