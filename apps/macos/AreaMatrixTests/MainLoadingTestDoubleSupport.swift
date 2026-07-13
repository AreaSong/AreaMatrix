@testable import AreaMatrix
import XCTest

actor MainLoadingPausingStartupRecoverer: CoreStartupRecovering, RepoPathRequestRecording {
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

    var repoPathsForAssertions: [String] {
        paths
    }
}

actor MainLoadingRecordingTreeLister: CoreRepositoryTreeListing, RepoPathRequestRecording {
    private var resultQueue: TestResultQueue<RepositoryTreeNodeSnapshot>
    private var requests: [String] = []

    init(result: Result<RepositoryTreeNodeSnapshot, Error>) {
        resultQueue = TestResultQueue(results: [result]) {
            .failure(CoreError.Internal(message: "missing tree result"))
        }
    }

    init(results: [Result<RepositoryTreeNodeSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .failure(CoreError.Internal(message: "missing tree result"))
        }
    }

    func listTree(repoPath: String, locale _: String) async throws -> RepositoryTreeNodeSnapshot {
        requests.append(repoPath)
        return try resultQueue.next()
    }

    var repoPathsForAssertions: [String] {
        requests
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

actor MainLoadingPausingRepositoryOpener: CoreEmptyRepositoryOpening, ConfiguredRepoPathRequestRecording {
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

    var configuredRepoPathsForAssertions: [String] {
        configuredPaths
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
