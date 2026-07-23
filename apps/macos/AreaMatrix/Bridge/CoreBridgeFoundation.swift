import Foundation

protocol CoreConfigurationLoading: Sendable {
    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot
}

protocol CoreConfigurationUpdating: Sendable {
    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws
}

protocol CoreRepositoryPathValidating: Sendable {
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot
}

protocol CoreInitializedRepositoryPathValidating: Sendable {
    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot
}

protocol CoreRepositoryInitializing: Sendable {
    func initializeEmptyRepository(repoPath: String) async throws
    func adoptExistingRepository(repoPath: String) async throws
}

protocol CoreScanSessionReading: Sendable {
    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot?
    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot
}

protocol CoreCategoryPredicting: Sendable {
    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot
}

protocol CoreCommandIndexing: Sendable {
    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex
}

extension CoreScanSessionReading {
    func resumeScanSession(repoPath _: String, scanSessionId _: Int64) async throws -> ReindexReportSnapshot {
        throw CoreError.Internal(message: "scan session resume is unavailable")
    }
}

enum RepoInitModeSnapshot: String, Equatable {
    case createEmpty = "CreateEmpty"
    case adoptExisting = "AdoptExisting"
}

enum ScanSessionKindSnapshot: String, Equatable {
    case adopt = "Adopt"
    case reindex = "Reindex"
}

enum ScanSessionStatusSnapshot: String, Equatable {
    case running = "Running"
    case completed = "Completed"
    case paused = "Paused"
    case failed = "Failed"
    case interrupted = "Interrupted"

    var displayName: String {
        switch self {
        case .running: L10n.string("Running")
        case .completed: L10n.string("Completed")
        case .paused: L10n.string("Paused")
        case .failed: L10n.string("Failed")
        case .interrupted: L10n.string("Interrupted")
        }
    }
}

enum RepoPathIssueSnapshot: String, Equatable {
    case missingPath = "MissingPath"
    case notDirectory = "NotDirectory"
    case notReadable = "NotReadable"
    case notWritable = "NotWritable"
    case nonEmptyDirectory = "NonEmptyDirectory"
    case alreadyInitialized = "AlreadyInitialized"
    case insideAreaMatrix = "InsideAreaMatrix"
    case iCloudPath = "ICloudPath"
    case oneDrivePath = "OneDrivePath"
    case windowsReservedName = "WindowsReservedName"
    case windowsCaseInsensitive = "WindowsCaseInsensitive"
    case unfinishedScanSession = "UnfinishedScanSession"
}

struct RepoPathValidationSnapshot: Equatable {
    var repoPath: String
    var exists: Bool
    var isDirectory: Bool
    var isReadable: Bool
    var isWritable: Bool
    var isEmpty: Bool
    var isInitialized: Bool
    var isInsideAreaMatrix: Bool
    var isICloudPath: Bool
    var hasUnfinishedScanSession: Bool
    var availableCapacityBytes: Int64?
    var isExternalVolume: Bool?
    var recommendedMode: RepoInitModeSnapshot?
    var issues: [RepoPathIssueSnapshot]
}

extension RepoPathValidationSnapshot {
    static let minimumUsableCapacityBytes: Int64 = 512 * 1024 * 1024

    var hasInsufficientAvailableCapacity: Bool {
        availableCapacityBytes.map { $0 < Self.minimumUsableCapacityBytes } ?? false
    }

    var hasMissingEnvironmentChecks: Bool {
        availableCapacityBytes == nil || isExternalVolume == nil
    }
}

struct RepositoryInitializationDraft: Equatable {
    var validation: RepoPathValidationSnapshot
    var mode: RepoInitModeSnapshot
    var scanSession: ScanSessionSnapshot?
}

struct ScanSessionSnapshot: Equatable {
    var id: Int64
    var kind: ScanSessionKindSnapshot
    var status: ScanSessionStatusSnapshot
    var lastPath: String?
    var inserted: Int64
    var updated: Int64
    var skipped: Int64
    var startedAt: Int64
    var updatedAt: Int64
    var finishedAt: Int64?
    var errors: [String]
}

struct RepoConfigSnapshot: Equatable {
    var repoPath: String
    var defaultMode: String
    var overviewOutput: String
    var aiEnabled: Bool
    var locale: String
    var iCloudWarn: Bool
    var enableExtensionRules: Bool
    var enableKeywordRules: Bool
    var fallbackToInbox: Bool
    var allowReplaceDuringImport: Bool
}

extension RepoConfigSnapshot {
    init(coreConfig: RepoConfig) {
        repoPath = coreConfig.repoPath
        defaultMode = coreConfig.defaultMode.displayName
        overviewOutput = coreConfig.overviewOutput.displayName
        aiEnabled = coreConfig.aiEnabled
        locale = coreConfig.locale
        iCloudWarn = coreConfig.icloudWarn
        enableExtensionRules = coreConfig.enableExtensionRules
        enableKeywordRules = coreConfig.enableKeywordRules
        fallbackToInbox = coreConfig.fallbackToInbox
        allowReplaceDuringImport = coreConfig.allowReplaceDuringImport
    }
}

extension StorageMode {
    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "Moved":
            self = .moved
        case "Copied":
            self = .copied
        case "Indexed":
            self = .indexed
        default:
            throw CoreError.Config(reason: "unsupported storage mode: \(snapshotValue)")
        }
    }

    var displayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

extension OverviewOutput {
    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "GeneratedOnly":
            self = .generatedOnly
        case "RootAreaMatrixFile":
            self = .rootAreaMatrixFile
        default:
            throw CoreError.Config(reason: "unsupported overview output: \(snapshotValue)")
        }
    }

    var displayName: String {
        switch self {
        case .generatedOnly:
            "GeneratedOnly"
        case .rootAreaMatrixFile:
            "RootAreaMatrixFile"
        }
    }
}
