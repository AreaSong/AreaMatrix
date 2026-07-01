@testable import AreaMatrix
import XCTest

final class SemanticSearchCoreRoutingTests: XCTestCase {
    @MainActor
    func testSemanticSearchSemanticModeRoutesToSemanticSearchCoreSemanticSearchAndKeepsNormalFallbackGroup() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let semanticFile = FileEntrySnapshot.semanticSearchFixture(id: 670, name: "invoice_0426.pdf")
        let normalFile = FileEntrySnapshot.semanticSearchFixture(id: 671, name: "invoice_notes.txt")
        let semantic = SemanticSearchSemanticSearcher(page: .semanticSearchPage(
            semanticFile: semanticFile,
            normalFile: normalFile
        ))
        let normal = SemanticSearchNormalSearcher()
        let model = MainFileListModel(
            opening: .semanticSearchFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: SemanticSearchLister(),
            fileDetailer: SemanticSearchDetailer(file: semanticFile),
            searchQuerying: normal,
            semanticSearching: semantic,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchFailure)
        )

        await model.runSearch(
            query: " 上个月的发票 ",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: SearchFilterStateSnapshot.empty,
            mode: SearchModeSnapshot.semantic
        )
        let semanticRequests = await semantic.semanticRequests()
        let normalRequests = await normal.requests()

        XCTAssertEqual(semanticRequests.first?.query, "上个月的发票")
        XCTAssertEqual(semanticRequests.first?.mode, SearchModeSnapshot.semantic)
        XCTAssertEqual(normalRequests, [])
        XCTAssertEqual(model.searchState.page?.semanticPage?.semanticTotalCount, 1)
        XCTAssertEqual(model.searchState.page?.semanticPage?.normalTotalCount, 1)
        XCTAssertEqual(model.files.map(\.id), [semanticFile.id, normalFile.id])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.semanticSearch))
    }

    @MainActor
    func testSemanticSearchBuildSemanticIndexRunsOnlyAfterExplicitUserAction() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let semantic = SemanticSearchSemanticSearcher(page: .semanticSearchIndexNotReadyPage())
        let model = MainFileListModel(
            opening: .semanticSearchFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: SemanticSearchLister(),
            fileDetailer: SemanticSearchDetailer(file: .semanticSearchFixture(id: 672)),
            searchQuerying: SemanticSearchNormalSearcher(),
            semanticSearching: semantic,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchFailure)
        )

        await model.runSearch(
            query: "客户合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: SearchFilterStateSnapshot.empty,
            mode: SearchModeSnapshot.semantic
        )
        let initialIndexRequests = await semantic.indexRequests()
        XCTAssertEqual(initialIndexRequests, [])

        await model.buildSemanticIndexForCurrentSearch()
        let indexRequests = await semantic.indexRequests()

        XCTAssertEqual(indexRequests.map(\.query), ["客户合同"])
        XCTAssertEqual(indexRequests.map(\.mode), [SearchModeSnapshot.semantic])
        XCTAssertFalse(model.semanticIndexBuildState.isBuilding)
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.buildEmbeddingIndex))
    }
}
