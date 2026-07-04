@testable import AreaMatrix

func batchChangeCategoryRepoPath() -> String {
    "/tmp/repo"
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

    static func batchChangeCategoryRouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "batchChangeCategory-route-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension BatchChangeCategoryReturnContext {
    static func batchChangeCategoryFixture(
        initialTargetCategory: String? = nil
    ) -> BatchChangeCategoryReturnContext {
        let route = BatchChangeCategoryRoute.batchChangeCategoryRoute(initialTargetCategory: initialTargetCategory)
        return BatchChangeCategoryReturnContext(
            route: route,
            handoff: BatchChangeCategoryNewCategoryHandoff(
                selectedFileIDs: route.fileIDs,
                currentTargetCategory: "finance"
            )
        )
    }
}

extension BatchChangeCategoryRoute {
    static func batchChangeCategoryRoute(initialTargetCategory: String? = nil) -> BatchChangeCategoryRoute {
        BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: [1, 2],
            selectedFiles: [
                .batchChangeCategoryRouteFixture(id: 1, currentName: "a.pdf"),
                .batchChangeCategoryRouteFixture(id: 2, currentName: "b.pdf")
            ],
            selectedCount: 2,
            disabledReason: nil,
            initialTargetCategory: initialTargetCategory
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
