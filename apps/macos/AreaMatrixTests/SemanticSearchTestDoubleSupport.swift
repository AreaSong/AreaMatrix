@testable import AreaMatrix

typealias SemanticSearchDetailer = DetailMetaImmediateDetailer

typealias SemanticSearchLister = NoopFileLister

typealias SemanticSearchNormalSearcher = RecordingSearchQuerying

typealias SemanticSearchPageDetailer = DetailMetaImmediateDetailer

typealias SemanticSearchPageLister = NoopFileLister

typealias SemanticSearchPageNormalSearcher = RecordingSearchQuerying

actor SemanticSearchSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot
    private var semanticSearchRequests: [SearchQueryRequestSnapshot] = []
    private var indexBuildRequests: [SearchQueryRequestSnapshot] = []

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        semanticSearchRequests.append(request)
        return page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        indexBuildRequests.append(request)
        return .semanticSearchReport()
    }

    func semanticRequests() -> [SearchQueryRequestSnapshot] {
        semanticSearchRequests
    }

    func indexRequests() -> [SearchQueryRequestSnapshot] {
        indexBuildRequests
    }
}

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
