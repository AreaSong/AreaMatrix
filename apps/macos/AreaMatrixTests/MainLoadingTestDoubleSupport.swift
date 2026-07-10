@testable import AreaMatrix
import XCTest

actor MainLoadingPausingStartupRecoverer: CoreStartupRecovering {
    private let result: Result<RecoveryReportSnapshot, Error>
    private let pauseGate = MainLoadingPauseGate()
    private var paths: [String] = []

    init(result: Result<RecoveryReportSnapshot, Error>) {
        self.result = result
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        await pauseGate.pauseUntilFinished()
        return try result.get()
    }

    func waitUntilStarted() async {
        await pauseGate.waitUntilStarted()
    }

    func finishRecovery() async {
        await pauseGate.finish()
    }

    func requestedRepoPaths() -> [String] {
        paths
    }

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(paths, expectedRepoPaths, file: file, line: line)
    }
}

actor MainLoadingRecordingTreeLister: CoreRepositoryTreeListing {
    private var results: [Result<RepositoryTreeNodeSnapshot, Error>]
    private var requests: [String] = []

    init(result: Result<RepositoryTreeNodeSnapshot, Error>) {
        results = [result]
    }

    init(results: [Result<RepositoryTreeNodeSnapshot, Error>]) {
        self.results = results
    }

    func listTree(repoPath: String, locale _: String) async throws -> RepositoryTreeNodeSnapshot {
        requests.append(repoPath)
        let result = results.isEmpty ? Result.failure(CoreError.Internal(message: "missing tree result")) : results
            .removeFirst()
        return try result.get()
    }

    func requestedRepoPaths() -> [String] {
        requests
    }

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRepoPaths, file: file, line: line)
    }
}

actor MainLoadingInitializedPathValidator: CoreRepositoryPathValidating, CoreInitializedRepositoryPathValidating {
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

actor MainLoadingPausingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let opening: RepositoryOpeningResult
    private let pauseGate = MainLoadingPauseGate()
    private var configuredPaths: [String] = []

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        await pauseGate.pauseUntilFinished()
        return opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func waitUntilStarted() async {
        await pauseGate.waitUntilStarted()
    }

    func finishOpen() async {
        await pauseGate.finish()
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredPaths
    }

    func assertRequestedConfiguredRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(configuredPaths, expectedRepoPaths, file: file, line: line)
    }

    func assertNoConfiguredRepoPaths(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedConfiguredRepoPaths([], file: file, line: line)
    }
}

private actor MainLoadingPauseGate {
    private var didStart = false
    private var didFinish = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finish() {
        didFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func pauseUntilFinished() async {
        didStart = true
        resumeStartContinuations()
        guard !didFinish else { return }
        await withCheckedContinuation { finishContinuation = $0 }
    }

    private func resumeStartContinuations() {
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

typealias MainLoadingFailingRepositoryOpener = RecordingRepositoryOpener

typealias MainLoadingRecordingSettingsWriter = RecordingAppSettingsWriter
