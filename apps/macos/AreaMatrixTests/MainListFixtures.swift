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

extension AppRepoConfigSnapshot {
    static func mainListFixture(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryTreeNodeSnapshot {
    static func mainListFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(
            displayName: "资料库",
            children: [
                .testCategory("inbox", fileCount: 1),
                .testCategory("docs", fileCount: 42)
            ]
        )
    }

    static func mainListNestedFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(
            displayName: "资料库",
            children: [
                .testCategory("inbox", fileCount: 1),
                .testCategory(
                    "docs",
                    children: [
                        .testSubdirectory("contracts", relativePath: "docs/contracts", fileCount: 1),
                        .testSubdirectory("references", relativePath: "docs/references", fileCount: 1)
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
        FileEntrySnapshot.testFixture(
            id: id,
            path: path,
            currentName: currentName,
            category: category
        ) {
            $0.hashSha256 = "fixture-hash-\(id)"
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func mainListDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            rawContext: rawContext
        )
    }

    static func mainListFileNotFoundFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: rawContext
        )
    }
}
