@testable import AreaMatrix
import XCTest

actor RecordingDiagnosticsCollector: CoreDiagnosticsCollecting {
    typealias SnapshotResult = Swift.Result<DiagnosticsSnapshotSnapshot, Error>

    private let repeatingResult: SnapshotResult?
    private var queuedResults: [SnapshotResult]
    private var repoPaths: [String] = []

    init(result: SnapshotResult) {
        repeatingResult = result
        queuedResults = []
    }

    init(snapshot: DiagnosticsSnapshotSnapshot) {
        repeatingResult = .success(snapshot)
        queuedResults = []
    }

    init(snapshots: [DiagnosticsSnapshotSnapshot]) {
        repeatingResult = nil
        queuedResults = snapshots.map { .success($0) }
    }

    init(results: [SnapshotResult]) {
        repeatingResult = nil
        queuedResults = results
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        return try nextResult()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }

    func recordedRepoPaths() -> [String] {
        repoPaths
    }

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(repoPaths, expectedRepoPaths, file: file, line: line)
    }

    func assertRecordedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedRepoPaths(expectedRepoPaths, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequestedRepoPaths([], file: file, line: line)
    }

    private func nextResult() throws -> DiagnosticsSnapshotSnapshot {
        if let repeatingResult {
            return try repeatingResult.get()
        }
        guard !queuedResults.isEmpty else {
            throw CoreError.Internal(message: "missing diagnostics fixture")
        }

        return try queuedResults.removeFirst().get()
    }
}
