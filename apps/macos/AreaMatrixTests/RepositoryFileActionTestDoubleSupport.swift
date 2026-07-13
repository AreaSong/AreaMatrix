@testable import AreaMatrix
import XCTest

@MainActor
final class RecordingRepositoryFinderOpener: RepositoryFinderOpening {
    private let result: Result<Void, Error>
    private var repoPaths: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openRepositoryInFinder(repoPath: String) throws {
        repoPaths.append(repoPath)
        try result.get()
    }

    func assertRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(repoPaths, expectedRepoPaths, file: file, line: line)
    }
}

@MainActor
final class RecordingRepositoryFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: Result<Void, Error>
    private var requests: [Request] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }

    func assertRevealRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }
}

@MainActor
final class RecordingRepositoryFileOpener: RepositoryFileOpening {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: Result<Void, Error>
    private var requests: [Request] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }

    func assertOpenFileRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }
}
