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

        XCTAssertEqual(page.semanticRows().map(\.matchSource), [L10n.message("Semantic")])
        XCTAssertEqual(page.normalRows(showFoldedDuplicates: false).map(\.file.id), [normalOnlyFile.id])
        XCTAssertEqual(
            page.normalRows(showFoldedDuplicates: true).map(\.file.id),
            [duplicateFile.id, normalOnlyFile.id]
        )
        XCTAssertEqual(page.semanticRows().first?.relevance, "0.91")
        XCTAssertEqual(page.semanticRows().first?.matchedReason, "filename and summary match invoice")
        let localizer = AppLocalizer(runtime: AppLanguageRuntime(selection: .en))
        XCTAssertEqual(
            page.semanticRows().first?.whyThisMatched.resolve(using: localizer).contains("File name"),
            true
        )
        XCTAssertEqual(
            page.detailPresentation(for: semanticFile.id)?.title,
            L10n.message("From semantic search")
        )
        XCTAssertEqual(page.detailPresentation(for: semanticFile.id)?.alsoMatchedNormalSearch, true)
    }

    @MainActor
    func testSemanticSearchLoadMoreSemanticMergesOnlyRequestedGroup() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchPageTree()
        guard let row = requireSidebarRow(tree, id: "finance/invoices") else { return }
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

        await model.searchModel.runSearch(
            query: "invoice",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty,
            mode: .semantic
        )
        await model.searchModel.loadMoreSemanticMatches(.semantic)

        await searcher.assertRequestOffsets([0, 1])
        XCTAssertEqual(model.searchModel.searchState.page?.semanticPage?.semanticMatches.map(\.result.file.id), [
            firstSemantic.id,
            nextSemantic.id
        ])
        XCTAssertEqual(
            model.searchModel.searchState.page?.semanticPage?.normalMatches.map(\.result.file.id),
            [normalFile.id]
        )
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testSemanticSearchIndexLifecycleCancelsActiveCoreBuildAndKeepsLaterReportOutOfPage() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchPageTree()
        guard let row = requireSidebarRow(tree, id: "finance/invoices") else { return }
        let searcher = SemanticSearchDelayedSemanticSearcher(page: .semanticSearchIndexBuildingPage())
        let model = MainFileListModel(
            opening: .semanticSearchPageOpening(tree: tree),
            fileLister: SemanticSearchPageLister(),
            fileDetailer: SemanticSearchPageDetailer(file: .semanticSearchPageFile(id: 8707)),
            searchQuerying: SemanticSearchPageNormalSearcher(),
            semanticSearching: searcher,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .semanticSearchPrivacyRules(),
                evaluationReport: .semanticSearchAllowed()
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .semanticSearchPageFailure)
        )

        await model.searchModel.runSearch(
            query: "contracts",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty,
            mode: .semantic
        )
        let buildTask = Task { await model.searchModel.buildSemanticIndexForCurrentSearch() }
        await searcher.waitForBuildStart()

        XCTAssertTrue(model.searchModel.semanticIndexBuildState.canPause)
        XCTAssertTrue(model.searchModel.semanticIndexBuildState.canCancel)

        await model.searchModel.pauseSemanticIndexBuildForCurrentSearch()
        guard case let .pauseFailed(_, pauseError) = model.searchModel.semanticIndexControlState else {
            return XCTFail("Expected pause to expose the missing Core pause contract.")
        }
        XCTAssertEqual(pauseError.rawContext, "semantic-search pause index build missing Core API")
        XCTAssertTrue(model.searchModel.semanticIndexBuildState.isBuilding)

        model.searchModel.requestCancelSemanticIndexBuildForCurrentSearch()
        guard case .cancelConfirm = model.searchModel.semanticIndexControlState else {
            return XCTFail("Expected cancel confirmation state.")
        }
        model.searchModel.keepBuildingSemanticIndexForCurrentSearch()
        XCTAssertEqual(model.searchModel.semanticIndexControlState, .idle)

        model.searchModel.requestCancelSemanticIndexBuildForCurrentSearch()
        await model.searchModel.cancelSemanticIndexBuildForCurrentSearch()

        guard case .canceled = model.searchModel.semanticIndexControlState else {
            return XCTFail("Expected canceled state.")
        }
        guard case .canceled = model.searchModel.semanticIndexBuildState else {
            return XCTFail("Expected build state to be canceled.")
        }
        XCTAssertTrue(model.searchModel.semanticIndexBuildState.canRetryFailedItems)
        XCTAssertEqual(
            model.searchModel.searchState.page?.semanticPage?.fallbackMessage,
            "Semantic index build canceled."
        )
        await searcher.finishBuild()
        await buildTask.value
        guard case .canceled = model.searchModel.semanticIndexBuildState else {
            return XCTFail("Late Core build report must not replace the canceled UI state.")
        }
        XCTAssertEqual(model.searchModel.searchState.page?.semanticPage?.indexStatus, .canceled)
        await searcher.assertObservedCancellationCount(1)
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
        let localizer = AppLocalizer(runtime: AppLanguageRuntime(selection: .en))

        XCTAssertEqual(status.primaryAction, .buildSemanticIndex)
        XCTAssertEqual(status.nonAIFallbackAction, .useNormalSearch)
        XCTAssertEqual(status.actions, [.buildSemanticIndex, .useNormalSearch])
        XCTAssertTrue(status.canBuildSemanticIndex)
        XCTAssertEqual(localizer.resolve(status.title), "Semantic index is not ready")
        XCTAssertEqual(localizer.resolve(status.message), "Semantic index is not ready yet.")
        XCTAssertEqual(status.actionPresentations.map(\.accessibilityIdentifier), [
            "ai-fallback-semantic-search-core-action-build-semantic-index",
            "ai-fallback-semantic-search-core-action-use-normal-search"
        ])
        XCTAssertFalse(status.actions.contains(.classifyManually))
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
        let localizer = AppLocalizer(runtime: AppLanguageRuntime(selection: .en))

        XCTAssertEqual(status.title, L10n.message("Remote AI could not be reached"))
        XCTAssertTrue(status.retryable)
        XCTAssertEqual(status.actions, [.viewCallLog, .useNormalSearch])
        XCTAssertFalse(status.canBuildSemanticIndex)
        let presentations = [status.presentation(for: .retry)] + status.actionPresentations
        XCTAssertEqual(presentations.map(\.accessibilityIdentifier), [
            "ai-fallback-semantic-search-core-action-retry",
            "ai-fallback-semantic-search-core-action-view-call-log",
            "ai-fallback-semantic-search-core-action-use-normal-search"
        ])
        XCTAssertEqual(presentations.map { localizer.resolve($0.title) }, [
            "Retry",
            "View call log",
            "Use normal search"
        ])
        XCTAssertFalse(status.actions.contains(.classifyManually))
    }
}
