@testable import AreaMatrix
import Foundation

extension RepositoryOpeningResult {
    static func detailMultiFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "Repository",
                fileCount: Int64(files.count),
                children: []
            ),
            currentCategoryFiles: files
        )
    }

    static func detailMultiSelectFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .detailMultiSelectFixture(repoPath: repoPath),
            tree: .detailMultiSelectTreeFixture(fileCount: Int64(files.count)),
            currentCategoryFiles: files
        )
    }
}

extension RepoConfigSnapshot {
    static func detailMultiSelectFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func detailMultiSelectTreeFixture(fileCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            fileCount: fileCount,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: fileCount, children: [])
            ]
        )
    }
}

extension FileEntrySnapshot {
    static func detailMultiFixture(
        id: Int64,
        currentName: String,
        sizeBytes: Int64 = 256,
        storageMode: String = "Copied",
        importedAt: Int64 = 1_700_000_000,
        availability: FileAvailabilitySnapshot = .available
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: sizeBytes,
            hashSha256: "detail-multi-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: importedAt,
            updatedAt: importedAt,
            availability: availability
        )
    }

    static func detailMultiSelectFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "detailMultiSelect-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func detailMultiFileNotFound() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "部分选中项无法读取元数据",
            severity: .medium,
            suggestedAction: "刷新当前选择，确认文件是否仍在资料库中。",
            recoverability: .refreshRequired,
            rawContext: "file-list file-detail-core get_file"
        )
    }

    static func batchAddTagsUndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "无法撤销批量标签操作",
            severity: .medium,
            suggestedAction: "打开 Undo 历史查看阻塞原因。",
            recoverability: .refreshRequired,
            rawContext: "batch-add-tags undo-action-log undo_action"
        )
    }

    static func detailMultiSelectDbMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "file-list list-files list_files"
        )
    }

    static func detailMultiSelectFileNotFoundMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "部分选中项无法读取元数据",
            severity: .medium,
            suggestedAction: "刷新当前选择，确认文件是否仍在资料库中。",
            recoverability: .refreshRequired,
            rawContext: "file-list file-detail-core get_file"
        )
    }
}

extension UndoActionRecordSnapshot {
    static func batchAddTagsPendingBatchAddTags() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-action-log",
            kind: "batch_add_tags",
            summary: "Added urgent to 2 files.",
            affectedCount: 3,
            affectedFileNames: ["contract.pdf", "notes.md"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }

    static func batchAddTagsExecutedActionLogRow() -> UndoActionRecordSnapshot {
        var action = batchAddTagsPendingBatchAddTags()
        action.status = .executed
        action.canUndo = false
        action.updatedAt = 1_700_000_420
        return action
    }
}

extension UndoActionResultSnapshot {
    static func batchAddTagsExecutedBatchAddTags() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-action-log",
            status: .executed,
            summary: "Undone: added urgent to 2 files.",
            affectedCount: 3,
            refreshTargets: ["tags", "change_log", "undo_actions"],
            completedAt: 1_700_000_420
        )
    }
}

extension BatchMutationReportSnapshot {
    static func batchAddTagsBatchAddTagsReport() -> BatchMutationReportSnapshot {
        BatchMutationReportSnapshot(
            requestedFileCount: 2,
            requestedTagCount: 1,
            addedCount: 2,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                BatchMutationItemResultSnapshot(fileID: 1, tag: "urgent", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 2, tag: "urgent", status: .added, error: nil)
            ],
            undoToken: "undo-action-log"
        )
    }
}
