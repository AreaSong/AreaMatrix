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

extension FileEntrySnapshot {
    static func renameFixture(id: Int64, name: String, updatedAt: Int64 = 1_700_000_100) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(name)",
            originalName: "old.pdf",
            currentName: name,
            category: "docs",
            sizeBytes: 512,
            hashSha256: "rename-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

extension RepositoryOpeningResult {
    static func renameFixture(
        repoPath: String,
        files: [FileEntrySnapshot],
        writeLockedFileIDs: Set<Int64> = []
    ) -> RepositoryOpeningResult {
        var opening = RepositoryOpeningResult.detailMetaFixture(repoPath: repoPath, files: files)
        opening.writeLockedFileIDs = writeLockedFileIDs
        return opening
    }
}

extension CoreErrorMappingSnapshot {
    static func renameConflict() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "A file with this name already exists.",
            severity: .medium,
            suggestedAction: "Choose a different name, then retry.",
            recoverability: .userActionRequired,
            rawContext: "rename-file rename-file-core rename_file"
        )
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

actor BatchRenameErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }
}

extension CoreErrorMappingSnapshot {
    static var batchRenameConflict: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Could not preview rename",
            severity: .medium,
            suggestedAction: "Refresh preview, then retry.",
            recoverability: .refreshRequired,
            rawContext: "batch-rename batch-rename-preview batch_rename"
        )
    }
}

extension BatchRenameRuleSnapshot {
    static func batchRenameRule(
        _ mode: BatchRenameModeSnapshot,
        prefix: String? = nil,
        dateSource: BatchRenameDateSourceSnapshot? = nil,
        dateFormat: String? = nil,
        separator: String? = nil,
        startNumber: Int64? = nil,
        padding: Int64? = nil,
        find: String? = nil,
        replacement: String? = nil,
        caseSensitive: Bool = false
    ) -> BatchRenameRuleSnapshot {
        BatchRenameRuleSnapshot(
            mode: mode,
            prefix: prefix,
            dateSource: dateSource,
            dateFormat: dateFormat,
            separator: separator,
            startNumber: startNumber,
            padding: padding,
            find: find,
            replacement: replacement,
            caseSensitive: caseSensitive
        )
    }
}

extension BatchRenamePreviewReportSnapshot {
    static func preview(
        rule: BatchRenameRuleSnapshot,
        token: String,
        fileIDs: [Int64],
        canApply: Bool = true
    ) -> BatchRenamePreviewReportSnapshot {
        BatchRenamePreviewReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            rule: rule,
            previewToken: token,
            willRenameCount: Int64(fileIDs.count),
            displayOnlyCount: 0,
            unchangedCount: 0,
            blockedCount: 0,
            conflictCount: 0,
            items: fileIDs.map { .item(id: $0) },
            canApply: canApply,
            applyBlockedReason: canApply ? nil : "No filename changes."
        )
    }

    func with(canApply: Bool) -> BatchRenamePreviewReportSnapshot {
        .preview(rule: rule, token: previewToken, fileIDs: items.map(\.fileID), canApply: canApply)
    }
}

extension BatchRenamePreviewItemSnapshot {
    static func item(id: Int64) -> BatchRenamePreviewItemSnapshot {
        BatchRenamePreviewItemSnapshot(
            fileID: id,
            currentPath: "docs/\(id).pdf",
            originalName: "\(id).pdf",
            newName: "renamed-\(id).pdf",
            targetPath: "docs/renamed-\(id).pdf",
            status: .ok,
            reason: nil
        )
    }
}

extension BatchRenameReportSnapshot {
    static func report(token: String? = nil) -> BatchRenameReportSnapshot {
        BatchRenameReportSnapshot(
            requestedFileCount: 1,
            renamedCount: 1,
            displayNameUpdatedCount: 0,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [],
            updatedFiles: [],
            undoToken: token
        )
    }
}

func makeRenameTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRenameFile")
}
