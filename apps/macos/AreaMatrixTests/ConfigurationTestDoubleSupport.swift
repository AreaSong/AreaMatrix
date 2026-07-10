@testable import AreaMatrix
import XCTest

struct NoopConfigurationUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

actor RecordingConfigurationUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private var results: [Swift.Result<Void, Error>]
    private let repeatsSingleResult: Bool
    private var recordedRequests: [Request] = []

    init(result: Swift.Result<Void, Error> = .success(())) {
        results = [result]
        repeatsSingleResult = true
    }

    init(results: [Swift.Result<Void, Error>]) {
        self.results = results
        repeatsSingleResult = false
    }

    init(failureThenSuccess error: Error) {
        results = [.failure(error), .success(())]
        repeatsSingleResult = false
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        recordedRequests.append(Request(repoPath: repoPath, config: newConfig))
        try nextResult().get()
    }

    func requests() -> [Request] {
        recordedRequests
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

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests.map(\.repoPath), expectedRepoPaths, file: file, line: line)
    }

    func assertRequestedConfigValues<Value: Equatable>(
        _ keyPath: KeyPath<RepoConfigSnapshot, Value>,
        _ expectedValues: [Value],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests.map { $0.config[keyPath: keyPath] }, expectedValues, file: file, line: line)
    }

    func assertRequestedConfigValue<Value: Equatable>(
        at index: Int,
        _ keyPath: KeyPath<RepoConfigSnapshot, Value>,
        _ expectedValue: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard recordedRequests.indices.contains(index) else {
            XCTFail("Expected config request at index \(index), got \(recordedRequests.count)", file: file, line: line)
            return
        }

        XCTAssertEqual(recordedRequests[index].config[keyPath: keyPath], expectedValue, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, [], file: file, line: line)
    }

    private func nextResult() -> Swift.Result<Void, Error> {
        if repeatsSingleResult {
            return results.first ?? .success(())
        }
        return results.isEmpty ? .success(()) : results.removeFirst()
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

    func assertRequestedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(paths, expectedPaths, file: file, line: line)
    }

    private func nextResult() -> Result<RepoConfigSnapshot, Error>? {
        if repeatsSingleResult {
            return results.first
        }
        return results.isEmpty ? nil : results.removeFirst()
    }
}
