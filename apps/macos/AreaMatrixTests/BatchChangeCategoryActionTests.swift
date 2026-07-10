@testable import AreaMatrix
import XCTest

final class BatchChangeCategoryActionTests: XCTestCase {
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
                repoPath: batchChangeCategoryRepoPath(),
                fileIDs: [2, 1],
                targetCategory: "finance",
                moveRepoOwnedFiles: true
            ),
            changer: changer,
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
        )
        let apply = await BatchChangeCategoryAction.apply(
            repoPath: batchChangeCategoryRepoPath(),
            fileIDs: [2, 1],
            preview: preview,
            changer: changer,
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
        )
        let undoState = await BatchChangeCategoryUndoAction.stateAfterBatchApply(
            repoPath: batchChangeCategoryRepoPath(),
            report: report,
            failure: nil,
            undoStore: BatchChangeCategoryRecordingUndoStore(actions: [.batchChangeCategoryAction]),
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
        )
        let createdCategories = BatchChangeCategoryCreatedCategoryReturn
            .updatedCategories(["finance"], savedCategory: "tax")

        await changer.assertRecordedRequests([
            "preview|\(batchChangeCategoryRepoPath())|2,1|finance|true",
            "apply|\(batchChangeCategoryRepoPath())|2,1|finance|true|preview-current"
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
            .preview(.failure(CoreError.PermissionDenied(path: "\(batchChangeCategoryRepoPath())/finance")))
        ])
        let previewState = await BatchChangeCategoryAction.preview(
            request: BatchChangeCategoryPreviewRequest(
                repoPath: batchChangeCategoryRepoPath(),
                fileIDs: [1, 2],
                targetCategory: "finance",
                moveRepoOwnedFiles: true
            ),
            changer: changer,
            errorMapper: RecordingCoreErrorMapper.batchChangeCategory()
        )

        await changer.assertRecordedRequests(["preview|\(batchChangeCategoryRepoPath())|1,2|finance|true"])
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
}
