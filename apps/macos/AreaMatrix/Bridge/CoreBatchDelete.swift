import Foundation

protocol CoreBatchDeleting: Sendable {
    func previewBatchDelete(
        repoPath: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot
    ) async throws -> BatchDeletePreviewReportSnapshot

    func batchDeleteToTrash(
        repoPath: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot,
        previewToken: String
    ) async throws -> BatchDeleteReportSnapshot
}

enum BatchDeleteModeSnapshot: String, Equatable {
    case moveToTrash = "Move to Trash"
    case removeFromIndex = "Remove from Index"
}

enum BatchDeletePreviewStatusSnapshot: String, Equatable {
    case willMoveToTrash = "Trash"
    case indexOnly = "Index only"
    case missing = "Missing"
    case skipped = "Skipped"
    case blocked = "Blocked"
}

struct BatchDeletePreviewItemSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var currentPath: String?
    var currentName: String?
    var storageMode: String?
    var deleteMode: BatchDeleteModeSnapshot
    var willMoveToTrash: Bool
    var willRemoveIndex: Bool
    var status: BatchDeletePreviewStatusSnapshot
    var reason: String?

    var id: Int64 {
        fileID
    }
}

struct BatchDeletePreviewReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var deleteMode: BatchDeleteModeSnapshot
    var previewToken: String
    var trashAvailable: Bool
    var undoAvailable: Bool
    var willTrashCount: Int64
    var indexOnlyCount: Int64
    var missingCount: Int64
    var skippedCount: Int64
    var blockedCount: Int64
    var items: [BatchDeletePreviewItemSnapshot]
    var canApply: Bool
    var applyBlockedReason: String?
}

enum BatchDeleteResultStatusSnapshot: String, Equatable {
    case movedToTrash = "Moved to Trash"
    case removedFromIndex = "Removed from Index"
    case skipped = "Skipped"
    case failed = "Failed"
}

struct BatchDeleteItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var finalPath: String?
    var status: BatchDeleteResultStatusSnapshot
    var error: String?

    var id: Int64 {
        fileID
    }
}

struct BatchDeleteReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var deleteMode: BatchDeleteModeSnapshot
    var movedToTrashCount: Int64
    var removedFromIndexCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchDeleteItemResultSnapshot]
    var affectedFileIDs: [Int64]
    var undoToken: String?
}

extension CoreBridge: CoreBatchDeleting {
    func previewBatchDelete(
        repoPath: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot
    ) async throws -> BatchDeletePreviewReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchDeletePreviewReportSnapshot(coreReport: AreaMatrix.previewBatchDelete(
                repoPath: repoPath,
                fileIds: fileIDs,
                deleteMode: BatchDeleteMode(snapshotValue: deleteMode)
            ))
        }.value
    }

    func batchDeleteToTrash(
        repoPath: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot,
        previewToken: String
    ) async throws -> BatchDeleteReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchDeleteReportSnapshot(coreReport: AreaMatrix.batchDeleteToTrash(
                repoPath: repoPath,
                fileIds: fileIDs,
                deleteMode: BatchDeleteMode(snapshotValue: deleteMode),
                previewToken: previewToken
            ))
        }.value
    }
}

private extension BatchDeleteMode {
    init(snapshotValue: BatchDeleteModeSnapshot) {
        switch snapshotValue {
        case .moveToTrash:
            self = .moveToTrash
        case .removeFromIndex:
            self = .removeFromIndex
        }
    }
}

private extension BatchDeleteModeSnapshot {
    init(coreMode: BatchDeleteMode) {
        switch coreMode {
        case .moveToTrash:
            self = .moveToTrash
        case .removeFromIndex:
            self = .removeFromIndex
        }
    }
}

private extension BatchDeletePreviewReportSnapshot {
    init(coreReport: BatchDeletePreviewReport) {
        requestedFileCount = coreReport.requestedFileCount
        deleteMode = BatchDeleteModeSnapshot(coreMode: coreReport.deleteMode)
        previewToken = coreReport.previewToken
        trashAvailable = coreReport.trashAvailable
        undoAvailable = coreReport.undoAvailable
        willTrashCount = coreReport.willTrashCount
        indexOnlyCount = coreReport.indexOnlyCount
        missingCount = coreReport.missingCount
        skippedCount = coreReport.skippedCount
        blockedCount = coreReport.blockedCount
        items = coreReport.items.map(BatchDeletePreviewItemSnapshot.init(coreItem:))
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
    }
}

private extension BatchDeletePreviewItemSnapshot {
    init(coreItem: BatchDeletePreviewItem) {
        fileID = coreItem.fileId
        currentPath = coreItem.currentPath
        currentName = coreItem.currentName
        storageMode = coreItem.storageMode?.batchDeleteDisplayName
        deleteMode = BatchDeleteModeSnapshot(coreMode: coreItem.deleteMode)
        willMoveToTrash = coreItem.willMoveToTrash
        willRemoveIndex = coreItem.willRemoveIndex
        status = BatchDeletePreviewStatusSnapshot(coreStatus: coreItem.status)
        reason = coreItem.reason
    }
}

private extension BatchDeletePreviewStatusSnapshot {
    init(coreStatus: BatchDeletePreviewStatus) {
        switch coreStatus {
        case .willMoveToTrash:
            self = .willMoveToTrash
        case .indexOnly:
            self = .indexOnly
        case .missing:
            self = .missing
        case .skipped:
            self = .skipped
        case .blocked:
            self = .blocked
        }
    }
}

private extension BatchDeleteReportSnapshot {
    init(coreReport: BatchDeleteReport) {
        requestedFileCount = coreReport.requestedFileCount
        deleteMode = BatchDeleteModeSnapshot(coreMode: coreReport.deleteMode)
        movedToTrashCount = coreReport.movedToTrashCount
        removedFromIndexCount = coreReport.removedFromIndexCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchDeleteItemResultSnapshot.init(coreResult:))
        affectedFileIDs = coreReport.affectedFileIds
        undoToken = coreReport.undoToken
    }
}

private extension BatchDeleteItemResultSnapshot {
    init(coreResult: BatchDeleteItemResult) {
        fileID = coreResult.fileId
        finalPath = coreResult.finalPath
        status = BatchDeleteResultStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension BatchDeleteResultStatusSnapshot {
    init(coreStatus: BatchDeleteResultStatus) {
        switch coreStatus {
        case .movedToTrash:
            self = .movedToTrash
        case .removedFromIndex:
            self = .removedFromIndex
        case .skipped:
            self = .skipped
        case .failed:
            self = .failed
        }
    }
}

private extension StorageMode {
    var batchDeleteDisplayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}
