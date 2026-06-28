@testable import AreaMatrix

struct NoopFileLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

struct NoopNoteStore: CoreNoteReadingWriting {
    func readNote(repoPath _: String, fileID _: Int64) async throws -> String? {
        nil
    }

    func writeNote(repoPath _: String, fileID _: Int64, contentMarkdown _: String) async throws {}
}

struct NoopConfigurationUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

actor StaticStartupRecoverer: CoreStartupRecovering {
    private let report: RecoveryReportSnapshot

    init(report: RecoveryReportSnapshot = RecoveryReportSnapshot(
        cleanedStagingFiles: 0,
        revertedStagingDbRows: 0,
        warnings: []
    )) {
        self.report = report
    }

    func recoverOnStartup(repoPath _: String) async throws -> RecoveryReportSnapshot {
        report
    }
}

actor StaticScanSessionReader: CoreScanSessionReading {
    private let session: ScanSessionSnapshot?

    init(session: ScanSessionSnapshot? = nil) {
        self.session = session
    }

    func latestScanSession(repoPath _: String) async throws -> ScanSessionSnapshot? {
        session
    }
}
