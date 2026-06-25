extension CoreBridge: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        let report = try await Task.detached(priority: .userInitiated) { [repoPath] in
            try recoverCoreOnStartup(repoPath: repoPath)
        }.value
        return RecoveryReportSnapshot(coreReport: report)
    }
}

private extension RecoveryReportSnapshot {
    init(coreReport: RecoveryReport) {
        cleanedStagingFiles = coreReport.cleanedStagingFiles
        revertedStagingDbRows = coreReport.revertedStagingDbRows
        warnings = coreReport.warnings
    }
}

private func recoverCoreOnStartup(repoPath: String) throws -> RecoveryReport {
    try recoverOnStartup(repoPath: repoPath)
}
