@testable import AreaMatrix
import XCTest

final class SemanticSearchCoreRoutingTests: XCTestCase {
    @MainActor
    func testSemanticSearchSemanticModeRoutesToSemanticSearchCoreSemanticSearchAndKeepsNormalFallbackGroup() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
        guard let row = requireSidebarRow(tree, id: "finance/invoices") else { return }
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

        await model.searchModel.runSearch(
            query: " 上个月的发票 ",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: SearchFilterStateSnapshot.empty,
            mode: SearchModeSnapshot.semantic
        )

        await semantic.assertSemanticRequest(query: "上个月的发票", mode: SearchModeSnapshot.semantic)
        await normal.assertSearchRequests([])
        XCTAssertEqual(model.searchModel.searchState.page?.semanticPage?.semanticTotalCount, 1)
        XCTAssertEqual(model.searchModel.searchState.page?.semanticPage?.normalTotalCount, 1)
        XCTAssertEqual(model.files.map(\.id), [semanticFile.id, normalFile.id])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.semanticSearch))
    }

    @MainActor
    func testSemanticSearchBuildSemanticIndexRunsOnlyAfterExplicitUserAction() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
        guard let row = requireSidebarRow(tree, id: "finance/invoices") else { return }
        let semantic = SemanticSearchSemanticSearcher(page: .semanticSearchIndexNotReadyPage())
        let model = MainFileListModel(
            opening: .semanticSearchFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: SemanticSearchLister(),
            fileDetailer: SemanticSearchDetailer(file: .semanticSearchFixture(id: 672)),
            searchQuerying: SemanticSearchNormalSearcher(),
            semanticSearching: semantic,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchFailure)
        )

        await model.searchModel.runSearch(
            query: "客户合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: SearchFilterStateSnapshot.empty,
            mode: SearchModeSnapshot.semantic
        )
        await semantic.assertNoIndexRequests()

        await model.searchModel.buildSemanticIndexForCurrentSearch()

        await semantic.assertIndexRequests(queries: ["客户合同"], modes: [SearchModeSnapshot.semantic])
        XCTAssertFalse(model.searchModel.semanticIndexBuildState.isBuilding)
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.buildEmbeddingIndex))
    }
}
