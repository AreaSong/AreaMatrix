@testable import AreaMatrix
import XCTest

final class SemanticSearchPrivacyRulesCoreTests: XCTestCase {
    @MainActor
    func testSemanticSearchAIPrivacyRulesCoreSemanticIndexChecksPrivacyRulesBeforeCoreBuild() async {
        let request = SearchQueryRequestSnapshot.semanticSearchSemanticPrivacyFixture()
        let semantic = SemanticSearchPrivacySemanticSearcher()
        let privacy = RemotePrivacyRulesBridge(
            snapshot: .semanticSearchPrivacyRules(),
            evaluationReport: .semanticSearchAllowed()
        )
        let model = MainFileListModel(
            opening: .initDoneFixture(repoPath: "/tmp/repo", fileCount: 0),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(.deleteFixture(
                id: 680,
                name: "invoice.pdf",
                storageMode: "Copied"
            ))),
            semanticSearching: semantic,
            aiPrivacyRules: privacy,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchPrivacyFailure)
        )
        model.searchModel.searchState = .loaded(
            request: request,
            page: .semanticSearchSemanticPrivacyPage(route: .remote)
        )

        await model.searchModel.buildSemanticIndexForCurrentSearch()

        await privacy.assertLoadCount(1)
        await privacy.assertEvaluation(
            at: 0,
            feature: .semanticSearch,
            route: .remote,
            repoRelativePath: "finance/invoices",
            fileName: "客户合同",
            category: "finance",
            fileExtension: "pdf",
            tags: ["confidential"]
        )
        await semantic.assertIndexRequests([request])
        XCTAssertTrue(model.searchModel.semanticPrivacyGateState.allowsIndexBuild)
    }

    @MainActor
    func testSemanticSearchAIPrivacyRulesCorePrivacyRuleBlockPreventsSemanticIndexBuild() async {
        let request = SearchQueryRequestSnapshot.semanticSearchSemanticPrivacyFixture()
        let semantic = SemanticSearchPrivacySemanticSearcher()
        let privacy = RemotePrivacyRulesBridge(
            snapshot: .semanticSearchPrivacyRules(),
            evaluationReport: .semanticSearchBlocked()
        )
        let model = MainFileListModel(
            opening: .initDoneFixture(repoPath: "/tmp/repo", fileCount: 0),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(.deleteFixture(
                id: 681,
                name: "confidential.pdf",
                storageMode: "Copied"
            ))),
            semanticSearching: semantic,
            aiPrivacyRules: privacy,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchPrivacyFailure)
        )
        model.searchModel.searchState = .loaded(
            request: request,
            page: .semanticSearchSemanticPrivacyPage(route: .remote)
        )

        await model.searchModel.buildSemanticIndexForCurrentSearch()

        await semantic.assertNoIndexRequests()
        XCTAssertEqual(model.searchModel.semanticPrivacyGateState.matchedRuleID, "rule-confidential")
        XCTAssertFalse(model.searchModel.semanticIndexBuildState.isBuilding)
    }
}
