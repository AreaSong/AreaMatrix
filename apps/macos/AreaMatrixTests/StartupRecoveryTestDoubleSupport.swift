@testable import AreaMatrix
import XCTest

extension RecoveryReportSnapshot {
    static func testFixture(
        cleanedStagingFiles: Int64 = 0,
        revertedStagingDbRows: Int64 = 0,
        warnings: [String] = []
    ) -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(
            cleanedStagingFiles: cleanedStagingFiles,
            revertedStagingDbRows: revertedStagingDbRows,
            warnings: warnings
        )
    }
}

actor StaticStartupRecoverer: CoreStartupRecovering {
    private let report: RecoveryReportSnapshot

    init(report: RecoveryReportSnapshot = .testFixture()) {
        self.report = report
    }

    func recoverOnStartup(repoPath _: String) async throws -> RecoveryReportSnapshot {
        report
    }
}

actor RecordingCoreStartupRecoverer: CoreStartupRecovering, RepoPathRequestRecording {
    private var resultQueue: TestResultQueue<RecoveryReportSnapshot>
    private var paths: [String] = []
    private var didRecover = false

    init(report: RecoveryReportSnapshot = .testFixture()) {
        resultQueue = TestResultQueue(results: [.success(report)]) {
            .success(.testFixture())
        }
    }

    init(result: Result<RecoveryReportSnapshot, Error>) {
        resultQueue = TestResultQueue(results: [result]) {
            .success(.testFixture())
        }
    }

    init(results: [Result<RecoveryReportSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success(.testFixture())
        }
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        didRecover = true
        return try resultQueue.next()
    }

    func waitUntilRecovered() async {
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for startup recovery request" },
            value: {
                didRecover ? true : nil
            }
        )
    }

    var repoPathsForAssertions: [String] {
        paths
    }
}
