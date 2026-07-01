@testable import AreaMatrix
import XCTest

final class ImportBatchResultSummaryTests: XCTestCase {
    @MainActor
    func testBatchChangeCategoryBatchChangeCategoryCorePreviewApplyUndoAndRouteStayWithinControlMap() async {
        let preview = BatchCategoryPreviewReportSnapshot.batchChangeCategoryPreview()
        let report = BatchCategoryChangeReportSnapshot.batchChangeCategorySuccessReport()
        let changer = BatchCategoryChanger(results: [
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
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
        )
        let apply = await BatchChangeCategoryAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [2, 1],
            preview: preview,
            changer: changer,
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
        )
        let undoState = await BatchChangeCategoryUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: report,
            failure: nil,
            undoStore: BatchChangeCategoryRecordingUndoStore(actions: [.batchChangeCategoryAction]),
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
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
        let changer = BatchCategoryChanger(results: [
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
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
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
        XCTAssertFalse(BatchCategoryChangeReportSnapshot.batchChangeCategoryAllFailedReport()
            .shouldRefreshConsumerAfterApply)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testImportBatchPreviewErrorAndPartialSuccessSurfaceFailedItemInResultSummary() async {
        let readyURL = importBatchInvoiceURL()
        let failedPreviewURL = URL(fileURLWithPath: "/tmp/unreadable.mov")
        let rows = [
            importBatchReadyBatchRow(url: readyURL),
            ImportBatchPreviewRow.failed(
                url: failedPreviewURL,
                message: "无法读取分类预览路径：/tmp/unreadable.mov"
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = importBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
                    sourcePath: importBatchSourcePath(),
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .done,
                    errorMessage: nil
                )
            ]
        ))
    }

    @MainActor
    func testImportBatchSkippedDuplicateAndPendingICloudSurfaceInProgressResultSummary() async {
        let duplicateURL = importBatchInvoiceURL()
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let rows = [
            importBatchDuplicateInvoiceRow(url: duplicateURL),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let model = importBatchCopyImportModel()

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
