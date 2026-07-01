@testable import AreaMatrix

typealias SemanticSearchDetailer = DetailMetaImmediateDetailer

typealias SemanticSearchLister = NoopFileLister

typealias SemanticSearchNormalSearcher = RecordingSearchQuerying

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
