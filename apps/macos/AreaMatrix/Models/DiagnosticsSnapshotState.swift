import Foundation

protocol CoreDiagnosticsCollecting: Sendable {
    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot
}

struct DiagnosticsSnapshotSnapshot: Equatable {
    var snapshotPath: String
    var createdAt: Int64
    var warnings: [String]
}

enum MainRepoDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

extension DiagnosticsSnapshotSnapshot {
    init(coreSnapshot: DiagnosticsSnapshot) {
        snapshotPath = coreSnapshot.snapshotPath
        createdAt = coreSnapshot.createdAt
        warnings = coreSnapshot.warnings
    }
}
