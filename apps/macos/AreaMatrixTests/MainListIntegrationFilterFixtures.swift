@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func integrationFilterFixture(
        repoPath: String,
        currentCategoryFiles: [FileEntrySnapshot]
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .integrationFilterFixture(repoPath: repoPath),
            tree: .integrationFilterFixtureTree(),
            currentCategoryFiles: currentCategoryFiles
        )
    }
}

extension AppRepoConfigSnapshot {
    static func integrationFilterFixture(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryTreeNodeSnapshot {
    static func integrationFilterFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(
            children: [
                .testCategory(
                    "docs",
                    children: [
                        .testSubdirectory("contracts", relativePath: "docs/contracts", fileCount: 2),
                        .testSubdirectory("references", relativePath: "docs/references", fileCount: 1)
                    ]
                )
            ]
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func integrationFilterDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

extension SearchResultPageSnapshot {
    static func mainSearchFixture(
        query: String,
        files: [FileEntrySnapshot],
        indexStatus: SearchIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        .testFixture(
            query: query,
            results: files.map {
                .nameMatchFixture(file: $0)
            },
            indexStatus: indexStatus
        )
    }

    static func semanticSearchSemanticFallbackFixture() -> SearchResultPageSnapshot {
        .testFixture(
            query: "客户合同",
            totalCount: 0,
            indexStatus: .unavailable,
            semanticPage: SemanticSearchResultPageSnapshot.testFixture(
                query: "客户合同",
                semanticTotalCount: 0,
                normalTotalCount: 0,
                indexStatus: .notReady,
                route: .remote,
                fallbackReason: .semanticIndexNotReady,
                fallbackMessage: "Semantic index is not ready"
            )
        )
    }
}

extension AiFallbackStatus {
    static func semanticSearchSemanticIndexNotReady() -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .semanticSearch,
            kind: .semanticIndexNotReady,
            category: .unavailable,
            title: "Semantic index is not ready",
            message: "Semantic index is not ready yet.",
            retryable: false,
            retryDisabledReason: "Build the semantic index or use normal search.",
            primaryAction: .buildSemanticIndex,
            secondaryAction: .viewCallLog,
            nonAiFallbackAction: .useNormalSearch,
            route: .remote,
            callLogId: 308,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }
}

extension FileEntrySnapshot {
    static func integrationFilterFixture(
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
            $0.hashSha256 = "integration-filter-\(id)"
            $0.importedAt = 1_700_000_000 - id
            $0.updatedAt = 1_700_000_000
        }
    }
}
