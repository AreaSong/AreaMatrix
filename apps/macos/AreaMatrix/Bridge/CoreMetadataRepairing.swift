import Foundation

protocol CoreMetadataRepairing: Sendable {
    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot
}

struct RepairOptionsSnapshot: Equatable, Sendable {
    var fullRescan: Bool
    var preserveDiagnosticsSnapshot: Bool
}

struct RepairReportSnapshot: Equatable, Sendable {
    var scanSessionId: Int64?
    var diagnosticsSnapshotPath: String?
    var inserted: Int64
    var updated: Int64
    var skipped: Int64
    var errors: [String]
}

extension RepairReportSnapshot {
    init(coreReport: RepairReport) {
        scanSessionId = coreReport.scanSessionId
        diagnosticsSnapshotPath = coreReport.diagnosticsSnapshotPath
        inserted = coreReport.inserted
        updated = coreReport.updated
        skipped = coreReport.skipped
        errors = coreReport.errors
    }

    var summaryText: String {
        "Inserted \(inserted), updated \(updated), skipped \(skipped)."
    }
}

extension CoreBridge: CoreMetadataRepairing {
    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let coreOptions = RepairOptions(
                fullRescan: options.fullRescan,
                preserveDiagnosticsSnapshot: options.preserveDiagnosticsSnapshot
            )
            return RepairReportSnapshot(coreReport: try repairCoreMetadata(repoPath: repoPath, options: coreOptions))
        }.value
    }
}

private func repairCoreMetadata(repoPath: String, options: RepairOptions) throws -> RepairReport {
    try repairMetadata(repoPath: repoPath, options: options)
}
