protocol CoreStartupRecovering: Sendable {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot
}

struct RecoveryReportSnapshot: Equatable {
    var cleanedStagingFiles: Int64
    var revertedStagingDbRows: Int64
    var warnings: [String]

    var hasVisibleDetails: Bool {
        cleanedStagingFiles > 0 || revertedStagingDbRows > 0 || !warnings.isEmpty
    }

    var startupRecoverySummaryText: String {
        """
        清理 \(cleanedStagingFiles) 个临时文件，回滚 \(revertedStagingDbRows) 条 staging 记录
        """
    }
}

struct ReindexReportSnapshot: Equatable {
    var scanSessionId: Int64?
    var inserted: Int64
    var updated: Int64
    var skipped: Int64
    var errors: [String]
}

struct RepositoryInitializationResult: Equatable {
    var repoPath: String
    var mode: RepoInitModeSnapshot
    var scanSession: ScanSessionSnapshot?
    var recoveryReport: RecoveryReportSnapshot?
}

extension ReindexReportSnapshot {
    init(coreReport: ReindexReport) {
        scanSessionId = coreReport.scanSessionId
        inserted = coreReport.inserted
        updated = coreReport.updated
        skipped = coreReport.skipped
        errors = coreReport.errors
    }
}
