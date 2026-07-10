@testable import AreaMatrix
import XCTest

actor RecordingRepositoryPathValidator: CoreRepositoryPathValidating, CoreInitializedRepositoryPathValidating {
    typealias ValidationResult = Swift.Result<RepoPathValidationSnapshot, Error>

    private let repeatingResult: ValidationResult?
    private var queuedResults: [ValidationResult]
    private var allRequests: [String] = []
    private var repoPathRequests: [String] = []
    private var initializedRepoPathRequests: [String] = []

    init(result: ValidationResult) {
        repeatingResult = result
        queuedResults = []
    }

    init(validation: RepoPathValidationSnapshot) {
        repeatingResult = .success(validation)
        queuedResults = []
    }

    init(validations: [RepoPathValidationSnapshot]) {
        repeatingResult = nil
        queuedResults = validations.map { .success($0) }
    }

    init(results: [ValidationResult]) {
        repeatingResult = nil
        queuedResults = results
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        allRequests.append(repoPath)
        repoPathRequests.append(repoPath)
        return try nextResult()
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        allRequests.append(repoPath)
        initializedRepoPathRequests.append(repoPath)
        return try nextResult()
    }

    func requestedRepoPaths() -> [String] {
        allRequests
    }

    func requestedPaths() -> [String] {
        requestedRepoPaths()
    }

    func recordedRequests() -> [String] {
        requestedRepoPaths()
    }

    func assertRequestedRepoPaths(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestedRepoPaths(), expectedRequests, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestedRepoPaths(), [], file: file, line: line)
    }

    func assertRecordedRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedRepoPaths(expectedRequests, file: file, line: line)
    }

    func requestedValidatedRepoPaths() -> [String] {
        repoPathRequests
    }

    func requestedInitializedRepoPaths() -> [String] {
        initializedRepoPathRequests
    }

    private func nextResult() throws -> RepoPathValidationSnapshot {
        if let repeatingResult {
            return try repeatingResult.get()
        }
        guard !queuedResults.isEmpty else {
            throw CoreError.Config(reason: "missing validation fixture")
        }

        return try queuedResults.removeFirst().get()
    }
}

typealias StaticRepositoryPathValidator = RecordingRepositoryPathValidator
