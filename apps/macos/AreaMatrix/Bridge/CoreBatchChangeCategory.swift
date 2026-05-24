import Foundation

protocol CoreBatchCategoryChanging: Sendable {
    func previewBatchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    ) async throws -> BatchCategoryPreviewReportSnapshot

    func batchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        previewToken: String
    ) async throws -> BatchCategoryChangeReportSnapshot
}

struct CategoryDistributionItemSnapshot: Equatable, Identifiable {
    var category: String
    var count: Int64

    var id: String { category }
}

enum BatchCategoryPreviewStatusSnapshot: String, Equatable {
    case willMove = "Will move"
    case metadataOnly = "Metadata only"
    case unchanged = "Unchanged"
    case skipped = "Skipped"
    case blocked = "Blocked"
}

struct BatchCategoryPreviewItemSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var fromCategory: String?
    var toCategory: String
    var currentPath: String?
    var targetPath: String?
    var targetName: String?
    var storageMode: String?
    var indexOnly: Bool
    var willMoveFile: Bool
    var status: BatchCategoryPreviewStatusSnapshot
    var reason: String?

    var id: Int64 { fileID }
}

struct BatchCategoryPreviewReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var targetCategory: String
    var moveRepoOwnedFiles: Bool
    var previewToken: String
    var categoryDistribution: [CategoryDistributionItemSnapshot]
    var willMoveCount: Int64
    var metadataOnlyCount: Int64
    var unchangedCount: Int64
    var skippedCount: Int64
    var blockedCount: Int64
    var items: [BatchCategoryPreviewItemSnapshot]
    var canApply: Bool
    var applyBlockedReason: String?
}

enum BatchCategoryResultStatusSnapshot: String, Equatable {
    case moved = "Moved"
    case metadataUpdated = "Metadata updated"
    case unchanged = "Unchanged"
    case skipped = "Skipped"
    case failed = "Failed"
}

struct BatchCategoryChangeItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var fromCategory: String?
    var toCategory: String
    var finalPath: String?
    var status: BatchCategoryResultStatusSnapshot
    var error: String?

    var id: Int64 { fileID }
}

struct BatchCategoryChangeReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var targetCategory: String
    var movedCount: Int64
    var metadataOnlyCount: Int64
    var unchangedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchCategoryChangeItemResultSnapshot]
    var updatedFiles: [FileEntrySnapshot]
    var undoToken: String?
}

extension CoreBridge: CoreBatchCategoryChanging {
    func previewBatchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    ) async throws -> BatchCategoryPreviewReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchCategoryPreviewReportSnapshot(coreReport: AreaMatrix.previewBatchMoveToCategory(
                repoPath: repoPath,
                fileIds: fileIDs,
                targetCategory: targetCategory,
                moveRepoOwnedFiles: moveRepoOwnedFiles
            ))
        }.value
    }

    func batchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        previewToken: String
    ) async throws -> BatchCategoryChangeReportSnapshot {
        let report = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.batchMoveToCategory(
                repoPath: repoPath,
                fileIds: fileIDs,
                targetCategory: targetCategory,
                moveRepoOwnedFiles: moveRepoOwnedFiles,
                previewToken: previewToken
            )
        }.value
        let updatedFiles = await makeFileEntrySnapshots(from: report.updatedFiles, repoPath: repoPath)
        return BatchCategoryChangeReportSnapshot(coreReport: report, updatedFiles: updatedFiles)
    }
}

private extension BatchCategoryPreviewReportSnapshot {
    init(coreReport: BatchCategoryPreviewReport) {
        requestedFileCount = coreReport.requestedFileCount
        targetCategory = coreReport.targetCategory
        moveRepoOwnedFiles = coreReport.moveRepoOwnedFiles
        previewToken = coreReport.previewToken
        categoryDistribution = coreReport.categoryDistribution.map(CategoryDistributionItemSnapshot.init(coreItem:))
        willMoveCount = coreReport.willMoveCount
        metadataOnlyCount = coreReport.metadataOnlyCount
        unchangedCount = coreReport.unchangedCount
        skippedCount = coreReport.skippedCount
        blockedCount = coreReport.blockedCount
        items = coreReport.items.map(BatchCategoryPreviewItemSnapshot.init(coreItem:))
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
    }
}

private extension CategoryDistributionItemSnapshot {
    init(coreItem: CategoryDistributionItem) {
        category = coreItem.category
        count = coreItem.count
    }
}

private extension BatchCategoryPreviewItemSnapshot {
    init(coreItem: BatchCategoryPreviewItem) {
        fileID = coreItem.fileId
        fromCategory = coreItem.fromCategory
        toCategory = coreItem.toCategory
        currentPath = coreItem.currentPath
        targetPath = coreItem.targetPath
        targetName = coreItem.targetName
        storageMode = coreItem.storageMode?.batchCategoryDisplayName
        indexOnly = coreItem.indexOnly
        willMoveFile = coreItem.willMoveFile
        status = BatchCategoryPreviewStatusSnapshot(coreStatus: coreItem.status)
        reason = coreItem.reason
    }
}

private extension BatchCategoryPreviewStatusSnapshot {
    init(coreStatus: BatchCategoryPreviewStatus) {
        switch coreStatus {
        case .willMove:
            self = .willMove
        case .metadataOnly:
            self = .metadataOnly
        case .unchanged:
            self = .unchanged
        case .skipped:
            self = .skipped
        case .blocked:
            self = .blocked
        }
    }
}

private extension StorageMode {
    var batchCategoryDisplayName: String {
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

private extension BatchCategoryChangeReportSnapshot {
    init(coreReport: BatchCategoryChangeReport, updatedFiles: [FileEntrySnapshot]) {
        requestedFileCount = coreReport.requestedFileCount
        targetCategory = coreReport.targetCategory
        movedCount = coreReport.movedCount
        metadataOnlyCount = coreReport.metadataOnlyCount
        unchangedCount = coreReport.unchangedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchCategoryChangeItemResultSnapshot.init(coreResult:))
        self.updatedFiles = updatedFiles
        undoToken = coreReport.undoToken
    }
}

private extension BatchCategoryChangeItemResultSnapshot {
    init(coreResult: BatchCategoryChangeItemResult) {
        fileID = coreResult.fileId
        fromCategory = coreResult.fromCategory
        toCategory = coreResult.toCategory
        finalPath = coreResult.finalPath
        status = BatchCategoryResultStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension BatchCategoryResultStatusSnapshot {
    init(coreStatus: BatchCategoryResultStatus) {
        switch coreStatus {
        case .moved:
            self = .moved
        case .metadataUpdated:
            self = .metadataUpdated
        case .unchanged:
            self = .unchanged
        case .skipped:
            self = .skipped
        case .failed:
            self = .failed
        }
    }
}
