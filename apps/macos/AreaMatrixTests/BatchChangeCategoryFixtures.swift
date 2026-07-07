@testable import AreaMatrix

func batchChangeCategoryRepoPath() -> String {
    "/tmp/repo"
}

extension UndoActionRecordSnapshot {
    static var batchChangeCategoryAction: UndoActionRecordSnapshot {
        UndoActionRecordSnapshot.testFixture(
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
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/\(currentName)",
            currentName: currentName,
            category: "docs"
        ) {
            $0.hashSha256 = "batchChangeCategory-category-\(id)"
        }
    }

    static func batchChangeCategoryRouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/\(currentName)",
            currentName: currentName,
            category: "docs"
        ) {
            $0.hashSha256 = "batchChangeCategory-route-\(id)"
        }
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
    static func testFixture(
        requestedFileCount: Int64 = 2,
        targetCategory: String = "finance",
        movedCount: Int64 = 1,
        metadataOnlyCount: Int64 = 1,
        unchangedCount: Int64 = 0,
        skippedCount: Int64 = 0,
        failedCount: Int64 = 0,
        itemResults: [BatchCategoryChangeItemResultSnapshot] = [
            .batchChangeCategoryResult(fileID: 1, status: .moved),
            .batchChangeCategoryResult(fileID: 2, status: .metadataUpdated)
        ],
        updatedFiles: [FileEntrySnapshot] = [.batchChangeCategoryCategoryFixture(id: 1, currentName: "a.pdf")],
        undoToken: String? = "undo-batch-category"
    ) -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: requestedFileCount,
            targetCategory: targetCategory,
            movedCount: movedCount,
            metadataOnlyCount: metadataOnlyCount,
            unchangedCount: unchangedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            itemResults: itemResults,
            updatedFiles: updatedFiles,
            undoToken: undoToken
        )
    }

    static func batchChangeCategorySuccessReport() -> BatchCategoryChangeReportSnapshot {
        testFixture()
    }

    static func batchChangeCategoryPartialFailureReport() -> BatchCategoryChangeReportSnapshot {
        testFixture(
            metadataOnlyCount: 0,
            failedCount: 1,
            itemResults: [
                .batchChangeCategoryResult(fileID: 1, status: .moved),
                .batchChangeCategoryResult(fileID: 2, status: .failed, error: "Permission denied")
            ],
            undoToken: "undo-partial-batch-category"
        )
    }

    static func batchChangeCategoryAllFailedReport() -> BatchCategoryChangeReportSnapshot {
        testFixture(
            requestedFileCount: 1,
            movedCount: 0,
            metadataOnlyCount: 0,
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
