@testable import AreaMatrix
import XCTest

final class SearchResultsPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testSearchResultsPageIntegrationWiresSearchFiltersResultDetailAndClear() async {
        let tree = RepositoryTreeNodeSnapshot.task98FixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let resultFile = FileEntrySnapshot.task98Fixture(
            id: 298,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.task98SearchPage(query: "合同", files: [resultFile]))
        ])
        let facetLoader = MainListRecordingSearchFiltering(results: [
            .success(.task98SearchFacets(query: "合同", totalCount: 1, activeFilters: 1))
        ])
        let detailer = MainListRecordingFileDetailer(results: [.success(resultFile)])
        let filters = SearchFilterStateSnapshot.task98ContractFilters()
        let model = MainFileListModel(
            opening: .task98Fixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: detailer,
            searchQuerying: searcher,
            searchFiltering: facetLoader,
            errorMapper: StaticCoreErrorMapper(mapping: .task98Mapping(kind: .db))
        )

        await model.runSearch(query: " 合同 ", scope: .current, sort: .relevance, sidebarRow: row, filters: filters)
        await model.loadSearchFacets(query: "合同", scope: .current, sidebarRow: row, filters: filters)
        await model.selectFiles([resultFile.id])
        let searchRequests = await searcher.recordedRequests()
        let facetRequests = await facetLoader.recordedRequests()
        let detailRequests = await detailer.recordedRequests()
        model.clearSearch()

        XCTAssertEqual(searchRequests.map(\.request.filters), [filters])
        XCTAssertEqual(facetRequests.map(\.request.filters), [filters])
        XCTAssertEqual(detailRequests.map(\.fileID), [resultFile.id])
        XCTAssertEqual(model.searchState, .idle)
        XCTAssertEqual(model.searchFacetsState, .idle)
        XCTAssertEqual(model.selection, .none)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testSearchResultsPageIntegrationRoutesEmptyQueryErrorIndexingSaveAndCommandEntrances() async {
        let tree = RepositoryTreeNodeSnapshot.task98FixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let diagnostic = SearchQueryDiagnosticSnapshot(
            severityDisplayName: "Error",
            message: "Unknown field: owner",
            suggestion: "Use category:"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.task98SearchPage(query: "missing", files: [])),
            .success(.task98SearchPage(query: "owner:me", diagnostics: [diagnostic])),
            .success(.task98SearchPage(query: "")),
            .success(.task98SearchPage(query: "合同", files: [], indexStatus: .unavailable))
        ])
        let model = MainFileListModel(
            opening: .task98Fixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .task98Mapping(kind: .db))
        )

        await model.runSearch(
            query: "missing",
            scope: .current,
            sort: .newestImported,
            sidebarRow: row,
            filters: .empty
        )
        XCTAssertEqual(model.searchPageDestination?.pageID, "search-empty")
        XCTAssertEqual(model.files, [])
        let firstRecordedQuery = await searcher.recordedRequests().first?.request.query
        XCTAssertEqual(firstRecordedQuery, "missing")
        model.openSavedSearchSheet()
        XCTAssertEqual(model.pendingSearchDestination?.pageID, "saved-search")
        model.clearPendingSearchDestination()

        await model.runSearch(query: "owner:me", scope: .current, sort: .relevance, sidebarRow: row, filters: .empty)
        XCTAssertEqual(model.searchPageDestination?.pageID, "query-error")
        XCTAssertFalse(model.canSaveCurrentSearch)
        XCTAssertNil(model.searchState.errorMapping)

        await model.runSearch(
            query: "",
            scope: .current,
            sort: .newestModified,
            sidebarRow: row,
            filters: .task98ContractFilters()
        )
        XCTAssertTrue(model.canSaveCurrentSearch)

        await model.runSearch(query: "合同", scope: .current, sort: .newestImported, sidebarRow: row, filters: .empty)
        model.openIndexingStatus()
        XCTAssertEqual(model.pendingSearchDestination?.pageID, "search-index-status-indexing-status")

        model.enterSearch(context: .commandFind)
        XCTAssertEqual(model.lastSearchExitContext, .toolbar)
        model.openCommandPaletteForSearch()
        XCTAssertEqual(model.pendingSearchDestination?.pageID, "command-palette")
        XCTAssertEqual(model.lastSearchExitContext, .toolbar)
    }

    @MainActor
    func testSearchResultsPageIntegrationSmartListClearPreservesSavedQueryContext() async {
        let tree = RepositoryTreeNodeSnapshot.task98FixtureTree()
        let resultFile = FileEntrySnapshot.task98Fixture(
            id: 299,
            path: "docs/contracts/smart.pdf",
            category: "docs",
            currentName: "smart.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.task98SearchPage(query: "合同", files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .task98Fixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .task98Mapping(kind: .db))
        )
        let smartListContext = MainSearchEntryContext.smartList(id: 42, name: "最近合同")

        model.enterSearch(context: smartListContext)
        await model.runSearch(
            query: "合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: tree.sidebarRows[0],
            filters: .task98ContractFilters()
        )
        model.clearSearch()

        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 42, name: "最近合同"))
        XCTAssertEqual(model.searchState, .idle)
        XCTAssertNil(model.pendingSearchDestination)
    }
}

private extension RepositoryOpeningResult {
    static func task98Fixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func task98FixtureTree() -> RepositoryTreeNodeSnapshot {
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

private extension SearchFilterStateSnapshot {
    static func task98ContractFilters() -> SearchFilterStateSnapshot {
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

private extension SearchResultPageSnapshot {
    static func task98SearchPage(
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

private extension SearchFacetsSnapshot {
    static func task98SearchFacets(
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

private extension FileEntrySnapshot {
    static func task98Fixture(
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
            hashSha256: "task-98-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000 - id,
            updatedAt: 1_700_000_000
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func task98Mapping(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: .high,
            suggestedAction: "mapped action",
            recoverability: .userActionRequired,
            rawContext: "task-98"
        )
    }
}
