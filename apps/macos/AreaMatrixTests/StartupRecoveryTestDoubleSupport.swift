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

actor RecordingCoreStartupRecoverer: CoreStartupRecovering {
    private var results: [Result<RecoveryReportSnapshot, Error>]
    private var paths: [String] = []
    private var didRecover = false

    init(report: RecoveryReportSnapshot = .testFixture()) {
        results = [.success(report)]
    }

    init(result: Result<RecoveryReportSnapshot, Error>) {
        results = [result]
    }

    init(results: [Result<RecoveryReportSnapshot, Error>]) {
        self.results = results
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        didRecover = true
        let result = results.isEmpty ? Result.success(.testFixture()) : results.removeFirst()
        return try result.get()
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

    func requestedRepoPaths() -> [String] {
        paths
    }

    func assertRequestedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(paths, expectedRepoPaths, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(paths, [], file: file, line: line)
    }
}
