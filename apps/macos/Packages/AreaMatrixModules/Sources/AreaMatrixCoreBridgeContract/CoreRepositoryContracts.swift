/// Stable repository lifecycle contracts consumed by the App composition and
/// feature models. Core DTO conversion and filesystem inspection stay App-owned.
public protocol CoreConfigurationLoading: Sendable {
    func loadConfig(repoPath: String) async throws -> AppRepoConfigSnapshot
}

public protocol CoreConfigurationUpdating: Sendable {
    func updateConfig(
        repoPath: String,
        from currentConfig: AppRepoConfigSnapshot,
        to updatedConfig: AppRepoConfigSnapshot
    ) async throws -> AppRepoConfigSnapshot
}

public protocol CoreRepositoryPathValidating: Sendable {
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot
}

public protocol CoreInitializedRepositoryPathValidating: Sendable {
    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot
}

public protocol CoreRepositoryInitializing: Sendable {
    func initializeEmptyRepository(repoPath: String) async throws
    func adoptExistingRepository(repoPath: String) async throws
}

public protocol CoreScanSessionReading: Sendable {
    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot?
    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot
}

public enum RepoInitModeSnapshot: String, Equatable, Sendable {
    case createEmpty = "CreateEmpty"
    case adoptExisting = "AdoptExisting"
}

public enum ScanSessionKindSnapshot: String, Equatable, Sendable {
    case adopt = "Adopt"
    case reindex = "Reindex"
}

public enum ScanSessionStatusSnapshot: String, Equatable, Sendable {
    case running = "Running"
    case completed = "Completed"
    case paused = "Paused"
    case failed = "Failed"
    case interrupted = "Interrupted"
}

public enum RepoPathIssueSnapshot: String, Equatable, Sendable {
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

public struct RepoPathValidationSnapshot: Equatable, Sendable {
    public var repoPath: String
    public var exists: Bool
    public var isDirectory: Bool
    public var isReadable: Bool
    public var isWritable: Bool
    public var isEmpty: Bool
    public var isInitialized: Bool
    public var isInsideAreaMatrix: Bool
    public var isICloudPath: Bool
    public var hasUnfinishedScanSession: Bool
    public var availableCapacityBytes: Int64?
    public var isExternalVolume: Bool?
    public var recommendedMode: RepoInitModeSnapshot?
    public var issues: [RepoPathIssueSnapshot]

    public init(
        repoPath: String,
        exists: Bool,
        isDirectory: Bool,
        isReadable: Bool,
        isWritable: Bool,
        isEmpty: Bool,
        isInitialized: Bool,
        isInsideAreaMatrix: Bool,
        isICloudPath: Bool,
        hasUnfinishedScanSession: Bool,
        availableCapacityBytes: Int64?,
        isExternalVolume: Bool?,
        recommendedMode: RepoInitModeSnapshot?,
        issues: [RepoPathIssueSnapshot]
    ) {
        self.repoPath = repoPath
        self.exists = exists
        self.isDirectory = isDirectory
        self.isReadable = isReadable
        self.isWritable = isWritable
        self.isEmpty = isEmpty
        self.isInitialized = isInitialized
        self.isInsideAreaMatrix = isInsideAreaMatrix
        self.isICloudPath = isICloudPath
        self.hasUnfinishedScanSession = hasUnfinishedScanSession
        self.availableCapacityBytes = availableCapacityBytes
        self.isExternalVolume = isExternalVolume
        self.recommendedMode = recommendedMode
        self.issues = issues
    }

    public static let minimumUsableCapacityBytes: Int64 = 512 * 1024 * 1024

    public var hasInsufficientAvailableCapacity: Bool {
        availableCapacityBytes.map { $0 < Self.minimumUsableCapacityBytes } ?? false
    }

    public var hasMissingEnvironmentChecks: Bool {
        availableCapacityBytes == nil || isExternalVolume == nil
    }
}

public struct RepositoryInitializationDraft: Equatable, Sendable {
    public var validation: RepoPathValidationSnapshot
    public var mode: RepoInitModeSnapshot
    public var scanSession: ScanSessionSnapshot?

    public init(
        validation: RepoPathValidationSnapshot,
        mode: RepoInitModeSnapshot,
        scanSession: ScanSessionSnapshot?
    ) {
        self.validation = validation
        self.mode = mode
        self.scanSession = scanSession
    }
}

public struct ScanSessionSnapshot: Equatable, Sendable {
    public var id: Int64
    public var kind: ScanSessionKindSnapshot
    public var status: ScanSessionStatusSnapshot
    public var lastPath: String?
    public var inserted: Int64
    public var updated: Int64
    public var skipped: Int64
    public var startedAt: Int64
    public var updatedAt: Int64
    public var finishedAt: Int64?
    public var errors: [String]

    public init(
        id: Int64,
        kind: ScanSessionKindSnapshot,
        status: ScanSessionStatusSnapshot,
        lastPath: String?,
        inserted: Int64,
        updated: Int64,
        skipped: Int64,
        startedAt: Int64,
        updatedAt: Int64,
        finishedAt: Int64?,
        errors: [String]
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.lastPath = lastPath
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
        self.errors = errors
    }
}

public struct ReindexReportSnapshot: Equatable, Sendable {
    public var scanSessionId: Int64?
    public var inserted: Int64
    public var updated: Int64
    public var skipped: Int64
    public var errors: [String]

    public init(
        scanSessionId: Int64?,
        inserted: Int64,
        updated: Int64,
        skipped: Int64,
        errors: [String]
    ) {
        self.scanSessionId = scanSessionId
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.errors = errors
    }
}

public struct AppRepoConfigSnapshot: Equatable, Sendable {
    public var repoPath: String
    public var revision: Int64
    public var defaultMode: String
    public var overviewOutput: String
    public var aiEnabled: Bool
    public var locale: String
    public var iCloudWarn: Bool
    public var enableExtensionRules: Bool
    public var enableKeywordRules: Bool
    public var fallbackToInbox: Bool
    public var allowReplaceDuringImport: Bool

    public init(
        repoPath: String,
        revision: Int64,
        defaultMode: String,
        overviewOutput: String,
        aiEnabled: Bool,
        locale: String,
        iCloudWarn: Bool,
        enableExtensionRules: Bool,
        enableKeywordRules: Bool,
        fallbackToInbox: Bool,
        allowReplaceDuringImport: Bool
    ) {
        self.repoPath = repoPath
        self.revision = revision
        self.defaultMode = defaultMode
        self.overviewOutput = overviewOutput
        self.aiEnabled = aiEnabled
        self.locale = locale
        self.iCloudWarn = iCloudWarn
        self.enableExtensionRules = enableExtensionRules
        self.enableKeywordRules = enableKeywordRules
        self.fallbackToInbox = fallbackToInbox
        self.allowReplaceDuringImport = allowReplaceDuringImport
    }
}
