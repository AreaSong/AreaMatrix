@testable import AreaMatrix

struct RepositoryInitializationRequest: Equatable {
    var repoPath: String
    var mode: RepoInitModeSnapshot
}

actor RecordingRepositoryInitializer: CoreRepositoryInitializing {
    typealias InitializationResult = Swift.Result<Void, Error>

    private var createResults: [InitializationResult]
    private var adoptResults: [InitializationResult]
    private let repeatsSingleResult: Bool
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []
    private var requests: [RepositoryInitializationRequest] = []

    init(result: InitializationResult = .success(())) {
        createResults = [result]
        adoptResults = [result]
        repeatsSingleResult = true
    }

    init(error: Error) {
        createResults = [.failure(error)]
        adoptResults = [.failure(error)]
        repeatsSingleResult = true
    }

    init(firstError: Error) {
        createResults = [.failure(firstError), .success(())]
        adoptResults = [.failure(firstError), .success(())]
        repeatsSingleResult = false
    }

    init(createResults: [InitializationResult], adoptResults: [InitializationResult]) {
        self.createResults = createResults
        self.adoptResults = adoptResults
        repeatsSingleResult = false
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        requests.append(RepositoryInitializationRequest(repoPath: repoPath, mode: .createEmpty))
        try nextResult(from: &createResults).get()
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        requests.append(RepositoryInitializationRequest(repoPath: repoPath, mode: .adoptExisting))
        try nextResult(from: &adoptResults).get()
    }

    func createdRepoPaths() -> [String] {
        createdPaths
    }

    func adoptedRepoPaths() -> [String] {
        adoptedPaths
    }

    func adoptRequests() -> [String] {
        adoptedPaths
    }

    func recordedRequests() -> [RepositoryInitializationRequest] {
        requests
    }

    private func nextResult(from results: inout [InitializationResult]) -> InitializationResult {
        if repeatsSingleResult {
            return results.first ?? .success(())
        }

        return results.isEmpty ? .success(()) : results.removeFirst()
    }
}

actor PausingRepositoryInitializer: CoreRepositoryInitializing {
    private let delayNanoseconds: UInt64
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []
    private var didStart = false

    init(delayNanoseconds: UInt64 = 500_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func waitUntilStarted() async {
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for repository initialization to start" },
            value: {
                didStart ? true : nil
            }
        )
    }

    func createdRepoPaths() -> [String] {
        createdPaths
    }

    func adoptedRepoPaths() -> [String] {
        adoptedPaths
    }
}
