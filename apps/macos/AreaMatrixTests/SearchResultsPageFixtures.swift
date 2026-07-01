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

extension SearchFilterStateSnapshot {
    static func searchResultsContractFilters() -> SearchFilterStateSnapshot {
        SearchFilterStateSnapshot(
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
}

extension SearchResultPageSnapshot {
    static func searchResultsPage(
        query: String,
        files: [FileEntrySnapshot] = [],
        diagnostics: [SearchQueryDiagnosticSnapshot] = [],
        indexStatus: SearchIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: Int64(files.count),
            results: files.map {
                SearchFileResultSnapshot(
                    file: $0,
                    score: 1,
                    matches: [
                        SearchMatchSnapshot(
                            fieldDisplayName: "Name",
                            kindDisplayName: "Exact match",
                            snippet: $0.currentName
                        )
                    ],
                    noteSnippet: nil
                )
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
        SearchFacetsSnapshot(
            query: query,
            totalCount: totalCount,
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
            activeFilterCount: activeFilters
        )
    }
}

extension FileEntrySnapshot {
    static func searchResultsFixture(
        id: Int64,
        path: String,
        category: String,
        currentName: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "search-results-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000 - id,
            updatedAt: 1_700_000_000
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func searchResultsMapping(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: .high,
            suggestedAction: "mapped action",
            recoverability: .userActionRequired,
            rawContext: "search-results"
        )
    }
}
