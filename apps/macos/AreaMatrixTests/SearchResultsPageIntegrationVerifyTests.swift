@testable import AreaMatrix
import XCTest

final class SearchResultsPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testSearchResultsPageIntegrationWiresSearchFiltersResultDetailAndClear() async {
        let tree = RepositoryTreeNodeSnapshot.searchResultsFixtureTree()
        guard let row = requireSidebarRow(tree, id: "docs/contracts") else { return }
        let resultFile = FileEntrySnapshot.searchResultsFixture(
            id: 298,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.searchResultsPage(query: "合同", files: [resultFile]))
        ])
        let facetLoader = MainListRecordingSearchFiltering(results: [
            .success(.searchResultsFacets(query: "合同", totalCount: 1, activeFilters: 1))
        ])
        let detailer = RecordingFileDetailer(results: [.success(resultFile)])
        let filters = SearchFilterStateSnapshot.searchResultsContractFilters()
        let model = MainFileListModel(
            opening: .searchResultsFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: detailer,
            searchQuerying: searcher,
            searchFiltering: facetLoader,
            errorMapper: StaticCoreErrorMapper(mapping: .searchResultsMapping(kind: .db))
        )

        await model.runSearch(query: " 合同 ", scope: .current, sort: .relevance, sidebarRow: row, filters: filters)
        await model.loadSearchFacets(query: "合同", scope: .current, sidebarRow: row, filters: filters)
        await model.selectFiles([resultFile.id])
        model.clearSearch()

        await searcher.assertRequestFilters([filters])
        await facetLoader.assertRequestFilters([filters])
        await detailer.assertRecordedRequests([FileDetailRequest(repoPath: "/tmp/repo", fileID: resultFile.id)])
        XCTAssertEqual(model.searchState, .idle)
        XCTAssertEqual(model.searchFacetsState, .idle)
        XCTAssertEqual(model.selection, .none)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testSearchResultsPageIntegrationRoutesEmptyQueryErrorIndexingSaveAndCommandEntrances() async {
        let tree = RepositoryTreeNodeSnapshot.searchResultsFixtureTree()
        guard let row = requireSidebarRow(tree, id: "docs/contracts") else { return }
        let diagnostic = SearchQueryDiagnosticSnapshot.testFixture(
            message: "Unknown field: owner",
            suggestion: "Use category:"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.searchResultsPage(query: "missing", files: [])),
            .success(.searchResultsPage(query: "owner:me", diagnostics: [diagnostic])),
            .success(.searchResultsPage(query: "")),
            .success(.searchResultsPage(query: "合同", files: [], indexStatus: .unavailable))
        ])
        let model = MainFileListModel(
            opening: .searchResultsFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .searchResultsMapping(kind: .db))
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
        await searcher.assertRecordedQueries(["missing"])
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
            filters: .searchResultsContractFilters()
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
        let tree = RepositoryTreeNodeSnapshot.searchResultsFixtureTree()
        let resultFile = FileEntrySnapshot.searchResultsFixture(
            id: 299,
            path: "docs/contracts/smart.pdf",
            category: "docs",
            currentName: "smart.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.searchResultsPage(query: "合同", files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .searchResultsFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .searchResultsMapping(kind: .db))
        )
        let smartListContext = MainSearchEntryContext.smartList(id: 42, name: "最近合同")

        model.enterSearch(context: smartListContext)
        await model.runSearch(
            query: "合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: tree.sidebarRows[0],
            filters: .searchResultsContractFilters()
        )
        model.clearSearch()

        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 42, name: "最近合同"))
        XCTAssertEqual(model.searchState, .idle)
        XCTAssertNil(model.pendingSearchDestination)
    }
}
