@testable import AreaMatrix
import Foundation

enum SmokeRecordingConfigResult {
    case success(RepoConfigSnapshot)
}

struct SmokeStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

final class SmokeRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

actor SmokeRecordingConfigLoader: CoreConfigurationLoading {
    private let result: SmokeRecordingConfigResult

    init(result: SmokeRecordingConfigResult) {
        self.result = result
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        switch result {
        case let .success(config):
            config
        }
    }
}

enum SmokeRecordingPathValidationResult {
    case success(RepoPathValidationSnapshot)
    case failure(Error)
}

actor SmokeRecordingPathValidator: CoreRepositoryPathValidating {
    private let result: SmokeRecordingPathValidationResult

    init(result: SmokeRecordingPathValidationResult) {
        self.result = result
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        switch result {
        case let .success(validation):
            return validation
        case let .failure(error):
            throw error
        }
    }
}

enum SmokeRecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor SmokeRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: SmokeRecordingRepositoryOpenResult
    private var paths: [String] = []

    init(result: SmokeRecordingRepositoryOpenResult) {
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
        case let .success(opening):
            return opening
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

enum SmokeRecordingScanSessionResult {
    case success(ScanSessionSnapshot?)
    case failure(Error)
}

actor SmokeRecordingScanSessionReader: CoreScanSessionReading {
    private let result: SmokeRecordingScanSessionResult
    private var paths: [String] = []

    init(result: SmokeRecordingScanSessionResult) {
        self.result = result
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        paths.append(repoPath)
        switch result {
        case let .success(session):
            return session
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

struct SmokeNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

struct SmokeExistingRepoMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

extension RepoConfigSnapshot {
    static func smokeFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func smokeFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .smokeFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

extension RepoPathValidationSnapshot {
    static func smokeAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        smokeFixture(
            repoPath: repoPath,
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
    }

    static func smokeFixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        hasUnfinishedScanSession: Bool = false,
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
            hasUnfinishedScanSession: hasUnfinishedScanSession,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}

extension ScanSessionSnapshot {
    static func adoptFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 7,
            kind: .adopt,
            status: .interrupted,
            lastPath: "docs/report.pdf",
            inserted: 12,
            updated: 1,
            skipped: 3,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_120,
            finishedAt: nil,
            errors: []
        )
    }
}
