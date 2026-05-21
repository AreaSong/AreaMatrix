@testable import AreaMatrix
import XCTest

final class ImportBatchResultSummaryTests: XCTestCase {
    @MainActor
    func testS212C208PreviewAndApplyUseCoreBridgeRequestAndPreviewToken() async {
        let preview = BatchCategoryPreviewReportSnapshot.s212Preview(token: "preview-current")
        let report = BatchCategoryChangeReportSnapshot.s212SuccessReport()
        let changer = S212RecordingBatchCategoryChanger(results: [
            .preview(.success(preview)),
            .apply(.success(report))
        ])

        let previewState = await BatchChangeCategoryAction.preview(
            repoPath: "/tmp/repo",
            fileIDs: [2, 1],
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            changer: changer,
            errorMapper: S212ErrorMapper()
        )
        guard let loadedPreview = previewState.report else {
            return XCTFail("Expected S2-12 preview to load from C2-08 CoreBridge")
        }
        let apply = await BatchChangeCategoryAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [2, 1],
            preview: loadedPreview,
            changer: changer,
            errorMapper: S212ErrorMapper()
        )
        let requests = await changer.recordedRequests()

        XCTAssertEqual(requests, [
            "preview|/tmp/repo|2,1|finance|true",
            "apply|/tmp/repo|2,1|finance|true|preview-current"
        ])
        XCTAssertEqual(apply.report, report)
        XCTAssertNil(apply.failure)
    }

    func testS212C208ApplyRequiresLatestPreviewSelectionAndUnblockedDryRun() {
        let preview = BatchCategoryPreviewReportSnapshot.s212Preview(token: "preview-current")
        var blockedPreview = preview
        blockedPreview.canApply = false
        blockedPreview.blockedCount = 1
        blockedPreview.applyBlockedReason = "Target folder is not writable."

        XCTAssertTrue(BatchChangeCategoryValidation.canApply(
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: preview,
            disabledReason: nil,
            isApplying: false
        ))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(
            targetCategory: "archive",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: preview,
            disabledReason: nil,
            isApplying: false
        ))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(
            targetCategory: "finance",
            moveRepoOwnedFiles: false,
            fileIDs: [1, 2],
            preview: preview,
            disabledReason: nil,
            isApplying: false
        ))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2, 3],
            preview: preview,
            disabledReason: nil,
            isApplying: false
        ))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: blockedPreview,
            disabledReason: nil,
            isApplying: false
        ))
    }

    func testS212C208PartialFailureStillRefreshesSuccessfulItemsAndUndoContext() {
        let partial = BatchCategoryChangeReportSnapshot.s212PartialFailureReport()
        let allFailed = BatchCategoryChangeReportSnapshot.s212AllFailedReport()

        XCTAssertEqual(partial.successfulChangeCount, 1)
        XCTAssertTrue(partial.shouldRefreshConsumerAfterApply)
        XCTAssertFalse(partial.shouldCloseSheetAfterApply)
        XCTAssertFalse(allFailed.shouldRefreshConsumerAfterApply)
        XCTAssertFalse(allFailed.shouldCloseSheetAfterApply)
    }

    func testS212CreateNewCategoryRoutesToS219WithoutCreatingInlineCategory() {
        let handoff = BatchChangeCategoryNewCategoryHandoff(
            selectedFileIDs: [1, 2],
            currentTargetCategory: "finance"
        )
        let createdCategories = BatchChangeCategoryCreatedCategoryReturn.updatedCategories(
            ["finance"],
            savedCategory: " tax "
        )

        XCTAssertEqual(handoff.sourcePageID, "S2-12")
        XCTAssertEqual(handoff.targetPageID, "S2-19")
        XCTAssertEqual(createdCategories, ["finance", "tax"])
        XCTAssertEqual(MainSearchDestination.classifierRuleEditor(sourcePageID: handoff.sourcePageID).pageID, "S2-19")
    }

    @MainActor
    func testS118PreviewErrorAndPartialSuccessSurfaceFailedItemInResultSummary() async {
        let readyURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let failedPreviewURL = URL(fileURLWithPath: "/tmp/unreadable.mov")
        let rows = [
            ImportBatchPreviewRow.ready(
                url: readyURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.failed(
                url: failedPreviewURL,
                message: "无法读取分类预览路径：/tmp/unreadable.mov"
            )
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(
            rows,
            request: s118ResultSummaryRequest(urls: [readyURL, failedPreviewURL]),
            selectedDestination: .autoClassify
        )
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.previewErrorCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            skipped: 0,
            pending: 0
        ))
    }

    @MainActor
    func testS118SkippedDuplicateAndPendingICloudSurfaceInProgressResultSummary() async {
        let duplicateURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let rows = [
            ImportBatchPreviewRow.duplicate(
                url: duplicateURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                ),
                existingPath: "finance/Invoice_2026Q1.pdf"
            ),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let model = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(
            rows,
            request: s118ResultSummaryRequest(urls: [duplicateURL, cloudURL]),
            selectedDestination: .autoClassify
        )
        model.markICloudPlaceholderPending(rowID: rows[1].id)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries, [])
        XCTAssertEqual(outcome?.skippedDuplicateCount, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "Import ready only",
            skipped: 1,
            pending: 1
        ))
    }
}

private func s118ResultSummaryRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "finance"]
    )
}

private extension FileEntrySnapshot {
    static func s212CategoryFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "s212-category-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension BatchCategoryPreviewReportSnapshot {
    static func s212Preview(token: String) -> BatchCategoryPreviewReportSnapshot {
        BatchCategoryPreviewReportSnapshot(
            requestedFileCount: 2,
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            previewToken: token,
            categoryDistribution: [
                CategoryDistributionItemSnapshot(category: "docs", count: 2)
            ],
            willMoveCount: 1,
            metadataOnlyCount: 1,
            unchangedCount: 0,
            skippedCount: 0,
            blockedCount: 0,
            items: [
                BatchCategoryPreviewItemSnapshot.s212Item(fileID: 1, status: .willMove),
                BatchCategoryPreviewItemSnapshot.s212Item(fileID: 2, status: .metadataOnly, indexOnly: true)
            ],
            canApply: true,
            applyBlockedReason: nil
        )
    }
}

private extension BatchCategoryPreviewItemSnapshot {
    static func s212Item(
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

private extension BatchCategoryChangeReportSnapshot {
    static func s212SuccessReport() -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: 2,
            targetCategory: "finance",
            movedCount: 1,
            metadataOnlyCount: 1,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                BatchCategoryChangeItemResultSnapshot.s212Result(fileID: 1, status: .moved),
                BatchCategoryChangeItemResultSnapshot.s212Result(fileID: 2, status: .metadataUpdated)
            ],
            updatedFiles: [.s212CategoryFixture(id: 1, currentName: "a.pdf")],
            undoToken: "undo-c2-08"
        )
    }

    static func s212PartialFailureReport() -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: 2,
            targetCategory: "finance",
            movedCount: 1,
            metadataOnlyCount: 0,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                BatchCategoryChangeItemResultSnapshot.s212Result(fileID: 1, status: .moved),
                BatchCategoryChangeItemResultSnapshot.s212Result(
                    fileID: 2,
                    status: .failed,
                    error: "Permission denied"
                )
            ],
            updatedFiles: [.s212CategoryFixture(id: 1, currentName: "a.pdf")],
            undoToken: "undo-partial-c2-08"
        )
    }

    static func s212AllFailedReport() -> BatchCategoryChangeReportSnapshot {
        BatchCategoryChangeReportSnapshot(
            requestedFileCount: 1,
            targetCategory: "finance",
            movedCount: 0,
            metadataOnlyCount: 0,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                BatchCategoryChangeItemResultSnapshot.s212Result(
                    fileID: 2,
                    status: .failed,
                    error: "Permission denied"
                )
            ],
            updatedFiles: [],
            undoToken: nil
        )
    }
}

private extension BatchCategoryChangeItemResultSnapshot {
    static func s212Result(
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

private actor S212RecordingBatchCategoryChanger: CoreBatchCategoryChanging {
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
        requests.append("preview|\(repoPath)|\(fileIDs.map(String.init).joined(separator: ","))|\(targetCategory)|\(moveRepoOwnedFiles)")
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
        requests.append(
            "apply|\(repoPath)|\(fileIDs.map(String.init).joined(separator: ","))|\(targetCategory)|\(moveRepoOwnedFiles)|\(previewToken)"
        )
        guard !results.isEmpty, case let .apply(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected batch_move_to_category")
        }
        return try result.get()
    }

    func recordedRequests() -> [String] {
        requests
    }
}

private actor S212ErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind(for: error),
            userMessage: "Batch category update failed",
            severity: .medium,
            suggestedAction: "Review failed items and refresh the preview.",
            recoverability: .refreshRequired,
            rawContext: "S2-12 C2-08 batch-change-category"
        )
    }

    private func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        switch error {
        case .Conflict:
            .conflict
        case .FileNotFound:
            .fileNotFound
        case .PermissionDenied:
            .permissionDenied
        case .Db:
            .db
        case .Io:
            .io
        default:
            .internal
        }
    }
}
