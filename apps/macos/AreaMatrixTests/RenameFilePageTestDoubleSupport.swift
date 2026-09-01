@testable import AreaMatrix
import AreaMatrixFeatureOperation
import XCTest

struct RenameRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var newName: String
}

actor RenameRecordingRenamer: CoreFileRenaming {
    private let result: Result<FileEntrySnapshot, Error>
    private var requestLog = TestRequestLog<RenameRequest>()

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        requestLog.append(RenameRequest(repoPath: repoPath, fileID: fileID, newName: newName))
        return try result.get()
    }

    func assertRenamedFiles(
        _ expectedRenames: [RenameRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRenames, file: file, line: line)
    }

    func assertNoRenamedFiles(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertNoRequests(file: file, line: line)
    }
}

struct BatchRenamePreviewRequest: Equatable {
    var repoPath: String
    var fileIDs: [Int64]
    var rule: BatchRenameRuleSnapshot
}

struct BatchRenameApplyRequest: Equatable {
    var repoPath: String
    var fileIDs: [Int64]
    var rule: BatchRenameRuleSnapshot
    var token: String
}

actor BatchRenameRecordingRenamer: CoreBatchRenaming {
    private let previewResult: Result<BatchRenamePreviewReportSnapshot, Error>
    private let applyResult: Result<BatchRenameReportSnapshot, Error>
    private var previewRequestLog = TestRequestLog<BatchRenamePreviewRequest>()
    private var applyRequestLog = TestRequestLog<BatchRenameApplyRequest>()

    init(preview: Result<BatchRenamePreviewReportSnapshot, Error>, apply: Result<BatchRenameReportSnapshot, Error>) {
        previewResult = preview
        applyResult = apply
    }

    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot {
        previewRequestLog.append(BatchRenamePreviewRequest(repoPath: repoPath, fileIDs: fileIDs, rule: rule))
        return try previewResult.get()
    }

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot {
        applyRequestLog.append(BatchRenameApplyRequest(
            repoPath: repoPath,
            fileIDs: fileIDs,
            rule: rule,
            token: previewToken
        ))
        return try applyResult.get()
    }

    func assertBatchRenamePreviewRequests(
        _ expectedRequests: [BatchRenamePreviewRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        previewRequestLog.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertBatchRenameApplyRequests(
        _ expectedRequests: [BatchRenameApplyRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        applyRequestLog.assertRequests(expectedRequests, file: file, line: line)
    }
}
