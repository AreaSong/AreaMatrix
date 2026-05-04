import Foundation

protocol CoreDiagnosticsCollecting: Sendable {
    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot
}

struct DiagnosticsSnapshotSnapshot: Equatable, Sendable {
    var snapshotPath: String
    var createdAt: Int64
    var warnings: [String]
}

extension DiagnosticsSnapshotSnapshot {
    init(coreSnapshot: DiagnosticsSnapshot) {
        snapshotPath = coreSnapshot.snapshotPath
        createdAt = coreSnapshot.createdAt
        warnings = coreSnapshot.warnings
    }
}
