@testable import AreaMatrix

struct NoopConfigurationUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

actor RecordingConfigurationUpdater: CoreConfigurationUpdating {
    enum UpdateResult {
        case success
        case failure(Error)
    }

    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private var results: [UpdateResult]
    private let repeatsSingleResult: Bool
    private var recordedRequests: [Request] = []

    init(result: UpdateResult = .success) {
        results = [result]
        repeatsSingleResult = true
    }

    init(results: [UpdateResult]) {
        self.results = results
        repeatsSingleResult = false
    }

    init(failureThenSuccess error: Error) {
        results = [.failure(error), .success]
        repeatsSingleResult = false
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        recordedRequests.append(Request(repoPath: repoPath, config: newConfig))
        if case let .failure(error) = nextResult() {
            throw error
        }
    }

    func requests() -> [Request] {
        recordedRequests
    }

    private func nextResult() -> UpdateResult {
        if repeatsSingleResult {
            return results.first ?? .success
        }
        return results.isEmpty ? .success : results.removeFirst()
    }
}

actor StaticConfigurationLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

actor RecordingConfigurationLoader: CoreConfigurationLoading {
    private var results: [Result<RepoConfigSnapshot, Error>]
    private let repeatsSingleResult: Bool
    private var paths: [String] = []

    init(result: Result<RepoConfigSnapshot, Error>) {
        results = [result]
        repeatsSingleResult = true
    }

    init(results: [Result<RepoConfigSnapshot, Error>]) {
        self.results = results
        repeatsSingleResult = false
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        guard let result = nextResult() else {
            throw CoreError.Internal(message: "missing config")
        }
        return try result.get()
    }

    func requestedPaths() -> [String] {
        paths
    }

    private func nextResult() -> Result<RepoConfigSnapshot, Error>? {
        if repeatsSingleResult {
            return results.first
        }
        return results.isEmpty ? nil : results.removeFirst()
    }
}
