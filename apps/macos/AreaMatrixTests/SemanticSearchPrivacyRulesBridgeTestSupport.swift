@testable import AreaMatrix
import XCTest

actor SemanticSearchPrivacySemanticSearcher: CoreSemanticSearching {
    private var indexRequestLog = TestRequestLog<SearchQueryRequestSnapshot>()

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
        indexRequestLog.append(request)
        return .testFixture(
            route: .remote,
            providerName: "OpenAI",
            callLogID: 680
        )
    }

    func assertIndexRequests(
        _ expectedRequests: [SearchQueryRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        indexRequestLog.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertNoIndexRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        indexRequestLog.assertNoRequests(file: file, line: line)
    }
}
