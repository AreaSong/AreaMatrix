@testable import AreaMatrix
import Foundation
import XCTest

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
    func recoverOnStartup(repoPath _: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}

func s135MirrorDescription(of value: Any, depth: Int = 0) -> String {
    guard depth < 8 else { return "" }

    var lines: [String] = []
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        lines.append(s135MirrorDescription(of: child.value, depth: depth + 1))
    }
    return lines.joined(separator: "\n")
}

func makeS135TemporaryDirectory(prefix: String) throws -> URL {
    let name = "AreaMatrixS135Integration-\(prefix)-\(UUID().uuidString)"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum ImportBatchICloudErrorKindMapper {
    static func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        switch error {
        case .Conflict:
            .conflict
        case .FileNotFound:
            .fileNotFound
        case .PermissionDenied:
            .permissionDenied
        case .Db:
            .db
        case .Io:
            .io
        default:
            .internal
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func s135Conflict() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Path conflict.",
            severity: .medium,
            suggestedAction: "Rename the file first, then retry.",
            recoverability: .userActionRequired,
            rawContext: "S1-35 C1-10 safe target name"
        )
    }

    static func s135PermissionDenied() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "Target category is not writable.",
            severity: .high,
            suggestedAction: "Grant folder access in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: "S1-35 C1-24 preview_move_to_category permission"
        )
    }
}

actor MainLoadingRecordingStartupRecoverer: CoreStartupRecovering {
    private var results: [MainLoadingStartupRecoveryResult]
    private var paths: [String] = []

    init(result: MainLoadingStartupRecoveryResult) {
        results = [result]
    }

    init(results: [MainLoadingStartupRecoveryResult]) {
        self.results = results
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        let result = results.isEmpty ? .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 0,
            revertedStagingDbRows: 0,
            warnings: []
        )) : results.removeFirst()
        switch result {
        case let .success(report):
            return report
        case let .failure(error):
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
        case let .success(report):
            return report
        case let .failure(error):
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

    func latestScanSession(repoPath _: String) async throws -> ScanSessionSnapshot? {
        switch result {
        case let .success(session):
            return session
        case let .failure(error):
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

    func listTree(repoPath: String, locale _: String) async throws -> RepositoryTreeNodeSnapshot {
        requests.append(repoPath)
        let result = results.isEmpty ? .failure(CoreError.Internal(message: "missing tree result")) : results
            .removeFirst()
        switch result {
        case let .success(tree):
            return tree
        case let .failure(error):
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

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

struct MainLoadingStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
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
    for _ in 0 ..< 100 {
        if case let .mainLoading(state) = model.route, predicate(state) {
            return state
        }

        await Task.yield()
    }

    XCTFail("Timed out waiting for matching main loading state, got \(model.route)", file: file, line: line)
    return nil
}

struct S215CommandIndexRequest: Equatable {
    var repoPath: String
    var context: CommandIndexContext
}

actor S215CommandIndexStore: CoreCommandIndexing {
    enum Result { case success(CommandIndex), failure(Error) }

    private var results: [Result]
    private var requests: [S215CommandIndexRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex {
        requests.append(.init(repoPath: repoPath, context: context))
        guard !results.isEmpty else { return .s215Fixture() }
        switch results.removeFirst() {
        case let .success(index):
            return index
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [S215CommandIndexRequest] {
        requests
    }
}

actor S215CommandErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

struct S215SmartListRunRequest: Equatable {
    var repoPath: String
    var savedSearchID: Int64
    var limit: Int64
    var offset: Int64
}

actor S215SmartListRunner: CoreSearchQuerying {
    enum Result { case success(SearchResultPageSnapshot), failure(Error) }

    private var results: [Result]
    private var runRequests: [S215SmartListRunRequest] = []
    private var searchRequests: [SearchQueryRequestSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        searchRequests.append(request)
        throw CoreError.Internal(message: "search_files must not run S2-15 C2-04 Smart List execution")
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        runRequests.append(S215SmartListRunRequest(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ))
        guard !results.isEmpty else {
            return SearchResultPageSnapshot(query: "", totalCount: 0, results: [], diagnostics: [], indexStatus: .ready)
        }
        switch results.removeFirst() {
        case let .success(page):
            return page
        case let .failure(error):
            throw error
        }
    }

    func recordedRunRequests() -> [S215SmartListRunRequest] {
        runRequests
    }

    func recordedSearchRequests() -> [SearchQueryRequestSnapshot] {
        searchRequests
    }
}
