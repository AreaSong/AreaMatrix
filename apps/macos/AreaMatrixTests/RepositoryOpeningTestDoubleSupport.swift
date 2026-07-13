@testable import AreaMatrix
import XCTest

protocol RepoPathRequestRecording: Actor {
    var repoPathsForAssertions: [String] { get }
}

extension RepoPathRequestRecording {
    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(repoPathsForAssertions, expectedRepoPaths, file: file, line: line)
    }

    func assertNoRepoPathRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedRepoPaths([], file: file, line: line)
    }
}

protocol ConfiguredRepoPathRequestRecording: Actor {
    var configuredRepoPathsForAssertions: [String] { get }
}

extension ConfiguredRepoPathRequestRecording {
    func assertRequestedConfiguredRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(configuredRepoPathsForAssertions, expectedRepoPaths, file: file, line: line)
    }

    func assertNoConfiguredRepoPaths(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedConfiguredRepoPaths([], file: file, line: line)
    }
}

protocol EmptyRepoPathRequestRecording: Actor {
    var emptyRepoPathsForAssertions: [String] { get }
}

extension EmptyRepoPathRequestRecording {
    func assertRequestedEmptyRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(emptyRepoPathsForAssertions, expectedRepoPaths, file: file, line: line)
    }
}

protocol AdoptedRepoPathRequestRecording: Actor {
    var adoptedRepoPathsForAssertions: [String] { get }
}

extension AdoptedRepoPathRequestRecording {
    func assertRequestedAdoptedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(adoptedRepoPathsForAssertions, expectedRepoPaths, file: file, line: line)
    }
}

actor RecordingRepositoryOpener: CoreEmptyRepositoryOpening,
    RepoPathRequestRecording,
    ConfiguredRepoPathRequestRecording,
    EmptyRepoPathRequestRecording,
    AdoptedRepoPathRequestRecording {
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

    var repoPathsForAssertions: [String] {
        repoPaths
    }

    var configuredRepoPathsForAssertions: [String] {
        configuredRepoPaths
    }

    var emptyRepoPathsForAssertions: [String] {
        emptyRepoPaths
    }

    var adoptedRepoPathsForAssertions: [String] {
        adoptedRepoPaths
    }
}
