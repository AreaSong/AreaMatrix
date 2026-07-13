@testable import AreaMatrix
import XCTest

actor RecordingRepositoryPathValidator: CoreRepositoryPathValidating,
    CoreInitializedRepositoryPathValidating,
    RepoPathRequestRecording {
    typealias ValidationResult = Swift.Result<RepoPathValidationSnapshot, Error>

    private var resultQueue: TestResultQueue<RepoPathValidationSnapshot>
    private var requestLog = TestRequestLog<String>()

    init(result: ValidationResult) {
        resultQueue = TestResultQueue(result: result, missingResult: Self.missingResult)
    }

    init(validation: RepoPathValidationSnapshot) {
        resultQueue = TestResultQueue(result: .success(validation), missingResult: Self.missingResult)
    }

    init(validations: [RepoPathValidationSnapshot]) {
        resultQueue = TestResultQueue(results: validations.map { .success($0) }, missingResult: Self.missingResult)
    }

    init(results: [ValidationResult]) {
        resultQueue = TestResultQueue(results: results, missingResult: Self.missingResult)
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        requestLog.append(repoPath)
        return try nextResult()
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        requestLog.append(repoPath)
        return try nextResult()
    }

    var repoPathsForAssertions: [String] {
        requestLog.requests
    }

    private func nextResult() throws -> RepoPathValidationSnapshot {
        try resultQueue.next()
    }

    private static func missingResult() -> ValidationResult {
        .failure(CoreError.Config(reason: "missing validation fixture"))
    }
}

typealias StaticRepositoryPathValidator = RecordingRepositoryPathValidator
