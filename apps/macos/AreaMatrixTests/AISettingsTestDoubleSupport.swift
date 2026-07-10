@testable import AreaMatrix
import XCTest

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

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRepoPaths, expectedRepoPaths, file: file, line: line)
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

    func assertRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, expectedRequests, file: file, line: line)
    }

    func assertRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests.count, expectedCount, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, [], file: file, line: line)
    }

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests.map(\.repoPath), expectedRepoPaths, file: file, line: line)
    }

    func assertRequestedConfigValues<Value: Equatable>(
        _ keyPath: KeyPath<AISettingsConfigSnapshot, Value>,
        _ expectedValues: [Value],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            recordedRequests.map { $0.config[keyPath: keyPath] },
            expectedValues,
            file: file,
            line: line
        )
    }

    func assertRequestedConfigValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<AISettingsConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard recordedRequests.indices.contains(index) else {
            XCTFail(
                "Expected AI settings request at index \(index), got \(recordedRequests.count)",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(
            recordedRequests[index].config[keyPath: keyPath],
            expectedValue,
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
        guard recordedRequests.indices.contains(index) else {
            XCTFail(
                "Expected AI settings request at index \(index), got \(recordedRequests.count)",
                file: file,
                line: line
            )
            return
        }
        guard let toggle = recordedRequests[index].config.featureToggles.first(where: { $0.feature == feature }) else {
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
            recordedRequests.map { request in
                request.config.featureToggles.filter(\.allowRemote).count
            },
            expectedCounts,
            file: file,
            line: line
        )
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

    func loadRequests() -> [String] {
        recordedLoadRepoPaths
    }

    func assertUpdateCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests.count, expectedCount, file: file, line: line)
    }

    func assertUpdatedConfigValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<AISettingsConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard recordedRequests.indices.contains(index) else {
            XCTFail(
                "Expected AI settings update at index \(index), got \(recordedRequests.count)",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(
            recordedRequests[index][keyPath: keyPath],
            expectedValue,
            file: file,
            line: line
        )
    }
}
