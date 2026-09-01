/// Stable undo and redo capability contracts consumed by feature models.
public protocol CoreUndoActionLogging: Sendable {
    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot]
    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot
}

/// Stable redo capability contract consumed by feature models.
public protocol CoreRedoActionLogging: Sendable {
    func listRedoActions(repoPath: String) async throws -> [RedoActionRecordSnapshot]
    func redoAction(repoPath: String, actionID: String) async throws -> RedoActionResultSnapshot
}

public enum UndoActionStatusSnapshot: String, Equatable, Sendable {
    case pending = "Pending"
    case executed = "Executed"
    case expired = "Expired"
    case blocked = "Blocked"
}

public enum RedoActionStatusSnapshot: String, Equatable, Sendable {
    case available = "Available"
    case cleared = "Cleared"
    case blocked = "Blocked"
    case expired = "Expired"
    case executed = "Executed"
}

public struct UndoActionRecordSnapshot: Equatable, Identifiable, Sendable {
    public var actionID: String
    public var kind: String
    public var summary: String
    public var affectedCount: Int64
    public var affectedFileNames: [String]
    public var status: UndoActionStatusSnapshot
    public var canUndo: Bool
    public var disabledReason: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public var id: String {
        actionID
    }

    public init(
        actionID: String,
        kind: String,
        summary: String,
        affectedCount: Int64,
        affectedFileNames: [String],
        status: UndoActionStatusSnapshot,
        canUndo: Bool,
        disabledReason: String?,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.actionID = actionID
        self.kind = kind
        self.summary = summary
        self.affectedCount = affectedCount
        self.affectedFileNames = affectedFileNames
        self.status = status
        self.canUndo = canUndo
        self.disabledReason = disabledReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct UndoActionResultSnapshot: Equatable, Sendable {
    public var actionID: String
    public var status: UndoActionStatusSnapshot
    public var summary: String
    public var affectedCount: Int64
    public var refreshTargets: [String]
    public var completedAt: Int64

    public init(
        actionID: String,
        status: UndoActionStatusSnapshot,
        summary: String,
        affectedCount: Int64,
        refreshTargets: [String],
        completedAt: Int64
    ) {
        self.actionID = actionID
        self.status = status
        self.summary = summary
        self.affectedCount = affectedCount
        self.refreshTargets = refreshTargets
        self.completedAt = completedAt
    }
}

public struct RedoActionRecordSnapshot: Equatable, Identifiable, Sendable {
    public var actionID: String
    public var kind: String
    public var summary: String
    public var affectedCount: Int64
    public var affectedFileNames: [String]
    public var status: RedoActionStatusSnapshot
    public var canRedo: Bool
    public var disabledReason: String?
    public var sourceUndoActionID: String
    public var createdAt: Int64
    public var updatedAt: Int64

    public var id: String {
        actionID
    }

    public init(
        actionID: String,
        kind: String,
        summary: String,
        affectedCount: Int64,
        affectedFileNames: [String],
        status: RedoActionStatusSnapshot,
        canRedo: Bool,
        disabledReason: String?,
        sourceUndoActionID: String,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.actionID = actionID
        self.kind = kind
        self.summary = summary
        self.affectedCount = affectedCount
        self.affectedFileNames = affectedFileNames
        self.status = status
        self.canRedo = canRedo
        self.disabledReason = disabledReason
        self.sourceUndoActionID = sourceUndoActionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RedoActionResultSnapshot: Equatable, Sendable {
    public var actionID: String
    public var status: RedoActionStatusSnapshot
    public var summary: String
    public var affectedCount: Int64
    public var refreshTargets: [String]
    public var undoToken: String?
    public var completedAt: Int64

    public init(
        actionID: String,
        status: RedoActionStatusSnapshot,
        summary: String,
        affectedCount: Int64,
        refreshTargets: [String],
        undoToken: String?,
        completedAt: Int64
    ) {
        self.actionID = actionID
        self.status = status
        self.summary = summary
        self.affectedCount = affectedCount
        self.refreshTargets = refreshTargets
        self.undoToken = undoToken
        self.completedAt = completedAt
    }
}
