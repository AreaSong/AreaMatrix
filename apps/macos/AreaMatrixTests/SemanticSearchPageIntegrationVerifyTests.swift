// swiftlint:disable file_length
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
                .semanticSearchPage(result: .semanticSearchPageResult(file: semanticFile), alsoMatchedNormalSearch: true)
            ],
            normalMatches: [
                SemanticNormalSearchMatchSnapshot(
                    result: .semanticSearchPageResult(file: duplicateFile, snippet: "filename contains invoice"),
                    dedupedBySemantic: true
                ),
                SemanticNormalSearchMatchSnapshot(
                    result: .semanticSearchPageResult(file: normalOnlyFile, snippet: "note mentions payment"),
                    dedupedBySemantic: false
                )
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
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
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
            errorMapper: SemanticSearchPageErrorMapper()
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
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
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
            errorMapper: SemanticSearchPageErrorMapper()
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
    func testAIFallbackSemanticSearchCoreSemanticFallbackUsesSemanticSearchOutputWithoutWaitingForAIFallbackCoreReader() {
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
        let body = changeCategoryMirrorDescription(of: region.body)

        XCTAssertEqual(status.primaryAction, .buildSemanticIndex)
        XCTAssertEqual(status.nonAiFallbackAction, .useNormalSearch)
        XCTAssertEqual(status.actions, [.buildSemanticIndex, .useNormalSearch])
        XCTAssertTrue(status.canBuildSemanticIndex)
        XCTAssertTrue(body.contains("Semantic index is not ready"))
        XCTAssertTrue(body.contains("Build semantic index"))
        XCTAssertTrue(body.contains("Use normal search"))
        XCTAssertFalse(body.contains("Classify manually"))
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
        let body = changeCategoryMirrorDescription(of: region.body)

        XCTAssertEqual(status.title, "Remote AI could not be reached")
        XCTAssertTrue(status.retryable)
        XCTAssertEqual(status.actions, [.viewCallLog, .useNormalSearch])
        XCTAssertFalse(status.canBuildSemanticIndex)
        XCTAssertTrue(body.contains("Retry"))
        XCTAssertTrue(body.contains("View call log"))
        XCTAssertTrue(body.contains("Use normal search"))
        XCTAssertFalse(body.contains("Classify manually"))
    }
}

private actor SemanticSearchPagedSemanticSearcher: CoreSemanticSearching {
    private var pages: [SearchResultPageSnapshot]
    private var recordedRequests: [SearchQueryRequestSnapshot] = []

    init(pages: [SearchResultPageSnapshot]) {
        self.pages = pages
    }

    func semanticSearch(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SearchResultPageSnapshot {
        recordedRequests.append(request)
        return pages.removeFirst()
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        .semanticSearchReadyReport()
    }

    func requests() -> [SearchQueryRequestSnapshot] {
        recordedRequests
    }
}

private actor SemanticSearchDelayedSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot
    private var continuation: CheckedContinuation<Void, Never>?
    private var buildStarted = false
    private var cancellationCount = 0

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        buildStarted = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
        try Task.checkCancellation()
        return .semanticSearchReadyReport()
    }

    func waitForBuildStart() async {
        while !buildStarted {
            await Task.yield()
        }
    }

    func finishBuild() {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func observedCancellationCount() -> Int {
        cancellationCount
    }

    private func recordCancellation() {
        cancellationCount += 1
    }
}

private actor SemanticSearchPageNormalSearcher: CoreSearchQuerying {
    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(query: request.query, totalCount: 0, results: [], diagnostics: [], indexStatus: .ready)
    }
}

private actor SemanticSearchPageLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor SemanticSearchPageDetailer: CoreFileDetailing {
    private let file: FileEntrySnapshot

    init(file: FileEntrySnapshot) {
        self.file = file
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        file
    }
}

private struct SemanticSearchPageErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "semantic-search semantic page failed",
            severity: .medium,
            suggestedAction: "Retry the failed semantic group.",
            recoverability: .retryable,
            rawContext: "semantic-search"
        )
    }
}

private extension FileEntrySnapshot {
    static func semanticSearchPageFile(id: Int64, name: String = "invoice.pdf") -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "finance/invoices/\(name)",
            originalName: name,
            currentName: name,
            category: "finance",
            sizeBytes: 128,
            hashSha256: "semanticSearch-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension SearchFileResultSnapshot {
    static func semanticSearchPageResult(file: FileEntrySnapshot,
                               snippet: String = "filename contains invoice") -> SearchFileResultSnapshot {
        SearchFileResultSnapshot(
            file: file,
            score: 1,
            matches: [SearchMatchSnapshot(fieldDisplayName: "Name", kindDisplayName: "Exact", snippet: snippet)],
            noteSnippet: nil
        )
    }
}

private extension RepositoryOpeningResult {
    static func semanticSearchPageOpening(tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .semanticSearchPageConfig(), tree: tree, currentCategoryFiles: [])
    }
}

private extension RepoConfigSnapshot {
    static func semanticSearchPageConfig() -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: "/tmp/repo",
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: true,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func semanticSearchTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [.semanticSearchFinanceNode()]
        )
    }

    static func semanticSearchFinanceNode() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "finance",
            displayName: "finance",
            fileCount: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "invoices",
                    displayName: "invoices",
                    kind: "Subdir",
                    relativePath: "finance/invoices",
                    fileCount: 2,
                    depth: 2,
                    children: []
                )
            ]
        )
    }
}

private extension SemanticSearchMatchSnapshot {
    static func semanticSearchPage(
        result: SearchFileResultSnapshot,
        alsoMatchedNormalSearch: Bool = false
    ) -> SemanticSearchMatchSnapshot {
        SemanticSearchMatchSnapshot(
            result: result,
            relevance: 0.91,
            matchedReason: "filename and summary match invoice",
            usedFields: [.fileName, .aiSummary],
            route: .local,
            alsoMatchedNormalSearch: alsoMatchedNormalSearch,
            callLogID: 308,
            privacyRuleID: nil
        )
    }
}

private extension SemanticSearchResultPageSnapshot {
    static func semanticSearchPage(
        semanticMatches: [SemanticSearchMatchSnapshot],
        normalMatches: [SemanticNormalSearchMatchSnapshot],
        dedupedNormalCount: Int64 = 0,
        semanticTotalCount: Int64? = nil,
        indexStatus: SemanticIndexStatusSnapshot = .ready,
        fallbackReason: SemanticSearchFallbackReasonSnapshot? = nil,
        fallbackMessage: String? = nil
    ) -> SemanticSearchResultPageSnapshot {
        SemanticSearchResultPageSnapshot(
            query: "invoice",
            semanticTotalCount: semanticTotalCount ?? Int64(semanticMatches.count),
            normalTotalCount: Int64(normalMatches.count),
            semanticMatches: semanticMatches,
            normalMatches: normalMatches,
            dedupedNormalCount: dedupedNormalCount,
            indexStatus: indexStatus,
            route: .local,
            fallbackReason: fallbackReason,
            fallbackMessage: fallbackMessage,
            callLogID: 308,
            privacyRuleID: nil,
            lowConfidence: false
        )
    }
}

private extension SearchResultPageSnapshot {
    static func semanticSearchSearchPage(
        semantic: [FileEntrySnapshot],
        normal: [FileEntrySnapshot],
        semanticTotalCount: Int64? = nil,
        indexStatus: SemanticIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot.semanticSearchPage(
            semanticMatches: semantic.map { .semanticSearchPage(result: .semanticSearchPageResult(file: $0)) },
            normalMatches: normal.map {
                SemanticNormalSearchMatchSnapshot(result: .semanticSearchPageResult(file: $0), dedupedBySemantic: false)
            },
            semanticTotalCount: semanticTotalCount,
            indexStatus: indexStatus
        )
        return SearchResultPageSnapshot(
            query: semanticPage.query,
            totalCount: semanticPage.visibleTotalCount,
            results: semanticPage.visibleResults,
            diagnostics: [],
            indexStatus: SearchIndexStatusSnapshot(semanticStatus: indexStatus),
            semanticPage: semanticPage
        )
    }

    static func semanticSearchIndexBuildingPage() -> SearchResultPageSnapshot {
        semanticSearchSearchPage(semantic: [], normal: [], indexStatus: .building)
    }
}

private extension SemanticIndexBuildReportSnapshot {
    static func semanticSearchReadyReport() -> SemanticIndexBuildReportSnapshot {
        SemanticIndexBuildReportSnapshot(
            status: .ready,
            route: .local,
            totalCount: 1,
            processedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            privacySkippedCount: 0,
            providerName: "Local",
            callLogID: 308,
            fallbackReason: nil,
            message: nil
        )
    }
}
