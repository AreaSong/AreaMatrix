@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func integrationClosureFixture(
        repoPath: String,
        files: [FileEntrySnapshot],
        isReadOnly: Bool = false,
        writeLockedFileIDs: Set<Int64> = []
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .integrationClosureFixture(repoPath: repoPath),
            tree: .integrationClosureFixtureTree(),
            currentCategoryFiles: files,
            isReadOnly: isReadOnly,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }
}

extension RepoConfigSnapshot {
    static func integrationClosureFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func integrationClosureFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 2,
                    children: []
                )
            ]
        )
    }
}

extension FileEntrySnapshot {
    static func integrationClosureFixture(
        id: Int64,
        path: String = "docs/contracts/a.pdf",
        category: String = "docs",
        currentName: String,
        storageMode: String = "Copied",
        availability: FileAvailabilitySnapshot = .available
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "integration-closure-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100,
            availability: availability
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func integrationClosureDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "db locked"
        )
    }
}
