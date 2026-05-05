import XCTest
@testable import AreaMatrix

struct ShellStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

final class ShellRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

enum ShellRecordingResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

enum ShellRecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor ShellRecordingConfigLoader: CoreConfigurationLoading {
    private let result: ShellRecordingResult
    private var paths: [String] = []

    init(result: ShellRecordingResult) {
        self.result = result
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] { paths }
}

actor ShellRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: ShellRecordingRepositoryOpenResult
    private var configuredPaths: [String] = []

    init(result: ShellRecordingRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        switch result {
        case .success(let opening):
            return opening
        case .failure(let error):
            throw error
        }
    }

    func requestedConfiguredRepoPaths() -> [String] { configuredPaths }
}

enum ShellRecordingPathValidationResult {
    case success(RepoPathValidationSnapshot)
    case failure(Error)
}

actor ShellRecordingPathValidator: CoreRepositoryPathValidating {
    private let result: ShellRecordingPathValidationResult
    private var paths: [String] = []

    init(result: ShellRecordingPathValidationResult) {
        self.result = result
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let validation):
            return validation
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] { paths }
}

struct ShellNoopWelcomeHelpOpener: WelcomeHelpOpening { func openWelcomeHelp() throws {} }

struct ShellFailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

@MainActor
final class ShellRecordingFileRevealer: RepositoryFileRevealing {
    private(set) var requests: [(repoPath: String, relativePath: String)] = []

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append((repoPath: repoPath, relativePath: relativePath))
    }
}

@MainActor
final class ShellRecordingPathCopier: RepositoryPathCopying {
    private(set) var requests: [(repoPath: String, relativePath: String)] = []

    func copyPath(repoPath: String, relativePath: String) throws {
        requests.append((repoPath: repoPath, relativePath: relativePath))
    }
}

struct ShellStaticExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

extension RepoConfigSnapshot {
    static func shellFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func shellFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
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
    static func shellFixture(
        repoPath: String,
        exists: Bool = true,
        isDirectory: Bool = true,
        isReadable: Bool = true,
        isWritable: Bool = true,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        isICloudPath: Bool = false,
        hasUnfinishedScanSession: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: exists,
            isDirectory: isDirectory,
            isReadable: isReadable,
            isWritable: isWritable,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: isICloudPath,
            hasUnfinishedScanSession: hasUnfinishedScanSession,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}
