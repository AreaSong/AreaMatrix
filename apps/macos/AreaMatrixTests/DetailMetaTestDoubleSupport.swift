@testable import AreaMatrix
import XCTest

actor DetailMetaImmediateDetailer: CoreFileDetailing {
    private let result: Swift.Result<FileEntrySnapshot, Error>

    init(result: Swift.Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    init(file: FileEntrySnapshot) {
        result = .success(file)
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        try result.get()
    }
}

struct FileDetailRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

actor RecordingFileDetailer: CoreFileDetailing {
    private var resultQueue: TestResultQueue<FileEntrySnapshot>
    private var requestLog = TestRequestLog<FileDetailRequest>()

    init() {
        resultQueue = TestResultQueue(results: []) {
            .failure(CoreError.FileNotFound(path: ""))
        }
    }

    init(results: [Swift.Result<FileEntrySnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .failure(CoreError.FileNotFound(path: ""))
        }
    }

    init(result: Swift.Result<FileEntrySnapshot, Error>) {
        resultQueue = TestResultQueue(results: [result]) {
            .failure(CoreError.FileNotFound(path: ""))
        }
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requestLog.append(FileDetailRequest(repoPath: repoPath, fileID: fileID))
        return try resultQueue.next {
            .failure(CoreError.FileNotFound(path: "\(fileID)"))
        }
    }

    func assertFileDetailRequests(
        _ expectedRequests: [FileDetailRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertNoFileDetailRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFileDetailRequests([], file: file, line: line)
    }

    func assertFileDetailRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestLog.requests.count, expectedCount, file: file, line: line)
    }

    func assertRequestedFileIDs(
        _ expectedFileIDs: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestLog.requests.map(\.fileID), expectedFileIDs, file: file, line: line)
    }
}

typealias DetailLogRequest = ChangeLogListRequest
typealias DetailLogRecordingLister = RecordingChangeLogLister
