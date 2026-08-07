import AreaMatrixCoreBridgeContract

extension DiagnosticsSnapshotSnapshot {
    init(coreSnapshot: DiagnosticsSnapshot) {
        self.init(
            snapshotPath: coreSnapshot.snapshotPath,
            createdAt: coreSnapshot.createdAt,
            warnings: coreSnapshot.warnings
        )
    }
}
