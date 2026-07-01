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
        model.searchState = .loaded(request: request, page: .semanticSearchSemanticPrivacyPage(route: .remote))

        await model.buildSemanticIndexForCurrentSearch()

        let privacyRequests = await privacy.requests()
        let indexRequests = await semantic.indexRequests()
        XCTAssertEqual(privacyRequests.loadCount, 1)
        XCTAssertEqual(privacyRequests.evaluations.first?.feature, .semanticSearch)
        XCTAssertEqual(privacyRequests.evaluations.first?.route, .remote)
        XCTAssertEqual(privacyRequests.evaluations.first?.context.repoRelativePath, "finance/invoices")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.fileName, "客户合同")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.category, "finance")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.extension, "pdf")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.tags, ["confidential"])
        XCTAssertEqual(indexRequests, [request])
        XCTAssertTrue(model.semanticPrivacyGateState.allowsIndexBuild)
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
        model.searchState = .loaded(request: request, page: .semanticSearchSemanticPrivacyPage(route: .remote))

        await model.buildSemanticIndexForCurrentSearch()

        let indexRequests = await semantic.indexRequests()
        XCTAssertEqual(indexRequests, [])
        XCTAssertEqual(model.semanticPrivacyGateState.matchedRuleID, "rule-confidential")
        XCTAssertFalse(model.semanticIndexBuildState.isBuilding)
    }
}
