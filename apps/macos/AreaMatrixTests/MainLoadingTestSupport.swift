import Foundation
import XCTest
@testable import AreaMatrix

enum MainLoadingScanSessionResult {
    case success(ScanSessionSnapshot?)
    case failure(Error)
}

enum MainLoadingTreeResult {
    case success(RepositoryTreeNodeSnapshot)
    case failure(Error)
}

enum MainLoadingStartupRecoveryResult {
    case success(RecoveryReportSnapshot)
    case failure(Error)
}

actor MainLoadingStaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}

actor MainLoadingRecordingStartupRecoverer: CoreStartupRecovering {
    private let result: MainLoadingStartupRecoveryResult
    private var paths: [String] = []

    init(result: MainLoadingStartupRecoveryResult) {
        self.result = result
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

actor MainLoadingPausingStartupRecoverer: CoreStartupRecovering {
    private let result: MainLoadingStartupRecoveryResult
    private var paths: [String] = []
    private var didStart = false
    private var didFinish = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(result: MainLoadingStartupRecoveryResult) {
        self.result = result
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        await pauseUntilFinished()
        switch result {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        }
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

actor MainLoadingStaticScanSessionReader: CoreScanSessionReading {
    private let result: MainLoadingScanSessionResult

    init(result: MainLoadingScanSessionResult) {
        self.result = result
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        switch result {
        case .success(let session):
            return session
        case .failure(let error):
            throw error
        }
    }
}

actor MainLoadingRecordingTreeLister: CoreRepositoryTreeListing {
    private var results: [MainLoadingTreeResult]
    private var requests: [String] = []

    init(result: MainLoadingTreeResult) {
        results = [result]
    }

    init(results: [MainLoadingTreeResult]) {
        self.results = results
    }

    func listTree(repoPath: String, locale: String) async throws -> RepositoryTreeNodeSnapshot {
        requests.append(repoPath)
        let result = results.isEmpty ? .failure(CoreError.Internal(message: "missing tree result")) : results.removeFirst()
        switch result {
        case .success(let tree):
            return tree
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        requests
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

actor MainLoadingFailingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let error: Error
    private var configuredPaths: [String] = []

    init(error: Error) {
        self.error = error
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        throw error
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredPaths
    }
}

final class MainLoadingRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

final class MainLoadingRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

struct MainLoadingStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

struct MainLoadingNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

@MainActor
func waitForMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState? {
    for _ in 0..<100 {
        if case .mainLoading(let state) = model.route, predicate(state) {
            return state
        }

        await Task.yield()
    }

    XCTFail("Timed out waiting for matching main loading state, got \(model.route)", file: file, line: line)
    return nil
}
