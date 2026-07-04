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
        return SemanticIndexBuildReportSnapshot(
            status: .ready,
            route: .remote,
            totalCount: 1,
            processedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            privacySkippedCount: 0,
            providerName: "OpenAI",
            callLogID: 680,
            fallbackReason: nil,
            message: nil
        )
    }

    func indexRequests() -> [SearchQueryRequestSnapshot] {
        recordedIndexRequests
    }
}
