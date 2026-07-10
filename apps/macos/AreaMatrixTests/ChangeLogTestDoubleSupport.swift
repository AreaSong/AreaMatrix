@testable import AreaMatrix
import XCTest

struct ChangeLogListRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

actor RecordingChangeLogLister: CoreChangeLogListing {
    private var results: [Swift.Result<[ChangeLogEntrySnapshot], Error>]
    private var requestsStorage: [ChangeLogListRequest] = []

    init(results: [Swift.Result<[ChangeLogEntrySnapshot], Error>]) {
        self.results = results
    }

    init(entries: [ChangeLogEntrySnapshot]) {
        results = [.success(entries)]
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requestsStorage.append(ChangeLogListRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [ChangeLogListRequest] {
        requestsStorage
    }

    func assertRecordedRequests(
        _ expectedRequests: [ChangeLogListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }
}
