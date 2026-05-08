import XCTest
@testable import AreaMatrix

struct ShellStaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    var lastOpenedAtByRepoPath: [String: Int64] = [:]

    func configuredRepoPath() -> String? { repoPath }
    func lastSuccessfulRepoOpenAt(repoPath: String) -> Int64? {
        lastOpenedAtByRepoPath[repoPath]
    }
}

final class ShellRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []
    private(set) var successfulRepoOpens: [(repoPath: String, openedAt: Int64)] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }

    func saveSuccessfulRepoOpen(repoPath: String, openedAt: Int64) {
        successfulRepoOpens.append((repoPath: repoPath, openedAt: openedAt))
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

actor ShellRecordingInitializedPathValidator: CoreInitializedRepositoryPathValidating {
    private let result: ShellRecordingPathValidationResult
    private var paths: [String] = []

    init(result: ShellRecordingPathValidationResult) {
        self.result = result
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
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

struct ShellExternalRemovalRequest: Equatable {
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

actor ShellRecordingExternalChangesSyncer: CoreExternalChangesSyncing {
    private let result: Result<SyncResultSnapshot, Error>
    private var requests: [ShellExternalRemovalRequest] = []
    private var createdRequests: [ShellExternalRemovalRequest] = []
    private var renamedRequests: [ShellExternalRemovalRequest] = []

    init(result: Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        createdRequests.append(ShellExternalRemovalRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func syncExternalRenamed(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        renamedRequests.append(ShellExternalRemovalRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        requests.append(ShellExternalRemovalRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [ShellExternalRemovalRequest] { requests }
    func recordedCreatedRequests() -> [ShellExternalRemovalRequest] { createdRequests }
    func recordedRenamedRequests() -> [ShellExternalRemovalRequest] { renamedRequests }

    func getFSEventCursor(repoPath: String) async throws -> Int64? { nil }
    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws {}
}

actor ShellRecordingDiagnosticsCollector: CoreDiagnosticsCollecting {
    private let result: Result<DiagnosticsSnapshotSnapshot, Error>
    private var repoPaths: [String] = []

    init(result: Result<DiagnosticsSnapshotSnapshot, Error>) {
        self.result = result
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        return try result.get()
    }

    func requestedRepoPaths() -> [String] { repoPaths }
}

struct ShellNoopWelcomeHelpOpener: WelcomeHelpOpening { func openWelcomeHelp() throws {} }

struct ShellFailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

@MainActor
final class ShellRecordingFinderOpener: RepositoryFinderOpening {
    private let result: Result<Void, RepositoryFinderOpenError>
    private(set) var openedRepoPaths: [String] = []

    init(result: Result<Void, RepositoryFinderOpenError> = .success(())) {
        self.result = result
    }

    func openRepositoryInFinder(repoPath: String) throws {
        openedRepoPaths.append(repoPath)
        try result.get()
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
final class ShellRecordingFileOpener: RepositoryFileOpening {
    private(set) var requests: [(repoPath: String, relativePath: String)] = []

    func openFile(repoPath: String, relativePath: String) throws {
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
    var lastOpenedAt: Int64?
    var configuredRepoPath: String?

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(
            schemaVersion: schemaVersion,
            lastOpenedAt: lastOpenedAt,
            configuredRepoPath: configuredRepoPath
        )
    }
}

@MainActor
final class ShellRecordingDirectoryPicker: RepositoryDirectoryPicking {
    private let selectedURL: URL?
    private(set) var chooseCount = 0

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func chooseDirectory() -> URL? {
        chooseCount += 1
        return selectedURL
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

extension SyncResultSnapshot {
    static func shellDeletedFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 1,
            detectedModifies: 0,
            errors: []
        )
    }

    static func shellRenamedFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 1,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
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

actor ShellStaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}
