@testable import AreaMatrix

extension DiagnosticsSnapshotSnapshot {
    static func settingsErrorRecoveryFixture(repoPath: String) -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(
            snapshotPath: "\(repoPath)/.areamatrix/diagnostics/settings-error-recovery.zip",
            createdAt: 1_778_031_000,
            warnings: []
        )
    }
}
