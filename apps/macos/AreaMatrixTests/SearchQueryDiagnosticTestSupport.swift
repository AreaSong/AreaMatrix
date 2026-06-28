@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func queryErrorOpening(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .queryErrorConfig(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepoConfigSnapshot {
    static func queryErrorConfig(repoPath: String) -> RepoConfigSnapshot {
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
    static func queryErrorFixtureTree() -> RepositoryTreeNodeSnapshot {
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

extension SearchQueryDiagnosticSnapshot {
    static func queryErrorUnknownField() -> SearchQueryDiagnosticSnapshot {
        SearchQueryDiagnosticSnapshot(
            kindDisplayName: "Unknown field",
            severityDisplayName: "Error",
            message: "Unknown field `kindd`",
            token: "kindd",
            start: 0,
            end: 5,
            suggestion: "kind"
        )
    }
}

extension SavedSearchSnapshot {
    static func smartListFixture(query: String) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: 77,
            name: "Finance",
            query: SavedSearchQuerySnapshot(request: .queryErrorQueryFixture(query: query)),
            icon: "magnifyingglass",
            color: nil,
            pinned: true,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension SearchQueryRequestSnapshot {
    static func queryErrorQueryFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .empty,
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

extension SearchResultPageSnapshot {
    static func queryErrorQueryErrorPage(
        query: String,
        diagnostic: SearchQueryDiagnosticSnapshot
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: 0,
            results: [],
            diagnostics: [diagnostic],
            indexStatus: .ready
        )
    }

    static func smartListValidQueryPage(query: String, totalCount: Int64) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: totalCount,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func queryErrorConfigMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Query syntax is invalid.",
            severity: .medium,
            suggestedAction: "Fix the highlighted query token.",
            recoverability: .userActionRequired,
            rawContext: "query-error"
        )
    }
}

struct SmartListSmartListRunRequest: Equatable {
    var repoPath: String
    var savedSearchID: Int64
    var limit: Int64
    var offset: Int64
}

actor SmartListRecordingSmartListRunner: CoreSearchQuerying {
    enum Result {
        case success(SearchResultPageSnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var runRequests: [SmartListSmartListRunRequest] = []
    private var searchRequests: [SearchQueryRequestSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        searchRequests.append(request)
        throw CoreError
            .Internal(message: "search_files must not run smart-list-management smart-list Smart List execution")
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        runRequests.append(SmartListSmartListRunRequest(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ))
        guard !results.isEmpty else {
            return SearchResultPageSnapshot(
                query: "",
                totalCount: 0,
                results: [],
                diagnostics: [],
                indexStatus: .ready
            )
        }
        switch results.removeFirst() {
        case let .success(page):
            return page
        case let .failure(error):
            throw error
        }
    }

    func recordedRunRequests() -> [SmartListSmartListRunRequest] {
        runRequests
    }

    func recordedSearchRequests() -> [SearchQueryRequestSnapshot] {
        searchRequests
    }
}
