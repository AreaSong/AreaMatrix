@testable import AreaMatrix

actor StaticAISettingsLoader: CoreAISettingsLoading {
    private let snapshot: AISettingsSnapshot

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    func loadAISettings(repoPath _: String) async throws -> AISettingsSnapshot {
        snapshot
    }
}

actor RecordingAISettingsUpdater: CoreAISettingsUpdating {
    enum UpdateResult {
        case success
        case failure(Error)
    }

    struct Request: Equatable {
        var repoPath: String
        var config: AISettingsConfigSnapshot
    }

    private var results: [UpdateResult]
    private let repeatsSingleResult: Bool
    private let updatedAt: Int64?
    private var recordedRequests: [Request] = []

    init(result: UpdateResult = .success, updatedAt: Int64? = 1_778_000_000) {
        results = [result]
        repeatsSingleResult = true
        self.updatedAt = updatedAt
    }

    init(results: [UpdateResult], updatedAt: Int64? = 1_778_000_000) {
        self.results = results
        repeatsSingleResult = false
        self.updatedAt = updatedAt
    }

    init(failureThenSuccess error: Error, updatedAt: Int64? = 1_778_000_000) {
        results = [.failure(error), .success]
        repeatsSingleResult = false
        self.updatedAt = updatedAt
    }

    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recordedRequests.append(Request(repoPath: repoPath, config: normalized))
        if case let .failure(error) = nextResult() {
            throw error
        }
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: updatedAt
        )
    }

    func requests() -> [Request] {
        recordedRequests
    }

    func requestedConfigs() -> [AISettingsConfigSnapshot] {
        recordedRequests.map(\.config)
    }

    private func nextResult() -> UpdateResult {
        if repeatsSingleResult {
            return results.first ?? .success
        }
        return results.isEmpty ? .success : results.removeFirst()
    }
}
