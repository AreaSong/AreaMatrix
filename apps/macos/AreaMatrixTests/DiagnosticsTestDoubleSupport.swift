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

actor SuspendedDiagnosticsCollector: CoreDiagnosticsCollecting {
    private let result: Swift.Result<DiagnosticsSnapshotSnapshot, Error>
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var canFinish = false

    init(result: Swift.Result<DiagnosticsSnapshotSnapshot, Error>) {
        self.result = result
    }

    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations.removeAll()
        if !canFinish {
            await withCheckedContinuation { finishContinuation = $0 }
        }
        return try result.get()
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finish() {
        canFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}
