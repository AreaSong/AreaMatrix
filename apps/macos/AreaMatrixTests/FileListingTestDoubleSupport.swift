@testable import AreaMatrix
import XCTest

struct NoopFileLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

struct StaticFileLister: CoreFileListing {
    private let files: [FileEntrySnapshot]

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        files
    }
}

struct FileListRequest: Equatable {
    var repoPath: String
    var filter: FileFilterSnapshot
}

actor RecordingFileLister: CoreFileListing {
    private var resultQueue: TestResultQueue<[FileEntrySnapshot]>
    private var requestsStorage: [FileListRequest] = []

    init(results: [Swift.Result<[FileEntrySnapshot], Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success([])
        }
    }

    init(files: [FileEntrySnapshot]) {
        resultQueue = TestResultQueue(results: [.success(files)]) {
            .success([])
        }
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requestsStorage.append(FileListRequest(repoPath: repoPath, filter: filter))
        return try resultQueue.next()
    }

    func assertFileListRequests(
        _ expectedRequests: [FileListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertNoFileListRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFileListRequests([], file: file, line: line)
    }

    func assertFileListRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.count, expectedCount, file: file, line: line)
    }

    func assertLastFileListRequest(
        _ expectedRequest: FileListRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.last, expectedRequest, file: file, line: line)
    }

    func assertFileListFilters(
        _ expectedFilters: [FileFilterSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.map(\.filter), expectedFilters, file: file, line: line)
    }
}
