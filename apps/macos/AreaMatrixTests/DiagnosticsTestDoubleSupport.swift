@testable import AreaMatrix

actor RecordingDiagnosticsCollector: CoreDiagnosticsCollecting, RepoPathRequestRecording {
    typealias SnapshotResult = Swift.Result<DiagnosticsSnapshotSnapshot, Error>

    private var resultQueue: TestResultQueue<DiagnosticsSnapshotSnapshot>
    private var repoPaths: [String] = []

    init(result: SnapshotResult) {
        resultQueue = TestResultQueue(result: result, missingResult: Self.missingResult)
    }

    init(snapshot: DiagnosticsSnapshotSnapshot) {
        resultQueue = TestResultQueue(result: .success(snapshot), missingResult: Self.missingResult)
    }

    init(snapshots: [DiagnosticsSnapshotSnapshot]) {
        resultQueue = TestResultQueue(results: snapshots.map { .success($0) }, missingResult: Self.missingResult)
    }

    init(results: [SnapshotResult]) {
        resultQueue = TestResultQueue(results: results, missingResult: Self.missingResult)
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        return try nextResult()
    }

    var repoPathsForAssertions: [String] {
        repoPaths
    }

    private func nextResult() throws -> DiagnosticsSnapshotSnapshot {
        try resultQueue.next()
    }

    private static func missingResult() -> SnapshotResult {
        .failure(CoreError.Internal(message: "missing diagnostics fixture"))
    }
}
