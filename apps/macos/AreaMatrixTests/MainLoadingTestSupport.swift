@testable import AreaMatrix
import Foundation
import XCTest

func makeChangeCategoryTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixChangeCategoryIntegration")
}

extension CoreErrorMappingSnapshot {
    static func changeCategoryConflict() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Path conflict.",
            severity: .medium,
            suggestedAction: "Rename the file first, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category resolve-name-conflict safe target name"
        )
    }

    static func changeCategoryPermissionDenied() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "Target category is not writable.",
            severity: .high,
            suggestedAction: "Grant folder access in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category move-to-category preview_move_to_category permission"
        )
    }
}

actor MainLoadingPausingStartupRecoverer: CoreStartupRecovering {
    private let result: Result<RecoveryReportSnapshot, Error>
    private var paths: [String] = []
    private var didStart = false
    private var didFinish = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(result: Result<RecoveryReportSnapshot, Error>) {
        self.result = result
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        await pauseUntilFinished()
        return try result.get()
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finishRecovery() {
        didFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func requestedRepoPaths() -> [String] {
        paths
    }

    private func pauseUntilFinished() async {
        didStart = true
        resumeStartContinuations()
        guard !didFinish else { return }
        await withCheckedContinuation { finishContinuation = $0 }
    }

    private func resumeStartContinuations() {
        let waiting = startContinuations
        startContinuations.removeAll()
        waiting.forEach { $0.resume() }
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
    private var didStart = false
    private var didFinish = false
    private var configuredPaths: [String] = []
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        await pauseUntilFinished()
        return opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finishOpen() {
        didFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredPaths
    }

    private func pauseUntilFinished() async {
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

@MainActor
func waitForMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState? {
    for _ in 0 ..< 100 {
        if case let .mainLoading(state) = model.route, predicate(state) {
            return state
        }

        await Task.yield()
    }

    XCTFail("Timed out waiting for matching main loading state, got \(model.route)", file: file, line: line)
    return nil
}
