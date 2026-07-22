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
        L10n.format(
            "onboarding.recovery.cleanupSummary",
            cleanedStagingFiles,
            revertedStagingDbRows
        )
    }
}

struct RepositoryInitializationResult: Equatable {
    var repoPath: String
    var mode: RepoInitModeSnapshot
    var scanSession: ScanSessionSnapshot?
    var recoveryReport: RecoveryReportSnapshot?
}
