@testable import AreaMatrix
import XCTest

struct NoopConfigurationUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

actor RecordingConfigurationUpdater:
    CoreConfigurationUpdating,
    RepoPathRequestRecording,
    ConfigUpdateRecording {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private var resultQueue: VoidResultQueue
    private var requestLog = TestRequestLog<Request>()

    init(result: Swift.Result<Void, Error> = .success(())) {
        resultQueue = VoidResultQueue(result: result)
    }

    init(results: [Swift.Result<Void, Error>]) {
        resultQueue = VoidResultQueue(results: results)
    }

    init(failureThenSuccess error: Error) {
        resultQueue = VoidResultQueue(failureThenSuccess: error)
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        requestLog.append(Request(repoPath: repoPath, config: newConfig))
        try resultQueue.next().get()
    }

    func assertConfigurationUpdateRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertNoConfigurationUpdateRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigurationUpdateRequests([], file: file, line: line)
    }

    var repoPathsForAssertions: [String] {
        requestLog.requests.map(\.repoPath)
    }

    var updatedConfigsForAssertions: [RepoConfigSnapshot] {
        requestLog.requests.map(\.config)
    }

    func assertRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateCount(expectedCount, file: file, line: line)
    }

    func assertRequestedConfigValues<Value: Equatable>(
        _ keyPath: KeyPath<RepoConfigSnapshot, Value>,
        _ expectedValues: [Value],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateValues(keyPath, expectedValues, file: file, line: line)
    }

    func assertRequestedConfigValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<RepoConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertConfigUpdateValue(
            at: index,
            keyPath,
            expectedValue,
            failureSubject: "config request",
            file: file,
            line: line
        )
    }
}

protocol ConfigUpdateRecording: Actor {
    associatedtype ConfigSnapshot

    var updatedConfigsForAssertions: [ConfigSnapshot] { get }
}

extension ConfigUpdateRecording {
    func assertConfigUpdateCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(updatedConfigsForAssertions.count, expectedCount, file: file, line: line)
    }

    func assertConfigUpdateValues<Value: Equatable>(
        _ keyPath: KeyPath<ConfigSnapshot, Value>,
        _ expectedValues: [Value],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(updatedConfigsForAssertions.map { $0[keyPath: keyPath] }, expectedValues, file: file, line: line)
    }

    func assertConfigUpdateValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<ConfigSnapshot, Value>,
        _ expectedValue: Value,
        failureSubject: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard updatedConfigsForAssertions.indices.contains(index) else {
            XCTFail(
                "Expected \(failureSubject) at index \(index), got \(updatedConfigsForAssertions.count)",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(
            updatedConfigsForAssertions[index][keyPath: keyPath],
            expectedValue,
            file: file,
            line: line
        )
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
    private var resultQueue: TestResultQueue<RepoConfigSnapshot>
    private var pathLog = TestRequestLog<String>()

    init(result: Result<RepoConfigSnapshot, Error>) {
        resultQueue = TestResultQueue(result: result) {
            .failure(CoreError.Internal(message: "missing config"))
        }
    }

    init(results: [Result<RepoConfigSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .failure(CoreError.Internal(message: "missing config"))
        }
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        pathLog.append(repoPath)
        return try resultQueue.next()
    }

    func assertRequestedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        pathLog.assertRequests(expectedPaths, file: file, line: line)
    }
}
