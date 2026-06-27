@testable import AreaMatrix

actor SemanticSearchPagedSemanticSearcher: CoreSemanticSearching {
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

actor SemanticSearchDelayedSemanticSearcher: CoreSemanticSearching {
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

actor SemanticSearchPageNormalSearcher: CoreSearchQuerying {
    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(query: request.query, totalCount: 0, results: [], diagnostics: [], indexStatus: .ready)
    }
}

actor SemanticSearchPageLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

actor SemanticSearchPageDetailer: CoreFileDetailing {
    private let file: FileEntrySnapshot

    init(file: FileEntrySnapshot) {
        self.file = file
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        file
    }
}

struct SemanticSearchPageErrorMapper: CoreErrorMapping {
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

extension FileEntrySnapshot {
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

extension SearchFileResultSnapshot {
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

extension RepositoryOpeningResult {
    static func semanticSearchPageOpening(tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .semanticSearchPageConfig(), tree: tree, currentCategoryFiles: [])
    }
}

extension RepoConfigSnapshot {
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

extension RepositoryTreeNodeSnapshot {
    static func semanticSearchPageTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [.semanticSearchPageFinanceNode()]
        )
    }

    static func semanticSearchPageFinanceNode() -> RepositoryTreeNodeSnapshot {
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

extension SemanticSearchMatchSnapshot {
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

extension SemanticSearchResultPageSnapshot {
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

extension SearchResultPageSnapshot {
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

extension SemanticIndexBuildReportSnapshot {
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
