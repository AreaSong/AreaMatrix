@testable import AreaMatrix
import XCTest

struct ChangeLogListRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

actor RecordingChangeLogLister: CoreChangeLogListing {
    private var resultQueue: TestResultQueue<[ChangeLogEntrySnapshot]>
    private var requestsStorage: [ChangeLogListRequest] = []

    init(results: [Swift.Result<[ChangeLogEntrySnapshot], Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success([])
        }
    }

    init(entries: [ChangeLogEntrySnapshot]) {
        resultQueue = TestResultQueue(results: [.success(entries)]) {
            .success([])
        }
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requestsStorage.append(ChangeLogListRequest(repoPath: repoPath, filter: filter))
        return try resultQueue.next()
    }

    func assertChangeLogListRequests(
        _ expectedRequests: [ChangeLogListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertNoChangeLogListRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertChangeLogListRequests([], file: file, line: line)
    }
}
