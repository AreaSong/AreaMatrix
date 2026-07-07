@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func detailMetaFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: repoPath),
            tree: .testRoot(fileCount: Int64(files.count)),
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
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/contracts/\(currentName)",
            currentName: currentName,
            category: "docs"
        ) {
            $0.sizeBytes = 256
            $0.hashSha256 = "detail-meta-\(id)"
            $0.storageMode = storageMode
            $0.sourcePath = sourcePath
        }
    }
}

extension ChangeLogEntrySnapshot {
    static func detailLogFixture(fileID: Int64, action: String) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot.testFixture(
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
        CoreErrorMappingSnapshot.testFixture(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: "file-detail file-detail-core get_file"
        )
    }

    static func detailLogDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "无法加载改动记录",
            severity: .medium,
            suggestedAction: "请重试改动时间线。",
            recoverability: .retryable,
            rawContext: "detail-change-log change-log-core list_changes"
        )
    }
}
