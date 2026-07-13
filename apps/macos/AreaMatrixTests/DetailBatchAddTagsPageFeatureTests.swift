@testable import AreaMatrix
import XCTest

final class DetailBatchAddTagsPageFeatureTests: XCTestCase {
    func testBatchAddTagsBatchAddTagsValidationNormalizesAndBlocksInvalidPendingTags() {
        let first = BatchTagValidation.pendingStateAfterAdding(
            input: " ClientA ",
            pendingTags: [],
            catalog: .batchAddTagsTagCatalogFixture(fileID: 31),
            disabledReason: nil
        )
        let catalog = TagSetSnapshot.batchAddTagsTagCatalogFixture(fileID: 31)
        let duplicate = BatchTagValidation.pendingStateAfterAdding(
            input: "clienta",
            pendingTags: first.pendingTags,
            catalog: catalog,
            disabledReason: nil
        )
        let invalid = BatchTagValidation.pendingStateAfterAdding(
            input: "bad/tag",
            pendingTags: first.pendingTags,
            catalog: catalog,
            disabledReason: nil
        )
        let blocked = BatchTagValidation.pendingStateAfterAdding(
            input: "blocked",
            pendingTags: [],
            catalog: catalog,
            disabledReason: nil
        )
        let reserved = BatchTagValidation.pendingStateAfterAdding(
            input: ".areamatrix",
            pendingTags: [],
            catalog: catalog,
            disabledReason: nil
        )

        XCTAssertEqual(first, BatchTagPendingState(input: "", pendingTags: ["clienta"], fieldError: nil))
        XCTAssertEqual(duplicate.fieldError, "Tag already selected.")
        XCTAssertEqual(invalid.fieldError, "Tag name is invalid.")
        XCTAssertEqual(blocked.fieldError, "Tag store is read-only.")
        XCTAssertEqual(reserved.fieldError, "Tag name is invalid.")
        XCTAssertFalse(BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: false, disabledReason: nil, input: " unsaved ", pendingTags: first.pendingTags,
            fieldError: nil, selectedCount: 2
        )))
        XCTAssertFalse(BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: false, disabledReason: nil, input: "", pendingTags: ["clienta", "ClientA"],
            fieldError: nil, selectedCount: 2
        )))
        XCTAssertEqual(BatchTagValidation.normalizedTagsForApply(["bad/tag"]), .failure("Tag name is invalid."))
    }

    @MainActor
    func testBatchAddTagsBatchAddTagsLoadsCandidatesAndAppliesThroughBatchAddTagsCoreCoreTagCRUD() async {
        let store = BatchAddTagsRecordingBatchTagStore(results: [
            .tagSet(.success(.batchAddTagsTagCatalogFixture(fileID: 31))),
            .batchAdd(.success(.batchAddTagsFixture()))
        ])
        let catalog = await BatchTagCatalogAction.load(
            repoPath: "/tmp/repo",
            fileIDs: [31, 32],
            tagStore: store,
            errorMapper: StaticCoreErrorMapper(mapping: .batchAddTagsTagDb())
        )
        let candidates = BatchTagValidation.visibleCandidates(
            input: "",
            catalog: catalog.tagSet,
            pendingTags: ["urgent"]
        )
        let result = await BatchAddTagsAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [32, 31],
            tags: ["urgent", "clienta"],
            tagStore: store,
            errorMapper: StaticCoreErrorMapper(mapping: .batchAddTagsTagDb())
        )

        await store.assertBatchAddTagsCatalogRequests(["31"])
        XCTAssertEqual(candidates.map(\.value), ["urgent", "clienta"])
        XCTAssertTrue(candidates.first { $0.value == "urgent" }?.selected == true)
        await store.assertBatchAddTagsApplyRequests(["/tmp/repo|32,31|urgent,clienta"])
        XCTAssertEqual(result.report?.addedCount, 3)
        XCTAssertEqual(result.report?.skippedCount, 1)
        XCTAssertEqual(result.report?.undoToken, "undo-batch-tags")
        XCTAssertNil(result.failure)
        guard let report = result.report else {
            return XCTFail("Expected batch-add-tags-core batch_add_tags report")
        }
        let presentation = BatchMutationReportPresentation(report: report)
        XCTAssertEqual(presentation.addedSummaryText, "Added to 2 files (3 tag relations)")
        XCTAssertEqual(presentation.skippedSummaryText, "1 file already had these tags")
        XCTAssertEqual(presentation.failedSummaryText, "0 failed")
    }

    func testBatchAddTagsBatchAddTagsValidationBlocksReadOnlyAndDuplicatePendingTags() {
        let readOnly = BatchTagValidation.pendingStateAfterAdding(
            input: "urgent",
            pendingTags: [],
            catalog: .batchAddTagsTagCatalogFixture(fileID: 31),
            disabledReason: MainFileWriteActionDisabledReason.repoReadOnly.message
        )
        let chips = BatchTagValidation.pendingChips(
            pendingTags: ["urgent", "urgent"],
            disabledReason: nil
        )

        XCTAssertEqual(readOnly.fieldError, "Tag store is read-only.")
        XCTAssertEqual(chips.map(\.status), [.ready, .alreadySelected])
        XCTAssertFalse(BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: false, disabledReason: MainFileWriteActionDisabledReason.repoReadOnly.message,
            input: "", pendingTags: ["urgent"], fieldError: nil, selectedCount: 2
        )))
        let duplicateApply = BatchTagValidation.normalizedTagsForApply(["urgent", "urgent"])
        XCTAssertEqual(duplicateApply, .failure("Tag already selected."))
    }

    @MainActor
    func testBatchAddTagsBatchAddTagsMapsBatchAddTagsCoreFailureWithoutMockingSuccess() async {
        let mapping = CoreErrorMappingSnapshot.batchAddTagsTagDb()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let store = BatchAddTagsRecordingBatchTagStore(results: [
            .batchAdd(.failure(CoreError.Db(message: "tag metadata locked")))
        ])
        let result = await BatchAddTagsAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [31, 32],
            tags: ["urgent"],
            tagStore: store,
            errorMapper: mapper
        )

        await store.assertBatchAddTagsApplyRequests(["/tmp/repo|31,32|urgent"])
        XCTAssertNil(result.report)
        XCTAssertEqual(result.failure, mapping)
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "tag metadata locked")])
    }
}
