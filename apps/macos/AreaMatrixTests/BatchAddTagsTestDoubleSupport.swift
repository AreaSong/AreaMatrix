@testable import AreaMatrix

actor BatchAddTagsRecordingBatchTagStore: CoreTagCRUD {
    enum Step {
        case tagSet(Swift.Result<TagSetSnapshot, Error>)
        case batchAdd(Swift.Result<BatchMutationReportSnapshot, Error>)
    }

    private var steps: TestStepQueue<Step>
    private var listRequests = TestRequestLog<String>()
    private var batchRequests = TestRequestLog<String>()

    init(results: [Step]) {
        steps = TestStepQueue(steps: results) {
            throw CoreError.Db(message: "missing batch-add-tags result")
        }
    }

    func listTags(repoPath _: String, fileID: Int64) async throws -> TagSetSnapshot {
        listRequests.append("\(fileID)")

        guard case let .tagSet(result) = try steps.next() else {
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
        batchRequests.append("\(repoPath)|\(ids)|\(tags.joined(separator: ","))")

        switch try steps.next() {
        case .tagSet:
            throw CoreError.Internal(message: "expected batch_add_tags result after list_tags")
        case let .batchAdd(result):
            return try result.get()
        }
    }

    func assertBatchAddTagsApplyRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        batchRequests.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertBatchAddTagsCatalogRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        listRequests.assertRequests(expectedRequests, file: file, line: line)
    }
}
