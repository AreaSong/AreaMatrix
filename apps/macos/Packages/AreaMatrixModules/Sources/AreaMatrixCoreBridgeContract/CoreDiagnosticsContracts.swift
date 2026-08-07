/// Stable diagnostics capability contract consumed by the App composition and
/// feature models. The live implementation remains App-owned because it uses
/// tracked UniFFI bindings and the repository file-system boundary.
public protocol CoreDiagnosticsCollecting: Sendable {
    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot
}

public struct DiagnosticsSnapshotSnapshot: Equatable, Sendable {
    public let snapshotPath: String
    public let createdAt: Int64
    public let warnings: [String]

    public init(snapshotPath: String, createdAt: Int64, warnings: [String]) {
        self.snapshotPath = snapshotPath
        self.createdAt = createdAt
        self.warnings = warnings
    }
}
