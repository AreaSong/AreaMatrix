import AreaMatrixCoreBridgeContract
import XCTest

final class CoreStartupRecoveryContractsTests: XCTestCase {
    func testRecoveryDetailsBecomeVisibleForCleanupDatabaseRollbackOrWarnings() {
        XCTAssertFalse(makeReport().hasVisibleDetails)
        XCTAssertTrue(makeReport(cleanedStagingFiles: 1).hasVisibleDetails)
        XCTAssertTrue(makeReport(revertedStagingDbRows: 1).hasVisibleDetails)
        XCTAssertTrue(makeReport(warnings: ["warning"]).hasVisibleDetails)
    }

    func testRepositoryInitializationResultPreservesRecoveryContract() {
        let report = makeReport(cleanedStagingFiles: 2, revertedStagingDbRows: 1)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/repository",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: report
        )

        XCTAssertEqual(result.repoPath, "/tmp/repository")
        XCTAssertEqual(result.mode, .adoptExisting)
        XCTAssertEqual(result.recoveryReport, report)
    }

    private func makeReport(
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
