@testable import AreaMatrix
import AreaMatrixFeatureLibrary
import XCTest

final class MainListIntegrationFilterTests: XCTestCase {
    func testCurrentListFilterMatchesLoadedFileNamesOnly() {
        let files = [
            FileEntrySnapshot.integrationFilterFixture(
                id: 1,
                path: "docs/contracts/customer.pdf",
                category: "docs",
                currentName: "customer.pdf"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 2,
                path: "docs/references/research.md",
                category: "docs",
                currentName: "research.md"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 3,
                path: "docs/contracts/budget.xlsx",
                category: "docs",
                currentName: "budget.xlsx"
            )
        ]
        let row = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
            .sidebarRow(id: "docs/contracts")

        guard let row else {
            return XCTFail("expected docs/contracts sidebar row")
        }

        let result = MainListFiltering.visibleItems(
            from: files,
            filterText: "customer",
            isInSelectedScope: row.contains,
            displayName: \FileEntrySnapshot.currentName
        )

        XCTAssertEqual(result.map(\.id), [1])
    }

    func testCurrentListFilterDoesNotSearchAcrossCategoryOrPathFields() {
        let files = [
            FileEntrySnapshot.integrationFilterFixture(
                id: 1,
                path: "docs/contracts/customer.pdf",
                category: "docs",
                currentName: "customer.pdf"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 2,
                path: "docs/references/research.md",
                category: "docs",
                currentName: "research.md"
            )
        ]
        let row = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
            .sidebarRow(id: "docs")

        guard let row else {
            return XCTFail("expected docs sidebar row")
        }

        let result = MainListFiltering.visibleItems(
            from: files,
            filterText: "contracts",
            isInSelectedScope: row.contains,
            displayName: \FileEntrySnapshot.currentName
        )

        XCTAssertEqual(result, [])
    }

    @MainActor
    func testMainListSearchQueriesAllRepoThroughSearchQueryFilesCoreSearchFiles() async {
        let resultFile = FileEntrySnapshot.integrationFilterFixture(
            id: 201,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.mainSearchFixture(query: "合同", files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.searchModel.runSearch(
            query: " 合同 ",
            scope: .all,
            sort: .newestImported,
            sidebarRow: RepositoryTreeNodeSnapshot.integrationFilterFixtureTree().sidebarRows[0],
            filters: .empty
        )
        await searcher.assertSearchRequests([
            .testFixture(
                query: "合同",
                sort: .newestImported
            )
        ])
        XCTAssertEqual(model.files, [resultFile])
        XCTAssertEqual(model.searchModel.searchState.page?.totalCount, 1)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListSearchCurrentScopeCarriesSidebarContext() async {
        let tree = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
        guard let row = requireSidebarRow(tree, id: "docs/contracts") else { return }
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.mainSearchFixture(query: "customer", files: []))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.searchModel.runSearch(
            query: "customer",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty
        )
        await searcher.assertSearchRequests([
            .testFixture(
                query: "customer",
                scope: .current,
                currentPath: "docs/contracts",
                category: "docs"
            )
        ])
    }

    @MainActor
    func testMainListSearchFailureMapsErrorAndPreservesRequestForRetry() async {
        let mapping = CoreErrorMappingSnapshot.integrationFilterDbFixture(rawContext: "search db locked")
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let searcher = MainListRecordingSearchQuerying(results: [
            .failure(CoreError.Db(message: "search db locked"))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: mapper
        )

        await model.searchModel.runSearch(
            query: "合同",
            scope: .all,
            sort: .newestImported,
            sidebarRow: RepositoryTreeNodeSnapshot.integrationFilterFixtureTree().sidebarRows[0],
            filters: .empty
        )

        XCTAssertEqual(model.searchModel.searchState.errorMapping, mapping)
        XCTAssertEqual(model.searchModel.searchState.request?.query, "合同")
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "search db locked")])
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListSearchClearExitsSearchMode() async {
        let resultFile = FileEntrySnapshot.integrationFilterFixture(
            id: 202,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.mainSearchFixture(query: "合同", files: [resultFile], indexStatus: .unavailable))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.searchModel.runSearch(
            query: "合同",
            scope: .all,
            sort: .newestImported,
            sidebarRow: RepositoryTreeNodeSnapshot.integrationFilterFixtureTree().sidebarRows[0],
            filters: .empty
        )
        model.searchModel.clearSearch()

        XCTAssertEqual(model.searchModel.searchState, .idle)
        XCTAssertNil(model.errorMapping)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testSemanticSearchSemanticSearchLoadsAIFallbackCoreFallbackStatusFromCore() async {
        let tree = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
        guard let row = requireSidebarRow(tree, id: "docs/contracts") else { return }
        let fallback = MainListRecordingSemanticFallbackReader(status: .semanticSearchSemanticIndexNotReady())
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            semanticSearching: MainListRecordingSemanticSearcher(page: .semanticSearchSemanticFallbackFixture()),
            semanticFallbackReader: fallback,
            errorMapper: StaticCoreErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.searchModel.runSearch(
            query: "客户合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty,
            mode: .semantic
        )
        await fallback.assertSemanticFallbackStatusRequests([
            .semanticSearchIndexNotReady(repoPath: "/tmp/repo", callLogID: 308)
        ])
        XCTAssertEqual(model.searchModel.semanticFallbackState.status?.primaryAction, .buildSemanticIndex)
        XCTAssertEqual(model.searchModel.semanticFallbackState.status?.nonAIFallbackAction, .useNormalSearch)
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.getAiFallbackStatus))
    }
}
