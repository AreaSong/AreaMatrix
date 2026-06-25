@testable import AreaMatrix
import XCTest

// swiftlint:disable file_length
final class ImportBatchResultSummaryTests: XCTestCase {
    @MainActor
    func testBatchChangeCategoryBatchChangeCategoryCorePreviewApplyUndoAndRouteStayWithinControlMap() async {
        let preview = BatchCategoryPreviewReportSnapshot.batchChangeCategoryPreview()
        let report = BatchCategoryChangeReportSnapshot.batchChangeCategorySuccessReport()
        let changer = BatchChangeCategoryRecordingBatchCategoryChanger(results: [
            .preview(.success(preview)),
            .apply(.success(report))
        ])

        let previewState = await BatchChangeCategoryAction.preview(
            request: BatchChangeCategoryPreviewRequest(
                repoPath: "/tmp/repo",
                fileIDs: [2, 1],
                targetCategory: "finance",
                moveRepoOwnedFiles: true
            ),
            changer: changer,
            errorMapper: BatchChangeCategoryErrorMapper()
        )
        let apply = await BatchChangeCategoryAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [2, 1],
            preview: preview,
            changer: changer,
            errorMapper: BatchChangeCategoryErrorMapper()
        )
        let undoState = await BatchChangeCategoryUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: report,
            failure: nil,
            undoStore: BatchChangeCategoryRecordingUndoStore(actions: [.batchChangeCategoryAction]),
            errorMapper: BatchChangeCategoryErrorMapper()
        )
        let createdCategories = BatchChangeCategoryCreatedCategoryReturn
            .updatedCategories(["finance"], savedCategory: "tax")
        let requests = await changer.recordedRequests()

        XCTAssertEqual(requests, [
            "preview|/tmp/repo|2,1|finance|true",
            "apply|/tmp/repo|2,1|finance|true|preview-current"
        ])
        XCTAssertEqual(previewState.report, preview)
        XCTAssertEqual(apply.report, report)
        XCTAssertEqual(undoState, .ready(.batchChangeCategoryAction))
        XCTAssertEqual(createdCategories, ["finance", "tax"])
        XCTAssertEqual(MainSearchDestination.classifierRuleEditor(context: nil).pageID, "classifier-rule-editor")
    }

    @MainActor
    func testBatchChangeCategoryBatchChangeCategoryCorePreviewFailureKeepsApplyClosedAndDoesNotExpandDetails() async {
        let changer = BatchChangeCategoryRecordingBatchCategoryChanger(results: [
            .preview(.failure(CoreError.PermissionDenied(path: "/tmp/repo/finance")))
        ])
        let previewState = await BatchChangeCategoryAction.preview(
            request: BatchChangeCategoryPreviewRequest(
                repoPath: "/tmp/repo",
                fileIDs: [1, 2],
                targetCategory: "finance",
                moveRepoOwnedFiles: true
            ),
            changer: changer,
            errorMapper: BatchChangeCategoryErrorMapper()
        )
        let requests = await changer.recordedRequests()

        XCTAssertEqual(requests, ["preview|/tmp/repo|1,2|finance|true"])
        XCTAssertEqual(previewState.failure?.kind, .permissionDenied)
        XCTAssertNil(previewState.report)
        XCTAssertFalse(BatchChangeCategoryPreviewDisclosure.shouldShowDetails(
            after: previewState,
            expandDetails: true
        ))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(BatchChangeCategoryApplyGate(
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: previewState.report,
            disabledReason: nil,
            isApplying: false
        )))
    }

    func testBatchChangeCategoryBatchChangeCategoryCoreApplyRequiresLatestUnblockedDryRunAndPartialFailureRefresh() {
        let preview = BatchCategoryPreviewReportSnapshot.batchChangeCategoryPreview()
        let partial = BatchCategoryChangeReportSnapshot.batchChangeCategoryPartialFailureReport()
        var blockedPreview = preview
        blockedPreview.canApply = false

        XCTAssertTrue(BatchChangeCategoryValidation.canApply(BatchChangeCategoryApplyGate(
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: preview,
            disabledReason: nil,
            isApplying: false
        )))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(BatchChangeCategoryApplyGate(
            targetCategory: "archive",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: preview,
            disabledReason: nil,
            isApplying: false
        )))
        XCTAssertFalse(BatchChangeCategoryValidation.canApply(BatchChangeCategoryApplyGate(
            targetCategory: "finance",
            moveRepoOwnedFiles: true,
            fileIDs: [1, 2],
            preview: blockedPreview,
            disabledReason: nil,
            isApplying: false
        )))
        XCTAssertTrue(partial.shouldRefreshConsumerAfterApply)
        XCTAssertFalse(partial.shouldCloseSheetAfterApply)
        XCTAssertFalse(BatchCategoryChangeReportSnapshot.batchChangeCategoryAllFailedReport().shouldRefreshConsumerAfterApply)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testImportBatchPreviewErrorAndPartialSuccessSurfaceFailedItemInResultSummary() async {
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
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        model.applyPreviewRows(
            rows,
            request: importBatchResultSummaryRequest(urls: [readyURL, failedPreviewURL]),
            selectedDestination: .autoClassify
        )
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
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
            pending: 0,
            items: [
                ImportBatchProgressSnapshot.Item(
                    fileID: 42,
                    sourcePath: "/tmp/source.pdf",
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .done,
                    errorMessage: nil
                )
            ]
        ))
    }

    @MainActor
    func testImportBatchSkippedDuplicateAndPendingICloudSurfaceInProgressResultSummary() async {
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
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        model.applyPreviewRows(
            rows,
            request: importBatchResultSummaryRequest(urls: [duplicateURL, cloudURL]),
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

private func importBatchResultSummaryRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "finance"]
    )
}

private actor BatchChangeCategoryRecordingUndoStore: CoreUndoActionLogging {
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

private extension UndoActionRecordSnapshot {
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

private extension FileEntrySnapshot {
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

private extension BatchCategoryPreviewReportSnapshot {
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

private extension BatchCategoryPreviewItemSnapshot {
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

private extension BatchCategoryChangeReportSnapshot {
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

private extension BatchCategoryChangeItemResultSnapshot {
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

private actor BatchChangeCategoryRecordingBatchCategoryChanger: CoreBatchCategoryChanging {
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

private actor BatchChangeCategoryErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind(for: error),
            userMessage: "Batch category update failed",
            severity: .medium,
            suggestedAction: "Review failed items and refresh the preview.",
            recoverability: .refreshRequired,
            rawContext: "batch-change-category batch-change-category-core batch-change-category"
        )
    }

    private func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        switch error {
        case .Conflict: .conflict
        case .FileNotFound: .fileNotFound
        case .PermissionDenied: .permissionDenied
        case .Db: .db
        case .Io: .io
        default:
            .internal
        }
    }
}
