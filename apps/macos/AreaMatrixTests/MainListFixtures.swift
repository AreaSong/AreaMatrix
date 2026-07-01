@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func mainListFixture(
        repoPath: String,
        currentCategoryFiles: [FileEntrySnapshot]
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainListFixture(repoPath: repoPath),
            tree: .mainListFixtureTree(),
            currentCategoryFiles: currentCategoryFiles
        )
    }
}

extension RepoConfigSnapshot {
    static func mainListFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func mainListFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "资料库",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "inbox",
                    displayName: "inbox",
                    fileCount: 1,
                    children: []
                ),
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 42,
                    children: []
                )
            ]
        )
    }

    static func mainListNestedFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "资料库",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "inbox",
                    displayName: "inbox",
                    fileCount: 1,
                    children: []
                ),
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 0,
                    children: [
                        RepositoryTreeNodeSnapshot(
                            slug: "contracts",
                            displayName: "contracts",
                            kind: "Subdir",
                            relativePath: "docs/contracts",
                            fileCount: 1,
                            depth: 2,
                            children: []
                        ),
                        RepositoryTreeNodeSnapshot(
                            slug: "references",
                            displayName: "references",
                            kind: "Subdir",
                            relativePath: "docs/references",
                            fileCount: 1,
                            depth: 2,
                            children: []
                        )
                    ]
                )
            ]
        )
    }
}

extension FileEntrySnapshot {
    static func mainListFixture(
        id: Int64,
        path: String,
        category: String,
        currentName: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "fixture-hash-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func mainListDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func mainListFileNotFoundFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: rawContext
        )
    }
}
