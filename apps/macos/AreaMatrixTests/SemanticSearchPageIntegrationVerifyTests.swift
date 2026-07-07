@testable import AreaMatrix
import XCTest

final class SemanticSearchPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testSemanticSearchPresentationKeepsSemanticAndNormalGroupsWithDuplicateExpansion() {
        let semanticFile = FileEntrySnapshot.semanticSearchPageFile(id: 8701, name: "invoice_0426.pdf")
        let duplicateFile = FileEntrySnapshot.semanticSearchPageFile(id: 8702, name: "invoice_notes.txt")
        let normalOnlyFile = FileEntrySnapshot.semanticSearchPageFile(id: 8703, name: "payment_notes.txt")
        let page = SemanticSearchResultPageSnapshot.semanticSearchPage(
            semanticMatches: [
                .semanticSearchPage(
                    result: .semanticSearchPageResult(file: semanticFile),
                    alsoMatchedNormalSearch: true
                )
            ],
            normalMatches: [
                .testFixture(
                    result: .semanticSearchPageResult(file: duplicateFile, snippet: "filename contains invoice"),
                    dedupedBySemantic: true
                ),
                .testFixture(result: .semanticSearchPageResult(file: normalOnlyFile, snippet: "note mentions payment"))
            ],
            dedupedNormalCount: 1
        )

        XCTAssertEqual(page.semanticRows().map(\.matchSource), ["Semantic"])
        XCTAssertEqual(page.normalRows(showFoldedDuplicates: false).map(\.file.id), [normalOnlyFile.id])
        XCTAssertEqual(
            page.normalRows(showFoldedDuplicates: true).map(\.file.id),
            [duplicateFile.id, normalOnlyFile.id]
        )
        XCTAssertEqual(page.semanticRows().first?.relevance, "0.91")
        XCTAssertEqual(page.semanticRows().first?.matchedReason, "filename and summary match invoice")
        XCTAssertEqual(page.semanticRows().first?.whyThisMatched.contains("File name"), true)
        XCTAssertEqual(page.detailPresentation(for: semanticFile.id)?.title, "From semantic search")
        XCTAssertEqual(page.detailPresentation(for: semanticFile.id)?.alsoMatchedNormalSearch, true)
    }

    @MainActor
    func testSemanticSearchLoadMoreSemanticMergesOnlyRequestedGroup() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchPageTree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let firstSemantic = FileEntrySnapshot.semanticSearchPageFile(id: 8704, name: "invoice_a.pdf")
        let nextSemantic = FileEntrySnapshot.semanticSearchPageFile(id: 8705, name: "invoice_b.pdf")
        let normalFile = FileEntrySnapshot.semanticSearchPageFile(id: 8706, name: "invoice_notes.txt")
        let searcher = SemanticSearchPagedSemanticSearcher(pages: [
            .semanticSearchSearchPage(semantic: [firstSemantic], normal: [normalFile], semanticTotalCount: 2),
            .semanticSearchSearchPage(semantic: [nextSemantic], normal: [], semanticTotalCount: 2)
        ])
        let model = MainFileListModel(
            opening: .semanticSearchPageOpening(tree: tree),
            fileLister: SemanticSearchPageLister(),
            fileDetailer: SemanticSearchPageDetailer(file: firstSemantic),
            searchQuerying: SemanticSearchPageNormalSearcher(),
            semanticSearching: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchPageFailure)
        )

        await model.runSearch(
            query: "invoice",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty,
            mode: .semantic
        )
        await model.loadMoreSemanticMatches(.semantic)

        let requests = await searcher.requests()
        XCTAssertEqual(requests.map(\.offset), [0, 1])
        XCTAssertEqual(model.searchState.page?.semanticPage?.semanticMatches.map(\.result.file.id), [
            firstSemantic.id,
            nextSemantic.id
        ])
        XCTAssertEqual(model.searchState.page?.semanticPage?.normalMatches.map(\.result.file.id), [normalFile.id])
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testSemanticSearchIndexLifecycleCancelsActiveCoreBuildAndKeepsLaterReportOutOfPage() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchPageTree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let searcher = SemanticSearchDelayedSemanticSearcher(page: .semanticSearchIndexBuildingPage())
        let model = MainFileListModel(
            opening: .semanticSearchPageOpening(tree: tree),
            fileLister: SemanticSearchPageLister(),
            fileDetailer: SemanticSearchPageDetailer(file: .semanticSearchPageFile(id: 8707)),
            searchQuerying: SemanticSearchPageNormalSearcher(),
            semanticSearching: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchPageFailure)
        )

        await model.runSearch(
            query: "contracts",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty,
            mode: .semantic
        )
        let buildTask = Task { await model.buildSemanticIndexForCurrentSearch() }
        await searcher.waitForBuildStart()

        XCTAssertTrue(model.semanticIndexBuildState.canPause)
        XCTAssertTrue(model.semanticIndexBuildState.canCancel)

        await model.pauseSemanticIndexBuildForCurrentSearch()
        guard case let .pauseFailed(_, pauseError) = model.semanticIndexControlState else {
            return XCTFail("Expected pause to expose the missing Core pause contract.")
        }
        XCTAssertEqual(pauseError.rawContext, "semantic-search pause index build missing Core API")
        XCTAssertTrue(model.semanticIndexBuildState.isBuilding)

        model.requestCancelSemanticIndexBuildForCurrentSearch()
        guard case .cancelConfirm = model.semanticIndexControlState else {
            return XCTFail("Expected cancel confirmation state.")
        }
        model.keepBuildingSemanticIndexForCurrentSearch()
        XCTAssertEqual(model.semanticIndexControlState, .idle)

        model.requestCancelSemanticIndexBuildForCurrentSearch()
        await model.cancelSemanticIndexBuildForCurrentSearch()

        guard case .canceled = model.semanticIndexControlState else {
            return XCTFail("Expected canceled state.")
        }
        guard case .canceled = model.semanticIndexBuildState else {
            return XCTFail("Expected build state to be canceled.")
        }
        XCTAssertTrue(model.semanticIndexBuildState.canRetryFailedItems)
        XCTAssertEqual(model.searchState.page?.semanticPage?.fallbackMessage, "Semantic index build canceled.")
        await searcher.finishBuild()
        await buildTask.value
        guard case .canceled = model.semanticIndexBuildState else {
            return XCTFail("Late Core build report must not replace the canceled UI state.")
        }
        XCTAssertEqual(model.searchState.page?.semanticPage?.indexStatus, .canceled)
        let cancellationCount = await searcher.observedCancellationCount()
        XCTAssertEqual(cancellationCount, 1)
    }

    @MainActor
    func testSemanticFallbackUsesSemanticSearchOutputWithoutWaitingForAIFallbackReader() {
        let page = SemanticSearchResultPageSnapshot.semanticSearchPage(
            semanticMatches: [],
            normalMatches: [],
            indexStatus: .notReady,
            fallbackReason: .semanticIndexNotReady,
            fallbackMessage: "Semantic index is not ready yet."
        )
        let status = SemanticSearchFallbackStatus.fromSemanticPage(page)
        let region = SemanticSearchFallbackStatusRegion(
            page: page,
            state: .idle,
            isIndexBuildBusy: false,
            isPrivacyGateChecking: false,
            onAction: { _ in }
        )

        XCTAssertEqual(status.primaryAction, .buildSemanticIndex)
        XCTAssertEqual(status.nonAiFallbackAction, .useNormalSearch)
        XCTAssertEqual(status.actions, [.buildSemanticIndex, .useNormalSearch])
        XCTAssertTrue(status.canBuildSemanticIndex)
        assertTestMirrorDescription(of: region.body, contains: [
            "Semantic index is not ready",
            "Build semantic index",
            "Use normal search"
        ], doesNotContain: "Classify manually", maxDepth: 8)
    }

    @MainActor
    func testAIFallbackSemanticSearchCoreProviderFallbackKeepsNormalSearchAndCallLogActions() {
        let page = SemanticSearchResultPageSnapshot.semanticSearchPage(
            semanticMatches: [],
            normalMatches: [],
            indexStatus: .failed,
            fallbackReason: .providerUnavailable,
            fallbackMessage: "Remote AI could not be reached. Your files were not changed."
        )
        let status = SemanticSearchFallbackStatus.fromSemanticPage(page)
        let region = SemanticSearchFallbackStatusRegion(
            page: page,
            state: .idle,
            isIndexBuildBusy: false,
            isPrivacyGateChecking: false,
            onAction: { _ in }
        )

        XCTAssertEqual(status.title, "Remote AI could not be reached")
        XCTAssertTrue(status.retryable)
        XCTAssertEqual(status.actions, [.viewCallLog, .useNormalSearch])
        XCTAssertFalse(status.canBuildSemanticIndex)
        assertTestMirrorDescription(of: region.body, contains: [
            "Retry",
            "View call log",
            "Use normal search"
        ], doesNotContain: "Classify manually", maxDepth: 8)
    }
}
