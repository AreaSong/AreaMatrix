@testable import AreaMatrix

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
}

private func emptySearchResultPage(query: String) -> SearchResultPageSnapshot {
    SearchResultPageSnapshot(query: query, totalCount: 0, results: [], diagnostics: [], indexStatus: .ready)
}
