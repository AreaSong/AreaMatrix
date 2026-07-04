@testable import AreaMatrix

typealias BatchChangeCategoryRecordingUndoStore = LenientUndoActionRecordingTestStore

actor BatchCategoryChanger: CoreBatchCategoryChanging {
    enum Step {
        case preview(Swift.Result<BatchCategoryPreviewReportSnapshot, Error>)
        case apply(Swift.Result<BatchCategoryChangeReportSnapshot, Error>)
    }

    private var results: [Step]
    private var requests: [String] = []

    init(results: [Step]) {
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
