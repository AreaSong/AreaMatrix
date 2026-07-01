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

typealias SemanticSearchPageNormalSearcher = RecordingSearchQuerying

typealias SemanticSearchPageLister = NoopFileLister

typealias SemanticSearchPageDetailer = DetailMetaImmediateDetailer
