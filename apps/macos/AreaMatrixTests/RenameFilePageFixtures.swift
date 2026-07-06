@testable import AreaMatrix

extension FileEntrySnapshot {
    static func renameFixture(id: Int64, name: String, updatedAt: Int64 = 1_700_000_100) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/contracts/\(name)",
            currentName: name,
            category: "docs"
        ) {
            $0.originalName = "old.pdf"
            $0.sizeBytes = 512
            $0.hashSha256 = "rename-\(id)"
            $0.updatedAt = updatedAt
        }
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
        CoreErrorMappingSnapshot.testFixture(
            kind: .conflict,
            userMessage: "A file with this name already exists.",
            suggestedAction: "Choose a different name, then retry.",
            recoverability: .userActionRequired,
            rawContext: "rename-file rename-file-core rename_file"
        )
    }

    static var batchRenameConflict: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .conflict,
            userMessage: "Could not preview rename",
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
