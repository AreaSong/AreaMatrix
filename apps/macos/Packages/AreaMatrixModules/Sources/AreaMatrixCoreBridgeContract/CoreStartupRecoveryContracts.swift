public protocol CoreStartupRecovering: Sendable {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot
}

public struct RecoveryReportSnapshot: Equatable, Sendable {
    public var cleanedStagingFiles: Int64
    public var revertedStagingDbRows: Int64
    public var warnings: [String]

    public init(
        cleanedStagingFiles: Int64,
        revertedStagingDbRows: Int64,
        warnings: [String]
    ) {
        self.cleanedStagingFiles = cleanedStagingFiles
        self.revertedStagingDbRows = revertedStagingDbRows
        self.warnings = warnings
    }

    public var hasVisibleDetails: Bool {
        cleanedStagingFiles > 0 || revertedStagingDbRows > 0 || !warnings.isEmpty
    }
}

public struct RepositoryInitializationResult: Equatable, Sendable {
    public var repoPath: String
    public var mode: RepoInitModeSnapshot
    public var scanSession: ScanSessionSnapshot?
    public var recoveryReport: RecoveryReportSnapshot?

    public init(
        repoPath: String,
        mode: RepoInitModeSnapshot,
        scanSession: ScanSessionSnapshot?,
        recoveryReport: RecoveryReportSnapshot?
    ) {
        self.repoPath = repoPath
        self.mode = mode
        self.scanSession = scanSession
        self.recoveryReport = recoveryReport
    }
}
