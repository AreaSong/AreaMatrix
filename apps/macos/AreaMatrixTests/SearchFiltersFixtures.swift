@testable import AreaMatrix

struct MainListSearchFacetRequestRecord: Equatable {
    var repoPath: String
    var request: SearchFacetRequestSnapshot
}

actor MainListRecordingSearchFiltering: CoreSearchFiltering {
    private var results: [Swift.Result<SearchFacetsSnapshot, Error>]
    private var requests: [MainListSearchFacetRequestRecord] = []

    init(results: [Swift.Result<SearchFacetsSnapshot, Error>]) {
        self.results = results
    }

    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot {
        requests.append(MainListSearchFacetRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else {
            return .searchFiltersFixture(active: request.filters.activeFilterCount)
        }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [MainListSearchFacetRequestRecord] {
        requests
    }
}

extension RepositoryOpeningResult {
    static func searchFiltersFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .searchFiltersFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepoConfigSnapshot {
    static func searchFiltersFixture(repoPath: String) -> RepoConfigSnapshot {
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

extension SearchResultPageSnapshot {
    static func searchFiltersSearchFixture(query: String) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func searchFiltersFixtureTree() -> RepositoryTreeNodeSnapshot {
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
                    fileCount: 0,
                    children: [
                        RepositoryTreeNodeSnapshot(
                            slug: "contracts",
                            displayName: "contracts",
                            kind: "Subdir",
                            relativePath: "docs/contracts",
                            fileCount: 2,
                            depth: 2,
                            children: []
                        )
                    ]
                )
            ]
        )
    }
}

extension SearchFacetsSnapshot {
    static func searchFiltersFixture(active: Int64) -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: "合同",
            totalCount: 7,
            categories: [],
            fileKinds: [],
            tags: [],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: active
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func searchFiltersDbFixture() -> CoreErrorMappingSnapshot {
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
