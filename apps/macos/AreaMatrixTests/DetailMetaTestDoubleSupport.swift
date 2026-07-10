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
    private var results: [Swift.Result<FileEntrySnapshot, Error>]
    private var requests: [FileDetailRequest] = []

    init() {
        results = []
    }

    init(results: [Swift.Result<FileEntrySnapshot, Error>]) {
        self.results = results
    }

    init(result: Swift.Result<FileEntrySnapshot, Error>) {
        results = [result]
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(FileDetailRequest(repoPath: repoPath, fileID: fileID))
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [FileDetailRequest] {
        requests
    }

    func assertRecordedRequests(
        _ expectedRequests: [FileDetailRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }

    func assertRecordedFileIDs(
        _ expectedFileIDs: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.fileID), expectedFileIDs, file: file, line: line)
    }
}

typealias DetailLogRequest = ChangeLogListRequest
typealias DetailLogRecordingLister = RecordingChangeLogLister
