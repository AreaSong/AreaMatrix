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

actor StaticCoreVersionReader: CoreVersionReading {
    private let result: Result<String, Error>
    private var count = 0

    init(version: String) {
        result = .success(version)
    }

    init(result: Result<String, Error>) {
        self.result = result
    }

    func coreVersion() async throws -> String {
        count += 1
        return try result.get()
    }

    func requestCount() -> Int {
        count
    }
}

actor StaticExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    private let result: Result<ExistingRepositoryMetadataSnapshot, Error>
    private var paths: [String] = []

    init(schemaVersion: Int64) {
        result = .success(ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil))
    }

    init(result: Result<ExistingRepositoryMetadataSnapshot, Error>) {
        self.result = result
    }

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        paths.append(repoPath)
        return try result.get()
    }

    func requestedPaths() -> [String] {
        paths
    }
}

actor StaticRepositoryPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot

    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
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
    private let result: Result<ScanSessionSnapshot?, Error>

    init(session: ScanSessionSnapshot? = nil) {
        result = .success(session)
    }

    init(result: Result<ScanSessionSnapshot?, Error>) {
        self.result = result
    }

    func latestScanSession(repoPath _: String) async throws -> ScanSessionSnapshot? {
        try result.get()
    }
}
