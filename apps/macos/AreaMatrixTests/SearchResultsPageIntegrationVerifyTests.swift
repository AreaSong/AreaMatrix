@testable import AreaMatrix
import AreaMatrixFeatureLibrary
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

        await model.searchModel.runSearch(
            query: " 合同 ",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: filters
        )
        await model.searchModel.loadSearchFacets(query: "合同", scope: .current, sidebarRow: row, filters: filters)
        await model.selectFiles([resultFile.id])
        model.searchModel.clearSearch()

        await searcher.assertRequestFilters([filters])
        await facetLoader.assertRequestFilters([filters])
        await detailer.assertFileDetailRequests([FileDetailRequest(repoPath: "/tmp/repo", fileID: resultFile.id)])
        XCTAssertEqual(model.searchModel.searchState, .idle)
        XCTAssertEqual(model.searchModel.searchFacetsState, .idle)
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

        await model.searchModel.runSearch(
            query: "missing",
            scope: .current,
            sort: .newestImported,
            sidebarRow: row,
            filters: .empty
        )
        XCTAssertEqual(model.searchModel.searchPageDestination?.pageID, "search-empty")
        XCTAssertEqual(model.files, [])
        await searcher.assertSearchRequestQueries(["missing"])
        model.searchModel.openSavedSearchSheet()
        XCTAssertEqual(model.searchModel.pendingSearchDestination?.pageID, "saved-search")
        model.searchModel.clearPendingSearchDestination()

        await model.searchModel.runSearch(
            query: "owner:me",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty
        )
        XCTAssertEqual(model.searchModel.searchPageDestination?.pageID, "query-error")
        XCTAssertFalse(model.searchModel.canSaveCurrentSearch)
        XCTAssertNil(model.searchModel.searchState.errorMapping)

        await model.searchModel.runSearch(
            query: "",
            scope: .current,
            sort: .newestModified,
            sidebarRow: row,
            filters: .searchResultsContractFilters()
        )
        XCTAssertTrue(model.searchModel.canSaveCurrentSearch)

        await model.searchModel.runSearch(
            query: "合同",
            scope: .current,
            sort: .newestImported,
            sidebarRow: row,
            filters: .empty
        )
        model.searchModel.openIndexingStatus()
        XCTAssertEqual(model.searchModel.pendingSearchDestination?.pageID, "search-index-status-indexing-status")

        model.searchModel.enterSearch(context: .commandFind)
        XCTAssertEqual(model.searchModel.lastSearchExitContext, .toolbar)
        model.searchModel.openCommandPaletteForSearch()
        XCTAssertEqual(model.searchModel.pendingSearchDestination?.pageID, "command-palette")
        XCTAssertEqual(model.searchModel.lastSearchExitContext, .toolbar)
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

        model.searchModel.enterSearch(context: smartListContext)
        await model.searchModel.runSearch(
            query: "合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: tree.sidebarRows[0],
            filters: .searchResultsContractFilters()
        )
        model.searchModel.clearSearch()

        XCTAssertEqual(model.searchModel.lastSearchExitContext, .smartList(id: 42, name: "最近合同"))
        XCTAssertEqual(model.searchModel.searchState, .idle)
        XCTAssertNil(model.searchModel.pendingSearchDestination)
    }
}
