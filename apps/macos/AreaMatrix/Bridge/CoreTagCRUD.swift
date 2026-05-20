import Foundation

protocol CoreTagCRUD: Sendable {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot
    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot
}

protocol CoreUndoActionLogging: Sendable {
    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot]
    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot
}

struct TagRecordSnapshot: Equatable, Identifiable {
    var value: String
    var label: String
    var fileCount: Int64
    var selected: Bool
    var disabled: Bool
    var updatedAt: Int64

    var id: String { value }

    var displayName: String {
        label.isEmpty ? value : label
    }
}

struct TagSetSnapshot: Equatable {
    var fileID: Int64
    var fileTags: [TagRecordSnapshot]
    var availableTags: [TagRecordSnapshot]
    var recentTags: [TagRecordSnapshot]
    var updatedAt: Int64
}

enum BatchMutationStatusSnapshot: Equatable {
    case added
    case alreadyHadTag
    case failed
}

struct BatchMutationItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var tag: String
    var status: BatchMutationStatusSnapshot
    var error: String?

    var id: String {
        "\(fileID):\(tag):\(status)"
    }
}

struct BatchMutationReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var requestedTagCount: Int64
    var addedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchMutationItemResultSnapshot]
    var undoToken: String?
}

enum UndoActionStatusSnapshot: String, Equatable {
    case pending = "Pending"
    case executed = "Executed"
    case expired = "Expired"
    case blocked = "Blocked"
}

struct UndoActionRecordSnapshot: Equatable, Identifiable {
    var actionID: String
    var kind: String
    var summary: String
    var affectedCount: Int64
    var affectedFileNames: [String]
    var status: UndoActionStatusSnapshot
    var canUndo: Bool
    var disabledReason: String?
    var createdAt: Int64
    var updatedAt: Int64

    var id: String { actionID }
}

struct UndoActionResultSnapshot: Equatable {
    var actionID: String
    var status: UndoActionStatusSnapshot
    var summary: String
    var affectedCount: Int64
    var refreshTargets: [String]
    var completedAt: Int64
}

extension CoreTagCRUD {
    func batchAddTags(repoPath _: String, fileIDs _: [Int64], tags _: [String]) async throws -> BatchMutationReportSnapshot {
        throw CoreError.Internal(message: "batch_add_tags is unavailable")
    }
}

extension CoreBridge: CoreTagCRUD {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.listTags(repoPath: repoPath, fileId: fileID))
        }.value
    }

    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.addTag(repoPath: repoPath, fileId: fileID, tag: tag))
        }.value
    }

    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.removeTag(repoPath: repoPath, fileId: fileID, tag: tag))
        }.value
    }

    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchMutationReportSnapshot(coreReport: AreaMatrix.batchAddTags(
                repoPath: repoPath,
                fileIds: fileIDs,
                tags: tags
            ))
        }.value
    }
}

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

private extension TagSetSnapshot {
    init(coreTagSet: TagSet) {
        fileID = coreTagSet.fileId
        fileTags = coreTagSet.fileTags.map(TagRecordSnapshot.init(coreRecord:))
        availableTags = coreTagSet.availableTags.map(TagRecordSnapshot.init(coreRecord:))
        recentTags = coreTagSet.recentTags.map(TagRecordSnapshot.init(coreRecord:))
        updatedAt = coreTagSet.updatedAt
    }
}

private extension TagRecordSnapshot {
    init(coreRecord: TagRecord) {
        value = coreRecord.value
        label = coreRecord.label
        fileCount = coreRecord.fileCount
        selected = coreRecord.selected
        disabled = coreRecord.disabled
        updatedAt = coreRecord.updatedAt
    }
}

private extension BatchMutationReportSnapshot {
    init(coreReport: BatchMutationReport) {
        requestedFileCount = coreReport.requestedFileCount
        requestedTagCount = coreReport.requestedTagCount
        addedCount = coreReport.addedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchMutationItemResultSnapshot.init(coreResult:))
        undoToken = coreReport.undoToken
    }
}

private extension BatchMutationItemResultSnapshot {
    init(coreResult: BatchMutationItemResult) {
        fileID = coreResult.fileId
        tag = coreResult.tag
        status = BatchMutationStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension BatchMutationStatusSnapshot {
    init(coreStatus: BatchMutationStatus) {
        switch coreStatus {
        case .added:
            self = .added
        case .alreadyHadTag:
            self = .alreadyHadTag
        case .failed:
            self = .failed
        }
    }
}

private extension UndoActionRecordSnapshot {
    init(coreRecord: UndoActionRecord) {
        actionID = coreRecord.actionId
        kind = coreRecord.kind
        summary = coreRecord.summary
        affectedCount = coreRecord.affectedCount
        affectedFileNames = coreRecord.affectedFileNames
        status = UndoActionStatusSnapshot(coreStatus: coreRecord.status)
        canUndo = coreRecord.canUndo
        disabledReason = coreRecord.disabledReason
        createdAt = coreRecord.createdAt
        updatedAt = coreRecord.updatedAt
    }
}

private extension UndoActionResultSnapshot {
    init(coreResult: UndoActionResult) {
        actionID = coreResult.actionId
        status = UndoActionStatusSnapshot(coreStatus: coreResult.status)
        summary = coreResult.summary
        affectedCount = coreResult.affectedCount
        refreshTargets = coreResult.refreshTargets
        completedAt = coreResult.completedAt
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
