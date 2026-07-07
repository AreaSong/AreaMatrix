@testable import AreaMatrix

actor SemanticSearchPrivacySemanticSearcher: CoreSemanticSearching {
    private var recordedIndexRequests: [SearchQueryRequestSnapshot] = []

    func semanticSearch(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SearchResultPageSnapshot {
        throw CoreError.Internal(message: "semantic-search ai-privacy-rules-core test does not execute semantic search")
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        recordedIndexRequests.append(request)
        return .testFixture(
            route: .remote,
            providerName: "OpenAI",
            callLogID: 680
        )
    }

    func indexRequests() -> [SearchQueryRequestSnapshot] {
        recordedIndexRequests
    }
}
