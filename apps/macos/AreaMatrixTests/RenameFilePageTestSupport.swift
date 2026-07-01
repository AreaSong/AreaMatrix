@testable import AreaMatrix
import Foundation

struct RenameRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var newName: String
}

actor RenameRecordingRenamer: CoreFileRenaming {
    private let result: Result<FileEntrySnapshot, Error>
    private var requests: [RenameRequest] = []

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        requests.append(RenameRequest(repoPath: repoPath, fileID: fileID, newName: newName))
        return try result.get()
    }

    func recordedRequests() -> [RenameRequest] {
        requests
    }
}

extension BatchRenameValidation {
    static func batchRenameUndoCanApply(
        fileIDs: [Int64],
        preview: BatchRenamePreviewReportSnapshot?,
        rule: BatchRenameRuleSnapshot,
        disabledReason: String? = nil,
        isApplying: Bool = false
    ) -> Bool {
        canApply(
            fileIDs: fileIDs,
            preview: preview,
            rule: rule,
            disabledReason: disabledReason,
            isApplying: isApplying
        )
    }
}

extension BatchRenameAction {
    static func batchRenameUndoPreview(
        rule: BatchRenameRuleSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenamePreviewState {
        await preview(repoPath: "/repo", fileIDs: [11, 12], rule: rule, renamer: renamer, errorMapper: errorMapper)
    }

    static func batchRenameUndoApply(
        preview: BatchRenamePreviewReportSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenameApplyResult {
        await apply(repoPath: "/repo", fileIDs: [11, 12], preview: preview, renamer: renamer, errorMapper: errorMapper)
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
    private(set) var previewRequests: [BatchRenamePreviewRequest] = []
    private(set) var applyRequests: [BatchRenameApplyRequest] = []

    init(preview: Result<BatchRenamePreviewReportSnapshot, Error>, apply: Result<BatchRenameReportSnapshot, Error>) {
        previewResult = preview
        applyResult = apply
    }

    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot {
        previewRequests.append(BatchRenamePreviewRequest(repoPath: repoPath, fileIDs: fileIDs, rule: rule))
        return try previewResult.get()
    }

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot {
        applyRequests.append(BatchRenameApplyRequest(
            repoPath: repoPath,
            fileIDs: fileIDs,
            rule: rule,
            token: previewToken
        ))
        return try applyResult.get()
    }
}

func makeRenameTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRenameFile")
}
