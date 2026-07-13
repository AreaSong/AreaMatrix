@testable import AreaMatrix
import XCTest

actor StaticAISettingsLoader: CoreAISettingsLoading, RepoPathRequestRecording {
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

    var repoPathsForAssertions: [String] {
        recordedRepoPaths
    }
}

actor RecordingAISettingsUpdater: CoreAISettingsUpdating, RepoPathRequestRecording, ConfigUpdateRecording {
    struct Request: Equatable {
        var repoPath: String
        var config: AISettingsConfigSnapshot
    }

    private var resultQueue: VoidResultQueue
    private let updatedAt: Int64?
    private var recordedRequests: [Request] = []

    init(result: Swift.Result<Void, Error> = .success(()), updatedAt: Int64? = 1_778_000_000) {
        resultQueue = VoidResultQueue(result: result)
        self.updatedAt = updatedAt
    }

    init(results: [Swift.Result<Void, Error>], updatedAt: Int64? = 1_778_000_000) {
        resultQueue = VoidResultQueue(results: results)
        self.updatedAt = updatedAt
    }

    init(failureThenSuccess error: Error, updatedAt: Int64? = 1_778_000_000) {
        resultQueue = VoidResultQueue(failureThenSuccess: error)
        self.updatedAt = updatedAt
    }

    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recordedRequests.append(Request(repoPath: repoPath, config: normalized))
        try resultQueue.next().get()
        return AISettingsSnapshot.aiSettingsSnapshot(
            config: normalized,
            updatedAt: updatedAt
        )
    }

    func assertAISettingsUpdateRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, expectedRequests, file: file, line: line)
    }

    func assertNoAISettingsUpdateRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAISettingsUpdateRequests([], file: file, line: line)
    }

    var repoPathsForAssertions: [String] {
        recordedRequests.map(\.repoPath)
    }

    var updatedConfigsForAssertions: [AISettingsConfigSnapshot] {
        recordedRequests.map(\.config)
    }

    func assertRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateCount(expectedCount, file: file, line: line)
    }

    func assertRequestedConfigValues<Value: Equatable>(
        _ keyPath: KeyPath<AISettingsConfigSnapshot, Value>,
        _ expectedValues: [Value],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateValues(keyPath, expectedValues, file: file, line: line)
    }

    func assertRequestedConfigValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<AISettingsConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateValue(
            at: index,
            keyPath,
            expectedValue,
            failureSubject: "AI settings request",
            file: file,
            line: line
        )
    }

    func assertRequestedFeatureValue<Value: Equatable>(
        at index: Int,
        feature: AISettingsFeatureKind,
        _ keyPath: KeyPath<AISettingsFeatureConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard updatedConfigsForAssertions.indices.contains(index) else {
            XCTFail(
                "Expected AI settings request at index \(index), got \(updatedConfigsForAssertions.count)",
                file: file,
                line: line
            )
            return
        }
        let toggle = updatedConfigsForAssertions[index]
            .featureToggles
            .first(where: { $0.feature == feature })
        guard let toggle else {
            XCTFail("Expected AI settings request at index \(index) to include \(feature)", file: file, line: line)
            return
        }

        XCTAssertEqual(toggle[keyPath: keyPath], expectedValue, file: file, line: line)
    }

    func assertRequestedAllowRemoteFeatureCounts(
        _ expectedCounts: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            updatedConfigsForAssertions.map { config in
                config.featureToggles.filter(\.allowRemote).count
            },
            expectedCounts,
            file: file,
            line: line
        )
    }
}

actor RecordingAISettingsStore: CoreAISettingsLoading, CoreAISettingsUpdating, ConfigUpdateRecording {
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

    var updatedConfigsForAssertions: [AISettingsConfigSnapshot] {
        recordedRequests
    }

    func assertUpdateCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateCount(expectedCount, file: file, line: line)
    }

    func assertUpdatedConfigValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<AISettingsConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateValue(
            at: index,
            keyPath,
            expectedValue,
            failureSubject: "AI settings update",
            file: file,
            line: line
        )
    }
}
