import Foundation
@testable import AreaMatrix

func makeRepairTemporaryAdoptRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdoptExisting-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct RepairStaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    func configuredRepoPath() -> String? { repoPath }
}

final class RepairRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []
    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

actor RepairRecordingConfigLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot
    init(config: RepoConfigSnapshot) {
        self.config = config
    }
    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        config
    }
}

enum RepairRecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor RepairRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: RepairRecordingRepositoryOpenResult
    private var paths: [String] = []

    init(result: RepairRecordingRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        paths.append(repoPath)
        switch result {
        case .success(let opening):
            return opening
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] { paths }
}

actor RepairRecordingPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot
    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
}

actor RepairSequencePathValidator: CoreRepositoryPathValidating {
    private var validations: [RepoPathValidationSnapshot]

    init(validations: [RepoPathValidationSnapshot]) {
        self.validations = validations
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        guard !validations.isEmpty else {
            throw CoreError.Config(reason: "missing validation fixture")
        }

        return validations.removeFirst()
    }
}

actor RepairRecordingRepositoryInitializer: CoreRepositoryInitializing {
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
    }

    func createdRepoPaths() -> [String] { createdPaths }
    func adoptedRepoPaths() -> [String] { adoptedPaths }
}

actor RepairPausingRepositoryInitializer: CoreRepositoryInitializing {
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []
    private var didStart = false

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func createdRepoPaths() -> [String] { createdPaths }
}

actor RepairStaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}

struct RepairStaticExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

struct RepairNoopWelcomeHelpOpener: WelcomeHelpOpening { func openWelcomeHelp() throws {} }

extension RepoConfigSnapshot {
    static func repairFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

extension RepositoryOpeningResult {
    static func repairFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .repairFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            )
        )
    }
}

extension RepoPathValidationSnapshot {
    static func repairFixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}
