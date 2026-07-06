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
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryTreeNodeSnapshot {
    static func queryErrorFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(
            children: [
                .testCategory(
                    "docs",
                    children: [.testSubdirectory("contracts", relativePath: "docs/contracts", fileCount: 1)]
                )
            ]
        )
    }
}

extension SearchQueryDiagnosticSnapshot {
    static func testFixture(
        kindDisplayName: String = "unknown",
        severityDisplayName: String = "Error",
        message: String = "Unknown field: owner",
        token: String? = nil,
        start: Int64? = nil,
        end: Int64? = nil,
        suggestion: String? = "Use category:"
    ) -> SearchQueryDiagnosticSnapshot {
        SearchQueryDiagnosticSnapshot(
            kindDisplayName: kindDisplayName,
            severityDisplayName: severityDisplayName,
            message: message,
            token: token,
            start: start,
            end: end,
            suggestion: suggestion
        )
    }

    static func queryErrorUnknownField() -> SearchQueryDiagnosticSnapshot {
        .testFixture(
            kindDisplayName: "Unknown field",
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
        .testFixture(
            id: 77,
            name: "Finance",
            query: .testFixture(request: .queryErrorQueryFixture(query: query)),
            pinned: true,
            updatedAt: 1_700_000_100
        )
    }
}

extension SearchQueryRequestSnapshot {
    static func queryErrorQueryFixture(query: String) -> SearchQueryRequestSnapshot {
        .testFixture(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .empty
        )
    }
}

extension SearchResultPageSnapshot {
    static func queryErrorQueryErrorPage(
        query: String,
        diagnostic: SearchQueryDiagnosticSnapshot
    ) -> SearchResultPageSnapshot {
        .testFixture(
            query: query,
            diagnostics: [diagnostic]
        )
    }

    static func smartListValidQueryPage(query: String, totalCount: Int64) -> SearchResultPageSnapshot {
        .testFixture(
            query: query,
            totalCount: totalCount
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func queryErrorConfigMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .config,
            userMessage: "Query syntax is invalid.",
            severity: .medium,
            suggestedAction: "Fix the highlighted query token.",
            recoverability: .userActionRequired,
            rawContext: "query-error"
        )
    }
}
