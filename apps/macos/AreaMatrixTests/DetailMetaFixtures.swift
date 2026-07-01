@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func detailMetaFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
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
}

extension FileEntrySnapshot {
    static func detailMetaFixture(
        id: Int64,
        currentName: String,
        storageMode: String = "Copied",
        sourcePath: String? = "~/Downloads/source.pdf"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "detail-meta-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: sourcePath,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension ChangeLogEntrySnapshot {
    static func detailLogFixture(fileID: Int64, action: String) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: fileID + 100,
            fileID: fileID,
            filename: "logged.pdf",
            category: "docs",
            action: action,
            detailJSON: #"{"changed":"modified_at"}"#,
            occurredAt: 1_700_000_200
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func detailMetaFileNotFound() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: "file-detail file-detail-core get_file"
        )
    }

    static func detailLogDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法加载改动记录",
            severity: .medium,
            suggestedAction: "请重试改动时间线。",
            recoverability: .retryable,
            rawContext: "detail-change-log change-log-core list_changes"
        )
    }
}
