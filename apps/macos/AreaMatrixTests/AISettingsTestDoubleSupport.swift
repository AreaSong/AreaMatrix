@testable import AreaMatrix

actor StaticAISettingsLoader: CoreAISettingsLoading {
    private let snapshot: AISettingsSnapshot
    private var recordedRepoPaths: [String] = []

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    init(aiEnabled: Bool = true, autoTagsEnabled: Bool = true) {
        let config = AISettingsConfigSnapshot.aiSettingsConfig(
            repoPath: "/tmp/repo",
            aiEnabled: aiEnabled,
            localAIEnabled: true,
            enabledFeatures: autoTagsEnabled ? [.autoTags] : []
        )
        snapshot = AISettingsSnapshot.aiSettingsSnapshot(
            config: config,
            updatedAt: 1_700_000_410
        )
    }

    func loadAISettings(repoPath: String) async throws -> AISettingsSnapshot {
        recordedRepoPaths.append(repoPath)
        return snapshot
    }

    func requests() -> [String] {
        recordedRepoPaths
    }
}

actor RecordingAISettingsUpdater: CoreAISettingsUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: AISettingsConfigSnapshot
    }

    private var results: [Swift.Result<Void, Error>]
    private let repeatsSingleResult: Bool
    private let updatedAt: Int64?
    private var recordedRequests: [Request] = []

    init(result: Swift.Result<Void, Error> = .success(()), updatedAt: Int64? = 1_778_000_000) {
        results = [result]
        repeatsSingleResult = true
        self.updatedAt = updatedAt
    }

    init(results: [Swift.Result<Void, Error>], updatedAt: Int64? = 1_778_000_000) {
        self.results = results
        repeatsSingleResult = false
        self.updatedAt = updatedAt
    }

    init(failureThenSuccess error: Error, updatedAt: Int64? = 1_778_000_000) {
        results = [.failure(error), .success(())]
        repeatsSingleResult = false
        self.updatedAt = updatedAt
    }

    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recordedRequests.append(Request(repoPath: repoPath, config: normalized))
        try nextResult().get()
        return AISettingsSnapshot.aiSettingsSnapshot(
            config: normalized,
            updatedAt: updatedAt
        )
    }

    func requests() -> [Request] {
        recordedRequests
    }

    func requestedConfigs() -> [AISettingsConfigSnapshot] {
        recordedRequests.map(\.config)
    }

    private func nextResult() -> Swift.Result<Void, Error> {
        if repeatsSingleResult {
            return results.first ?? .success(())
        }
        return results.isEmpty ? .success(()) : results.removeFirst()
    }
}

actor RecordingAISettingsStore: CoreAISettingsLoading, CoreAISettingsUpdating {
    private var snapshot: AISettingsSnapshot
    private let updatedAt: Int64
    private var recordedLoadRepoPaths: [String] = []
    private var recordedRequests: [AISettingsConfigSnapshot] = []

    init(snapshot: AISettingsSnapshot, updatedAt: Int64 = 1_778_000_000) {
        self.snapshot = snapshot
        self.updatedAt = updatedAt
    }

    func loadAISettings(repoPath: String) async throws -> AISettingsSnapshot {
        recordedLoadRepoPaths.append(repoPath)
        return snapshot
    }

    func updateAISettings(repoPath _: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recordedRequests.append(normalized)
        snapshot = AISettingsSnapshot.aiSettingsSnapshot(
            config: normalized,
            updatedAt: updatedAt
        )
        return snapshot
    }

    func requests() -> [AISettingsConfigSnapshot] {
        recordedRequests
    }

    func loadRequests() -> [String] {
        recordedLoadRepoPaths
    }
}
