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
            .success(.batchAddTagsFixture())
        ])
        let catalog = await BatchTagCatalogAction.load(
            repoPath: "/tmp/repo",
            fileIDs: [31, 32],
            tagStore: store,
            errorMapper: DetailMetaErrorMapper(mapping: .batchAddTagsTagDb())
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
            errorMapper: DetailMetaErrorMapper(mapping: .batchAddTagsTagDb())
        )
        let requests = await store.batchRequests()
        let listRequests = await store.listRequests()

        XCTAssertEqual(listRequests, ["31"])
        XCTAssertEqual(candidates.map(\.value), ["urgent", "clienta"])
        XCTAssertTrue(candidates.first { $0.value == "urgent" }?.selected == true)
        XCTAssertEqual(requests, ["/tmp/repo|32,31|urgent,clienta"])
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
            disabledReason: MainFileWriteActionDisabledReason.repoReadOnly.rawValue
        )
        let chips = BatchTagValidation.pendingChips(
            pendingTags: ["urgent", "urgent"],
            disabledReason: nil
        )

        XCTAssertEqual(readOnly.fieldError, "Tag store is read-only.")
        XCTAssertEqual(chips.map(\.status), [.ready, .alreadySelected])
        XCTAssertFalse(BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: false, disabledReason: MainFileWriteActionDisabledReason.repoReadOnly.rawValue,
            input: "", pendingTags: ["urgent"], fieldError: nil, selectedCount: 2
        )))
        let duplicateApply = BatchTagValidation.normalizedTagsForApply(["urgent", "urgent"])
        XCTAssertEqual(duplicateApply, .failure("Tag already selected."))
    }

    @MainActor
    func testBatchAddTagsBatchAddTagsMapsBatchAddTagsCoreFailureWithoutMockingSuccess() async {
        let mapping = CoreErrorMappingSnapshot.batchAddTagsTagDb()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let store = BatchAddTagsRecordingBatchTagStore(results: [
            .failure(CoreError.Db(message: "tag metadata locked"))
        ])
        let result = await BatchAddTagsAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [31, 32],
            tags: ["urgent"],
            tagStore: store,
            errorMapper: mapper
        )
        let requests = await store.batchRequests()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(requests, ["/tmp/repo|31,32|urgent"])
        XCTAssertNil(result.report)
        XCTAssertEqual(result.failure, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "tag metadata locked")])
    }
}

private actor BatchAddTagsRecordingBatchTagStore: CoreTagCRUD {
    enum Result {
        case tagSet(Swift.Result<TagSetSnapshot, Error>)
        case success(BatchMutationReportSnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedBatchRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listTags(repoPath _: String, fileID: Int64) async throws -> TagSetSnapshot {
        recordedListRequests.append("\(fileID)")
        guard !results.isEmpty else {
            throw CoreError.Db(message: "missing list_tags result")
        }

        guard case let .tagSet(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "expected list_tags result before batch_add_tags")
        }
        return try result.get()
    }

    func addTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        throw CoreError.Internal(message: "batch-add-tags batch-add-tags-core must use batch_add_tags")
    }

    func removeTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        throw CoreError.Internal(message: "batch-add-tags batch-add-tags-core must not remove tags")
    }

    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot {
        let ids = fileIDs.map(String.init).joined(separator: ",")
        recordedBatchRequests.append("\(repoPath)|\(ids)|\(tags.joined(separator: ","))")
        guard !results.isEmpty else {
            throw CoreError.Db(message: "missing batch_add_tags result")
        }

        switch results.removeFirst() {
        case .tagSet:
            throw CoreError.Internal(message: "expected batch_add_tags result after list_tags")
        case let .success(report):
            return report
        case let .failure(error):
            throw error
        }
    }

    func batchRequests() -> [String] {
        recordedBatchRequests
    }

    func listRequests() -> [String] {
        recordedListRequests
    }
}
