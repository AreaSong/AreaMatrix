@testable import AreaMatrix

extension SearchQueryRequestSnapshot {
    static func mainRepoSearchResultsRouteFixture(query: String) -> SearchQueryRequestSnapshot {
        .testFixture(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .mainRepoSearchResultsRouteFilters
        )
    }
}

extension RepositoryOpeningResult {
    static func mainRepoSearchFiltersFixture(
        repoPath: String,
        tree: RepositoryTreeNodeSnapshot
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func mainRepoSearchFiltersFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot()
    }
}

extension SearchFilterStateSnapshot {
    static func mainRepoSearchFiltersFixture(tag: String = "finance") -> SearchFilterStateSnapshot {
        .testFixture(
            category: "docs",
            fileKind: "pdf",
            tags: [tag],
            tagMatchMode: .all,
            modifiedAfter: 1_700_000_000,
            storageMode: .copied,
            includeDeleted: true
        )
    }

    static let mainRepoSearchResultsRouteFilters = SearchFilterStateSnapshot.testFixture(
        category: "docs",
        fileKind: "pdf",
        tags: ["contract"],
        storageMode: .copied
    )
}

extension CoreErrorMappingSnapshot {
    static func mainRepoSearchFiltersDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "过滤器不可用",
            severity: .high,
            suggestedAction: "请重试过滤器。",
            recoverability: .retryable,
            rawContext: "facet db locked"
        )
    }
}
