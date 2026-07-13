@testable import AreaMatrix
import XCTest

struct SearchQueryRequestRecord: Equatable {
    var repoPath: String
    var request: SearchQueryRequestSnapshot
}

struct SmartListRunRequestRecord: Equatable {
    var repoPath: String
    var savedSearchID: Int64
    var limit: Int64
    var offset: Int64
}

extension SmartListRunRequestRecord {
    static func testFixture(
        repoPath: String = "/tmp/repo",
        savedSearchID: Int64,
        limit: Int64 = 50,
        offset: Int64 = 0
    ) -> SmartListRunRequestRecord {
        SmartListRunRequestRecord(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        )
    }
}

private func expectedSmartListRunRequests(
    repoPath: String = "/tmp/repo",
    savedSearchID: Int64,
    count: Int = 1,
    limit: Int64 = 50,
    offset: Int64 = 0
) -> [SmartListRunRequestRecord] {
    Array(repeating: .testFixture(
        repoPath: repoPath,
        savedSearchID: savedSearchID,
        limit: limit,
        offset: offset
    ), count: count)
}

actor RecordingSearchQuerying: CoreSearchQuerying, SearchQueryRequestRecording, SmartListRunRequestRecording {
    private var resultQueue: TestResultQueue<SearchResultPageSnapshot>
    private var requestsStorage: [SearchQueryRequestRecord] = []
    private var smartListRequestsStorage: [SmartListRunRequestRecord] = []

    init(results: [Swift.Result<SearchResultPageSnapshot, Error>] = []) {
        resultQueue = TestResultQueue(results: results) {
            .success(emptySearchResultPage(query: ""))
        }
    }

    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        requestsStorage.append(SearchQueryRequestRecord(repoPath: repoPath, request: request))
        return try resultQueue.next {
            .success(emptySearchResultPage(query: request.query))
        }
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        smartListRequestsStorage.append(SmartListRunRequestRecord(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ))
        return try resultQueue.next()
    }

    var searchQueryRequestsForAssertions: [SearchQueryRequestRecord] {
        requestsStorage
    }

    var smartListRunRequestsForAssertions: [SmartListRunRequestRecord] {
        smartListRequestsStorage
    }

    func assertRequestFilters(
        _ expectedFilters: [SearchFilterStateSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSearchRequestFilters(expectedFilters, file: file, line: line)
    }
}

actor SmartListOnlyRecordingSearchQuerying: CoreSearchQuerying, SmartListRunRequestRecording {
    private var resultQueue: TestResultQueue<SearchResultPageSnapshot>
    private var runRequestsStorage: [SmartListRunRequestRecord] = []
    private var searchRequestsStorage: [SearchQueryRequestSnapshot] = []

    init(results: [Swift.Result<SearchResultPageSnapshot, Error>] = []) {
        resultQueue = TestResultQueue(results: results) {
            .success(emptySearchResultPage(query: ""))
        }
    }

    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        searchRequestsStorage.append(request)
        throw CoreError.Internal(message: "search_files must not run smart-list-only test searcher")
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        runRequestsStorage.append(SmartListRunRequestRecord(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ))
        return try resultQueue.next()
    }

    var smartListRunRequestsForAssertions: [SmartListRunRequestRecord] {
        runRequestsStorage
    }

    func assertSearchRequests(
        _ expectedRequests: [SearchQueryRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(searchRequestsStorage, expectedRequests, file: file, line: line)
    }
}

protocol SearchQueryRequestRecording: Actor {
    var searchQueryRequestsForAssertions: [SearchQueryRequestRecord] { get }
}

extension SearchQueryRequestRecording {
    func assertSearchRequests(
        _ expectedRequests: [SearchQueryRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(searchQueryRequestsForAssertions.map(\.request), expectedRequests, file: file, line: line)
    }

    func assertSearchRequestFilters(
        _ expectedFilters: [SearchFilterStateSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(searchQueryRequestsForAssertions.map(\.request.filters), expectedFilters, file: file, line: line)
    }

    func assertSearchRequestQueries(
        _ expectedQueries: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(searchQueryRequestsForAssertions.map(\.request.query), expectedQueries, file: file, line: line)
    }
}

protocol SmartListRunRequestRecording: Actor {
    var smartListRunRequestsForAssertions: [SmartListRunRequestRecord] { get }
}

extension SmartListRunRequestRecording {
    func assertSmartListRunRequests(
        repoPath: String = "/tmp/repo",
        savedSearchID: Int64,
        count: Int = 1,
        limit: Int64 = 50,
        offset: Int64 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            smartListRunRequestsForAssertions,
            expectedSmartListRunRequests(
                repoPath: repoPath,
                savedSearchID: savedSearchID,
                count: count,
                limit: limit,
                offset: offset
            ),
            file: file,
            line: line
        )
    }
}

private func emptySearchResultPage(query: String) -> SearchResultPageSnapshot {
    .testFixture(query: query)
}
