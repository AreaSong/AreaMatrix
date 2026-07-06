@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func searchResultsFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func searchResultsFixtureTree() -> RepositoryTreeNodeSnapshot {
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

extension SearchFilterStateSnapshot {
    static func searchResultsContractFilters() -> SearchFilterStateSnapshot {
        .testFixture(
            category: "docs",
            fileKind: "pdf",
            tags: ["contract"],
            storageMode: .copied
        )
    }
}

extension SearchMatchSnapshot {
    static func testFixture(
        fieldDisplayName: String = "Name",
        kindDisplayName: String = "Exact match",
        snippet: String = "match"
    ) -> SearchMatchSnapshot {
        SearchMatchSnapshot(
            fieldDisplayName: fieldDisplayName,
            kindDisplayName: kindDisplayName,
            snippet: snippet
        )
    }
}

extension SearchFileResultSnapshot {
    static func testFixture(
        file: FileEntrySnapshot,
        score: Float = 1,
        matches: [SearchMatchSnapshot] = [],
        noteSnippet: String? = nil
    ) -> SearchFileResultSnapshot {
        SearchFileResultSnapshot(
            file: file,
            score: score,
            matches: matches,
            noteSnippet: noteSnippet
        )
    }

    static func nameMatchFixture(
        file: FileEntrySnapshot,
        score: Float = 1,
        kindDisplayName: String = "Exact match",
        noteSnippet: String? = nil
    ) -> SearchFileResultSnapshot {
        .testFixture(
            file: file,
            score: score,
            matches: [.testFixture(kindDisplayName: kindDisplayName, snippet: file.currentName)],
            noteSnippet: noteSnippet
        )
    }
}

extension SearchResultPageSnapshot {
    static func testFixture(
        query: String = "",
        totalCount: Int64? = nil,
        results: [SearchFileResultSnapshot] = [],
        diagnostics: [SearchQueryDiagnosticSnapshot] = [],
        indexStatus: SearchIndexStatusSnapshot = .ready,
        semanticPage: SemanticSearchResultPageSnapshot? = nil
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: totalCount ?? Int64(results.count),
            results: results,
            diagnostics: diagnostics,
            indexStatus: indexStatus,
            semanticPage: semanticPage
        )
    }

    static func searchResultsPage(
        query: String,
        files: [FileEntrySnapshot] = [],
        diagnostics: [SearchQueryDiagnosticSnapshot] = [],
        indexStatus: SearchIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        .testFixture(
            query: query,
            results: files.map {
                .nameMatchFixture(file: $0)
            },
            diagnostics: diagnostics,
            indexStatus: indexStatus
        )
    }
}

extension SearchFacetsSnapshot {
    static func searchResultsFacets(
        query: String,
        totalCount: Int64,
        activeFilters: Int64
    ) -> SearchFacetsSnapshot {
        SearchFacetsSnapshot.testFixture(query: query, totalCount: totalCount) {
            $0.activeFilterCount = activeFilters
        }
    }
}

extension FileEntrySnapshot {
    static func searchResultsFixture(
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
            $0.hashSha256 = "search-results-\(id)"
            $0.importedAt = 1_700_000_000 - id
            $0.updatedAt = 1_700_000_000
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func searchResultsMapping(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: .high,
            suggestedAction: "mapped action",
            recoverability: .userActionRequired,
            rawContext: "search-results"
        )
    }
}
