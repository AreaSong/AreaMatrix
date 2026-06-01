@testable import AreaMatrix
import XCTest

final class S308PageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS308PresentationKeepsSemanticAndNormalGroupsWithDuplicateExpansion() {
        let semanticFile = FileEntrySnapshot.s308PageFile(id: 8701, name: "invoice_0426.pdf")
        let duplicateFile = FileEntrySnapshot.s308PageFile(id: 8702, name: "invoice_notes.txt")
        let normalOnlyFile = FileEntrySnapshot.s308PageFile(id: 8703, name: "payment_notes.txt")
        let page = SemanticSearchResultPageSnapshot.s308Page(
            semanticMatches: [
                .s308Page(result: .s308PageResult(file: semanticFile), alsoMatchedNormalSearch: true)
            ],
            normalMatches: [
                SemanticNormalSearchMatchSnapshot(
                    result: .s308PageResult(file: duplicateFile, snippet: "filename contains invoice"),
                    dedupedBySemantic: true
                ),
                SemanticNormalSearchMatchSnapshot(
                    result: .s308PageResult(file: normalOnlyFile, snippet: "note mentions payment"),
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
    func testS308LoadMoreSemanticMergesOnlyRequestedGroup() async {
        let tree = RepositoryTreeNodeSnapshot.s308Tree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let firstSemantic = FileEntrySnapshot.s308PageFile(id: 8704, name: "invoice_a.pdf")
        let nextSemantic = FileEntrySnapshot.s308PageFile(id: 8705, name: "invoice_b.pdf")
        let normalFile = FileEntrySnapshot.s308PageFile(id: 8706, name: "invoice_notes.txt")
        let searcher = S308PagedSemanticSearcher(pages: [
            .s308SearchPage(semantic: [firstSemantic], normal: [normalFile], semanticTotalCount: 2),
            .s308SearchPage(semantic: [nextSemantic], normal: [], semanticTotalCount: 2)
        ])
        let model = MainFileListModel(
            opening: .s308PageOpening(tree: tree),
            fileLister: S308PageLister(),
            fileDetailer: S308PageDetailer(file: firstSemantic),
            searchQuerying: S308PageNormalSearcher(),
            semanticSearching: searcher,
            errorMapper: S308PageErrorMapper()
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
    func testS308IndexLifecycleCancelsActiveCoreBuildAndKeepsLaterReportOutOfPage() async {
        let tree = RepositoryTreeNodeSnapshot.s308Tree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let searcher = S308DelayedSemanticSearcher(page: .s308IndexBuildingPage())
        let model = MainFileListModel(
            opening: .s308PageOpening(tree: tree),
            fileLister: S308PageLister(),
            fileDetailer: S308PageDetailer(file: .s308PageFile(id: 8707)),
            searchQuerying: S308PageNormalSearcher(),
            semanticSearching: searcher,
            errorMapper: S308PageErrorMapper()
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
        XCTAssertEqual(pauseError.rawContext, "S3-08 pause index build missing Core API")
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
    func testS310C308SemanticFallbackUsesSemanticSearchOutputWithoutWaitingForC310Reader() {
        let page = SemanticSearchResultPageSnapshot.s308Page(
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
        let body = s135MirrorDescription(of: region.body)

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
    func testS310C308ProviderFallbackKeepsNormalSearchAndCallLogActions() {
        let page = SemanticSearchResultPageSnapshot.s308Page(
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
        let body = s135MirrorDescription(of: region.body)

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

private actor S308PagedSemanticSearcher: CoreSemanticSearching {
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
        .s308ReadyReport()
    }

    func requests() -> [SearchQueryRequestSnapshot] {
        recordedRequests
    }
}

private actor S308DelayedSemanticSearcher: CoreSemanticSearching {
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
        return .s308ReadyReport()
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

private actor S308PageNormalSearcher: CoreSearchQuerying {
    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(query: request.query, totalCount: 0, results: [], diagnostics: [], indexStatus: .ready)
    }
}

private actor S308PageLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor S308PageDetailer: CoreFileDetailing {
    private let file: FileEntrySnapshot

    init(file: FileEntrySnapshot) {
        self.file = file
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        file
    }
}

private struct S308PageErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "S3-08 semantic page failed",
            severity: .medium,
            suggestedAction: "Retry the failed semantic group.",
            recoverability: .retryable,
            rawContext: "S3-08"
        )
    }
}

private extension FileEntrySnapshot {
    static func s308PageFile(id: Int64, name: String = "invoice.pdf") -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "finance/invoices/\(name)",
            originalName: name,
            currentName: name,
            category: "finance",
            sizeBytes: 128,
            hashSha256: "s308-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension SearchFileResultSnapshot {
    static func s308PageResult(file: FileEntrySnapshot,
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
    static func s308PageOpening(tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .s308PageConfig(), tree: tree, currentCategoryFiles: [])
    }
}

private extension RepoConfigSnapshot {
    static func s308PageConfig() -> RepoConfigSnapshot {
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
    static func s308Tree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [.s308FinanceNode()]
        )
    }

    static func s308FinanceNode() -> RepositoryTreeNodeSnapshot {
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
    static func s308Page(
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
    static func s308Page(
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
    static func s308SearchPage(
        semantic: [FileEntrySnapshot],
        normal: [FileEntrySnapshot],
        semanticTotalCount: Int64? = nil,
        indexStatus: SemanticIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot.s308Page(
            semanticMatches: semantic.map { .s308Page(result: .s308PageResult(file: $0)) },
            normalMatches: normal.map {
                SemanticNormalSearchMatchSnapshot(result: .s308PageResult(file: $0), dedupedBySemantic: false)
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

    static func s308IndexBuildingPage() -> SearchResultPageSnapshot {
        s308SearchPage(semantic: [], normal: [], indexStatus: .building)
    }
}

private extension SemanticIndexBuildReportSnapshot {
    static func s308ReadyReport() -> SemanticIndexBuildReportSnapshot {
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
