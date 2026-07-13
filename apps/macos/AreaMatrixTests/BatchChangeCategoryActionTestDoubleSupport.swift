@testable import AreaMatrix
import XCTest

typealias BatchChangeCategoryRecordingUndoStore = LenientUndoActionRecordingTestStore

enum BatchCategoryActionCall: Equatable {
    case preview(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    )
    case apply(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        previewToken: String
    )
}

func batchCategoryPreviewCall(
    fileIDs: [Int64],
    targetCategory: String = "finance",
    moveRepoOwnedFiles: Bool = true
) -> BatchCategoryActionCall {
    .preview(
        repoPath: batchChangeCategoryRepoPath(),
        fileIDs: fileIDs,
        targetCategory: targetCategory,
        moveRepoOwnedFiles: moveRepoOwnedFiles
    )
}

func batchCategoryApplyCall(
    fileIDs: [Int64],
    targetCategory: String = "finance",
    moveRepoOwnedFiles: Bool = true,
    previewToken: String
) -> BatchCategoryActionCall {
    .apply(
        repoPath: batchChangeCategoryRepoPath(),
        fileIDs: fileIDs,
        targetCategory: targetCategory,
        moveRepoOwnedFiles: moveRepoOwnedFiles,
        previewToken: previewToken
    )
}

actor BatchCategoryChanger: CoreBatchCategoryChanging {
    enum Step {
        case preview(Swift.Result<BatchCategoryPreviewReportSnapshot, Error>)
        case apply(Swift.Result<BatchCategoryChangeReportSnapshot, Error>)
    }

    private var stepQueue: TestStepQueue<Step>
    private var calls: [BatchCategoryActionCall] = []

    init(results: [Step]) {
        stepQueue = TestStepQueue(steps: results) {
            throw CoreError.Internal(message: "Expected batch category action step")
        }
    }

    func previewBatchMoveToCategory(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    ) async throws -> BatchCategoryPreviewReportSnapshot {
        calls.append(.preview(
            repoPath: repoPath,
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles
        ))
        let step = try stepQueue.next {
            throw CoreError.Internal(message: "Expected preview_batch_move_to_category")
        }
        guard case let .preview(result) = step else {
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
        calls.append(.apply(
            repoPath: repoPath,
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles,
            previewToken: previewToken
        ))
        let step = try stepQueue.next {
            throw CoreError.Internal(message: "Expected batch_move_to_category")
        }
        guard case let .apply(result) = step else {
            throw CoreError.Internal(message: "Expected batch_move_to_category")
        }
        return try result.get()
    }

    func assertCategoryChangeActions(
        _ expectedCalls: [BatchCategoryActionCall],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calls, expectedCalls, file: file, line: line)
    }
}
