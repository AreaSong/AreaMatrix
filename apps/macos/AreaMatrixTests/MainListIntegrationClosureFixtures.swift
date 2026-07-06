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
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryTreeNodeSnapshot {
    static func integrationClosureFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(children: [.testCategory("docs", fileCount: 2)])
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
        FileEntrySnapshot.testFixture(
            id: id,
            path: path,
            currentName: currentName,
            category: category
        ) {
            $0.hashSha256 = "integration-closure-\(id)"
            $0.storageMode = storageMode
            $0.availability = availability
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func integrationClosureDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "db locked"
        )
    }
}
