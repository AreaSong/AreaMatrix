@testable import AreaMatrix

extension SearchQueryRequestSnapshot {
    static func mainRepoSearchResultsRouteFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .mainRepoSearchResultsRouteFilters,
            sort: .relevance,
            limit: 50,
            offset: 0
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
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: []
        )
    }
}

extension SearchFilterStateSnapshot {
    static func mainRepoSearchFiltersFixture(tag: String = "finance") -> SearchFilterStateSnapshot {
        SearchFilterStateSnapshot(
            category: "docs",
            fileKind: "pdf",
            tags: [tag],
            tagMatchMode: .all,
            importedAfter: nil,
            importedBefore: nil,
            modifiedAfter: 1_700_000_000,
            modifiedBefore: nil,
            storageMode: .copied,
            includeDeleted: true
        )
    }

    static let mainRepoSearchResultsRouteFilters = SearchFilterStateSnapshot(
        category: "docs",
        fileKind: "pdf",
        tags: ["contract"],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: .copied,
        includeDeleted: false
    )
}

extension CoreErrorMappingSnapshot {
    static func mainRepoSearchFiltersDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "过滤器不可用",
            severity: .high,
            suggestedAction: "请重试过滤器。",
            recoverability: .retryable,
            rawContext: "facet db locked"
        )
    }
}
