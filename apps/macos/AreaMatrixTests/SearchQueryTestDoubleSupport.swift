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

func assertSmartListRunRequests(
    _ requests: [SmartListRunRequestRecord],
    repoPath: String = "/tmp/repo",
    savedSearchID: Int64,
    count: Int = 1,
    limit: Int64 = 50,
    offset: Int64 = 0,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        requests,
        Array(repeating: .testFixture(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ), count: count),
        file: file,
        line: line
    )
}

actor RecordingSearchQuerying: CoreSearchQuerying {
    private var results: [Swift.Result<SearchResultPageSnapshot, Error>]
    private var requestsStorage: [SearchQueryRequestRecord] = []
    private var smartListRequestsStorage: [SmartListRunRequestRecord] = []

    init(results: [Swift.Result<SearchResultPageSnapshot, Error>] = []) {
        self.results = results
    }

    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        requestsStorage.append(SearchQueryRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else {
            return emptySearchResultPage(query: request.query)
        }

        return try results.removeFirst().get()
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
        guard !results.isEmpty else {
            return emptySearchResultPage(query: "")
        }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [SearchQueryRequestRecord] {
        requestsStorage
    }

    func recordedSmartListRequests() -> [SmartListRunRequestRecord] {
        smartListRequestsStorage
    }

    func requests() -> [SearchQueryRequestSnapshot] {
        requestsStorage.map(\.request)
    }

    func assertRequests(
        _ expectedRequests: [SearchQueryRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.map(\.request), expectedRequests, file: file, line: line)
    }

    func assertRecordedQueries(
        _ expectedQueries: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.map(\.request.query), expectedQueries, file: file, line: line)
    }
}

actor SmartListOnlyRecordingSearchQuerying: CoreSearchQuerying {
    private var results: [Swift.Result<SearchResultPageSnapshot, Error>]
    private var runRequestsStorage: [SmartListRunRequestRecord] = []
    private var searchRequestsStorage: [SearchQueryRequestSnapshot] = []

    init(results: [Swift.Result<SearchResultPageSnapshot, Error>] = []) {
        self.results = results
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
        guard !results.isEmpty else {
            return emptySearchResultPage(query: "")
        }

        return try results.removeFirst().get()
    }

    func recordedRunRequests() -> [SmartListRunRequestRecord] {
        runRequestsStorage
    }

    func recordedSearchRequests() -> [SearchQueryRequestSnapshot] {
        searchRequestsStorage
    }

    func assertSearchRequests(
        _ expectedRequests: [SearchQueryRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(searchRequestsStorage, expectedRequests, file: file, line: line)
    }
}

private func emptySearchResultPage(query: String) -> SearchResultPageSnapshot {
    .testFixture(query: query)
}
