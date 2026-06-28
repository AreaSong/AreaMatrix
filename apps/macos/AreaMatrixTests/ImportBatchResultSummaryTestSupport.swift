@testable import AreaMatrix
import Foundation

func importBatchResultSummaryRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "finance"]
    )
}

actor BatchChangeCategoryRecordingUndoStore: CoreUndoActionLogging {
    private let actions: [UndoActionRecordSnapshot]

    init(actions: [UndoActionRecordSnapshot]) {
        self.actions = actions
    }

    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        actions
    }

    func undoAction(repoPath _: String, actionID _: String) async throws -> UndoActionResultSnapshot {
        throw CoreError.Internal(message: "batch-change-category completion must not execute undo")
    }
}

extension UndoActionRecordSnapshot {
    static var batchChangeCategoryAction: UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-batch-category",
            kind: "batch_move_to_category",
            summary: "Changed category for 2 files.",
            affectedCount: 2,
            affectedFileNames: ["a.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }
}

extension FileEntrySnapshot {
    static func batchChangeCategoryCategoryFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "batchChangeCategory-category-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension BatchCategoryPreviewReportSnapshot {
    static func batchChangeCategoryPreview() -> BatchCategoryPreviewReportSnapshot {
        BatchCategoryPreviewReportSnapshot(
            requestedFileCount: 2,
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            previewToken: "preview-current",
            categoryDistribution: [
                CategoryDistributionItemSnapshot(category: "docs", count: 2)
            ],
            willMoveCount: 1,
            metadataOnlyCount: 1,
            unchangedCount: 0,
            skippedCount: 0,
            blockedCount: 0,
            items: [
                .batchChangeCategoryItem(fileID: 1, status: .willMove),
                .batchChangeCategoryItem(fileID: 2, status: .metadataOnly, indexOnly: true)
            ],
            canApply: true,
            applyBlockedReason: nil
        )
    }
}

extension BatchCategoryPreviewItemSnapshot {
    static func batchChangeCategoryItem(
        fileID: Int64,
        status: BatchCategoryPreviewStatusSnapshot,
        indexOnly: Bool = false
    ) -> BatchCategoryPreviewItemSnapshot {
        BatchCategoryPreviewItemSnapshot(
            fileID: fileID,
            fromCategory: "docs",
            toCategory: "finance",
            currentPath: "docs/file-\(fileID).pdf",
            targetPath: "finance/file-\(fileID).pdf",
            targetName: "file-\(fileID).pdf",
            storageMode: indexOnly ? "Indexed" : "Copied",
            indexOnly: indexOnly,
            willMoveFile: status == .willMove,
            status: status,
            reason: nil
        )
    }
}

extension BatchCategoryChangeReportSnapshot {
    static func batchChangeCategorySuccessReport() -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: 2,
            targetCategory: "finance",
            movedCount: 1,
            metadataOnlyCount: 1,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                .batchChangeCategoryResult(fileID: 1, status: .moved),
                .batchChangeCategoryResult(fileID: 2, status: .metadataUpdated)
            ],
            updatedFiles: [.batchChangeCategoryCategoryFixture(id: 1, currentName: "a.pdf")],
            undoToken: "undo-batch-category"
        )
    }

    static func batchChangeCategoryPartialFailureReport() -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: 2,
            targetCategory: "finance",
            movedCount: 1,
            metadataOnlyCount: 0,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                .batchChangeCategoryResult(fileID: 1, status: .moved),
                .batchChangeCategoryResult(fileID: 2, status: .failed, error: "Permission denied")
            ],
            updatedFiles: [.batchChangeCategoryCategoryFixture(id: 1, currentName: "a.pdf")],
            undoToken: "undo-partial-batch-category"
        )
    }

    static func batchChangeCategoryAllFailedReport() -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: 1,
            targetCategory: "finance",
            movedCount: 0,
            metadataOnlyCount: 0,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                .batchChangeCategoryResult(fileID: 2, status: .failed, error: "Permission denied")
            ],
            updatedFiles: [],
            undoToken: nil
        )
    }
}

extension BatchCategoryChangeItemResultSnapshot {
    static func batchChangeCategoryResult(
        fileID: Int64,
        status: BatchCategoryResultStatusSnapshot,
        error: String? = nil
    ) -> BatchCategoryChangeItemResultSnapshot {
        BatchCategoryChangeItemResultSnapshot(
            fileID: fileID,
            fromCategory: "docs",
            toCategory: "finance",
            finalPath: "finance/file-\(fileID).pdf",
            status: status,
            error: error
        )
    }
}

actor BatchCategoryChanger: CoreBatchCategoryChanging {
    enum Result {
        case preview(Swift.Result<BatchCategoryPreviewReportSnapshot, Error>)
        case apply(Swift.Result<BatchCategoryChangeReportSnapshot, Error>)
    }

    private var results: [Result]
    private var requests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func previewBatchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    ) async throws -> BatchCategoryPreviewReportSnapshot {
        requests.append(requestLabel(
            action: "preview",
            repoPath: repoPath,
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles
        ))
        guard !results.isEmpty, case let .preview(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected preview_batch_move_to_category")
        }
        return try result.get()
    }

    func batchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        previewToken: String
    ) async throws -> BatchCategoryChangeReportSnapshot {
        requests.append(requestLabel(
            action: "apply",
            repoPath: repoPath,
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles,
            previewToken: previewToken
        ))
        guard !results.isEmpty, case let .apply(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected batch_move_to_category")
        }
        return try result.get()
    }

    func recordedRequests() -> [String] {
        requests
    }

    private func requestLabel(
        action: String,
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        previewToken: String? = nil
    ) -> String {
        let base = "\(action)|\(repoPath)|\(fileIDs.map(String.init).joined(separator: ","))"
        return "\(base)|\(targetCategory)|\(moveRepoOwnedFiles)\(previewToken.map { "|\($0)" } ?? "")"
    }
}

actor BatchChangeCategoryErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: CoreErrorKindTestMapper.kind(for: error),
            userMessage: "Batch category update failed",
            severity: .medium,
            suggestedAction: "Review failed items and refresh the preview.",
            recoverability: .refreshRequired,
            rawContext: "batch-change-category batch-change-category-core batch-change-category"
        )
    }
}
