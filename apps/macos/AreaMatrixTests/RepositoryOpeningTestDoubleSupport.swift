@testable import AreaMatrix
import XCTest

actor RecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: Swift.Result<RepositoryOpeningResult, Error>
    private var repoPaths: [String] = []
    private var configuredRepoPaths: [String] = []
    private var emptyRepoPaths: [String] = []
    private var adoptedRepoPaths: [String] = []

    init(result: Swift.Result<RepositoryOpeningResult, Error>) {
        self.result = result
    }

    init(opening: RepositoryOpeningResult) {
        result = .success(opening)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        configuredRepoPaths.append(repoPath)
        return try result.get()
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        emptyRepoPaths.append(repoPath)
        return try result.get()
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        adoptedRepoPaths.append(repoPath)
        return try result.get()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(repoPaths, expectedRepoPaths, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedRepoPaths([], file: file, line: line)
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredRepoPaths
    }

    func assertRequestedConfiguredRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(configuredRepoPaths, expectedRepoPaths, file: file, line: line)
    }

    func assertNoConfiguredRepoPaths(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(configuredRepoPaths, [], file: file, line: line)
    }

    func requestedEmptyRepoPaths() -> [String] {
        emptyRepoPaths
    }

    func requestedAdoptedRepoPaths() -> [String] {
        adoptedRepoPaths
    }
}
