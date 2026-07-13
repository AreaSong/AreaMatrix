@testable import AreaMatrix
import XCTest

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

    func assertSemanticRequest(
        at index: Int = 0,
        query expectedQuery: String? = nil,
        mode expectedMode: SearchModeSnapshot? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = semanticRequest(at: index, file: file, line: line) else { return }

        if let expectedQuery {
            XCTAssertEqual(request.query, expectedQuery, file: file, line: line)
        }
        if let expectedMode {
            XCTAssertEqual(request.mode, expectedMode, file: file, line: line)
        }
    }

    func assertNoIndexRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(indexBuildRequests, [], file: file, line: line)
    }

    func assertIndexRequests(
        queries expectedQueries: [String]? = nil,
        modes expectedModes: [SearchModeSnapshot]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let expectedQueries {
            XCTAssertEqual(indexBuildRequests.map(\.query), expectedQueries, file: file, line: line)
        }
        if let expectedModes {
            XCTAssertEqual(indexBuildRequests.map(\.mode), expectedModes, file: file, line: line)
        }
    }

    private func semanticRequest(
        at index: Int,
        file: StaticString,
        line: UInt
    ) -> SearchQueryRequestSnapshot? {
        guard semanticSearchRequests.indices.contains(index) else {
            XCTFail("Expected semantic search request at index \(index).", file: file, line: line)
            return nil
        }

        return semanticSearchRequests[index]
    }
}

actor SemanticSearchPagedSemanticSearcher: CoreSemanticSearching {
    private var pageQueue: TestResultQueue<SearchResultPageSnapshot>
    private var recordedRequests: [SearchQueryRequestSnapshot] = []

    init(pages: [SearchResultPageSnapshot]) {
        pageQueue = TestResultQueue(results: pages.map { .success($0) }) {
            .failure(CoreError.Internal(message: "missing semantic search page"))
        }
    }

    func semanticSearch(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SearchResultPageSnapshot {
        recordedRequests.append(request)
        return try pageQueue.next()
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        .semanticSearchReadyReport()
    }

    func assertRequestOffsets(
        _ expectedOffsets: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests.map(\.offset), expectedOffsets, file: file, line: line)
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
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for semantic index build start" },
            value: {
                buildStarted && continuation != nil ? true : nil
            }
        )
    }

    func finishBuild() {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func assertObservedCancellationCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(cancellationCount, expectedCount, file: file, line: line)
    }

    private func recordCancellation() {
        cancellationCount += 1
    }
}
