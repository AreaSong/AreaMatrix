import Foundation

protocol CoreMetadataRepairing: Sendable {
    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot
}

struct RepairOptionsSnapshot: Equatable {
    var fullRescan: Bool
    var preserveDiagnosticsSnapshot: Bool
}

struct RepairReportSnapshot: Equatable {
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
            return try RepairReportSnapshot(coreReport: repairCoreMetadata(repoPath: repoPath, options: coreOptions))
        }.value
    }
}

private func repairCoreMetadata(repoPath: String, options: RepairOptions) throws -> RepairReport {
    try repairMetadata(repoPath: repoPath, options: options)
}

extension TagSuggestionApplyReportSnapshot {
    init(coreReport: TagSuggestionApplyReport) {
        fileID = coreReport.fileId
        requestedCount = coreReport.requestedCount
        appliedCount = coreReport.appliedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(TagSuggestionApplyItemResultSnapshot.init(coreResult:))
        tagSet = TagSetSnapshot(coreTagSet: coreReport.tagSet)
        undoToken = coreReport.undoToken
        refreshTargets = coreReport.refreshTargets
    }
}

private extension TagSuggestionApplyItemResultSnapshot {
    init(coreResult: TagSuggestionApplyItemResult) {
        suggestionID = coreResult.suggestionId
        slug = coreResult.slug
        status = TagSuggestionApplyStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension TagSuggestionApplyStatusSnapshot {
    init(coreStatus: TagSuggestionApplyStatus) {
        switch coreStatus {
        case .applied:
            self = .applied
        case .alreadyAdded:
            self = .alreadyAdded
        case .failed:
            self = .failed
        }
    }
}
