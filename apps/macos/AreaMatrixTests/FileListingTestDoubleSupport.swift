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
    private var results: [Swift.Result<[FileEntrySnapshot], Error>]
    private var requestsStorage: [FileListRequest] = []

    init(results: [Swift.Result<[FileEntrySnapshot], Error>]) {
        self.results = results
    }

    init(files: [FileEntrySnapshot]) {
        results = [.success(files)]
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requestsStorage.append(FileListRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [FileFilterSnapshot] {
        requestsStorage.map(\.filter)
    }

    func assertRecordedRequests(
        _ expectedRequests: [FileFilterSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.map(\.filter), expectedRequests, file: file, line: line)
    }

    func recordedListRequests() -> [FileListRequest] {
        requestsStorage
    }

    func assertRecordedListRequests(
        _ expectedRequests: [FileListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }
}
