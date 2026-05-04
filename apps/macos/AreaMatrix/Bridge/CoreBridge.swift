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

protocol CoreRepositoryInitializing: Sendable {
    func initializeEmptyRepository(repoPath: String) async throws
    func adoptExistingRepository(repoPath: String) async throws
}

protocol CoreScanSessionReading: Sendable {
    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot?
}

enum RepoInitModeSnapshot: String, Equatable, Sendable {
    case createEmpty = "CreateEmpty"
    case adoptExisting = "AdoptExisting"
}

enum ScanSessionKindSnapshot: String, Equatable, Sendable {
    case adopt = "Adopt"
    case reindex = "Reindex"
}

enum ScanSessionStatusSnapshot: String, Equatable, Sendable {
    case running = "Running"
    case completed = "Completed"
    case paused = "Paused"
    case failed = "Failed"
    case interrupted = "Interrupted"
}

enum RepoPathIssueSnapshot: String, Equatable, Sendable {
    case missingPath = "MissingPath"
    case notDirectory = "NotDirectory"
    case notReadable = "NotReadable"
    case notWritable = "NotWritable"
    case nonEmptyDirectory = "NonEmptyDirectory"
    case alreadyInitialized = "AlreadyInitialized"
    case insideAreaMatrix = "InsideAreaMatrix"
    case iCloudPath = "ICloudPath"
    case unfinishedScanSession = "UnfinishedScanSession"
}

struct RepoPathValidationSnapshot: Equatable, Sendable {
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

struct RepositoryInitializationDraft: Equatable, Sendable {
    var validation: RepoPathValidationSnapshot
    var mode: RepoInitModeSnapshot
    var scanSession: ScanSessionSnapshot?
}

struct ScanSessionSnapshot: Equatable, Sendable {
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

struct RepoConfigSnapshot: Equatable, Sendable {
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

private extension RepoConfigSnapshot {
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

private extension ScanSessionSnapshot {
    init(coreSession: ScanSession) {
        id = coreSession.id
        kind = ScanSessionKindSnapshot(coreKind: coreSession.kind)
        status = ScanSessionStatusSnapshot(coreStatus: coreSession.status)
        lastPath = coreSession.lastPath
        inserted = coreSession.inserted
        updated = coreSession.updated
        skipped = coreSession.skipped
        startedAt = coreSession.startedAt
        updatedAt = coreSession.updatedAt
        finishedAt = coreSession.finishedAt
        errors = coreSession.errors
    }
}

private extension ScanSessionKindSnapshot {
    init(coreKind: ScanSessionKind) {
        switch coreKind {
        case .adopt:
            self = .adopt
        case .reindex:
            self = .reindex
        }
    }
}

private extension ScanSessionStatusSnapshot {
    init(coreStatus: ScanSessionStatus) {
        switch coreStatus {
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .paused:
            self = .paused
        case .failed:
            self = .failed
        case .interrupted:
            self = .interrupted
        }
    }
}

private extension RepoPathValidationSnapshot {
    init(coreValidation: RepoPathValidation) {
        let environment = RepositoryPathEnvironmentSnapshot.inspect(repoPath: coreValidation.repoPath)

        repoPath = coreValidation.repoPath
        exists = coreValidation.exists
        isDirectory = coreValidation.isDirectory
        isReadable = coreValidation.isReadable
        isWritable = coreValidation.isWritable
        isEmpty = coreValidation.isEmpty
        isInitialized = coreValidation.isInitialized
        isInsideAreaMatrix = coreValidation.isInsideAreaMatrix
        isICloudPath = coreValidation.isIcloudPath
        hasUnfinishedScanSession = coreValidation.hasUnfinishedScanSession
        availableCapacityBytes = environment.availableCapacityBytes
        isExternalVolume = environment.isExternalVolume
        recommendedMode = coreValidation.recommendedMode.map(RepoInitModeSnapshot.init(coreMode:))
        issues = coreValidation.issues.map(RepoPathIssueSnapshot.init(coreIssue:))
    }
}

private struct RepositoryPathEnvironmentSnapshot {
    var availableCapacityBytes: Int64?
    var isExternalVolume: Bool?

    static func inspect(repoPath: String) -> RepositoryPathEnvironmentSnapshot {
        do {
            let keys: Set<URLResourceKey> = [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsInternalKey,
            ]
            let values = try URL(fileURLWithPath: repoPath).resourceValues(forKeys: keys)
            return RepositoryPathEnvironmentSnapshot(
                availableCapacityBytes: values.volumeAvailableCapacityForImportantUsage ??
                    values.volumeAvailableCapacity.map(Int64.init),
                isExternalVolume: values.volumeIsInternal.map { !$0 }
            )
        } catch {
            return RepositoryPathEnvironmentSnapshot(availableCapacityBytes: nil, isExternalVolume: nil)
        }
    }
}

private extension RepoInitModeSnapshot {
    init(coreMode: RepoInitMode) {
        switch coreMode {
        case .createEmpty:
            self = .createEmpty
        case .adoptExisting:
            self = .adoptExisting
        }
    }
}

private extension RepoPathIssueSnapshot {
    init(coreIssue: RepoPathIssue) {
        switch coreIssue {
        case .missingPath:
            self = .missingPath
        case .notDirectory:
            self = .notDirectory
        case .notReadable:
            self = .notReadable
        case .notWritable:
            self = .notWritable
        case .nonEmptyDirectory:
            self = .nonEmptyDirectory
        case .alreadyInitialized:
            self = .alreadyInitialized
        case .insideAreaMatrix:
            self = .insideAreaMatrix
        case .iCloudPath:
            self = .iCloudPath
        case .unfinishedScanSession:
            self = .unfinishedScanSession
        }
    }
}

actor CoreBridge {
    enum BridgeState: Equatable, Sendable {
        case placeholder
        case generatedBindings
    }

    private let repoURL: URL?
    private let placeholderState: CoreBridgePlaceholderState

    init(repoURL: URL? = nil, placeholderState: CoreBridgePlaceholderState = .phase0) {
        self.repoURL = repoURL
        self.placeholderState = placeholderState
    }

    nonisolated var state: BridgeState {
        .generatedBindings
    }

    func currentState() -> CoreBridgePlaceholderState {
        placeholderState
    }

    nonisolated func coreAvailability() -> String {
        "generated-bindings"
    }

    func declaredBoundaries() -> [CoreBridgeBoundary] {
        CoreBridgeBoundary.allCases
    }

    func requireGeneratedBindings(for boundary: CoreBridgeBoundary) throws -> Never {
        throw CoreBridgeError.generatedBindingsUnavailable(boundary: boundary, state: placeholderState)
    }

    func getVersion() async throws -> Never {
        try requireGeneratedBindings(for: .getVersion)
    }

    func initializeLogging(level: String) async throws -> Never {
        try requireGeneratedBindings(for: .initLogging)
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(coreValidation: try validateCoreRepoPath(repoPath: repoPath))
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        try latestCoreScanSession(repoPath: repoPath).map(ScanSessionSnapshot.init(coreSession:))
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        RepoConfigSnapshot(coreConfig: try loadCoreConfig(repoPath: repoPath))
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        try updateCoreConfig(
            repoPath: repoPath,
            newConfig: RepoConfig(
                repoPath: newConfig.repoPath,
                defaultMode: try StorageMode(snapshotValue: newConfig.defaultMode),
                overviewOutput: try OverviewOutput(snapshotValue: newConfig.overviewOutput),
                aiEnabled: newConfig.aiEnabled,
                locale: newConfig.locale,
                icloudWarn: newConfig.iCloudWarn,
                enableExtensionRules: newConfig.enableExtensionRules,
                enableKeywordRules: newConfig.enableKeywordRules,
                fallbackToInbox: newConfig.fallbackToInbox,
                allowReplaceDuringImport: newConfig.allowReplaceDuringImport
            )
        )
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        try initRepo(repoPath: repoPath, options: RepoInitOptions(
            mode: .createEmpty,
            createDefaultCategories: true,
            overviewOutput: .generatedOnly
        ))
    }

    func adoptExistingRepository(repoPath: String) async throws {
        try initRepo(repoPath: repoPath, options: RepoInitOptions(
            mode: .adoptExisting,
            createDefaultCategories: false,
            overviewOutput: .generatedOnly
        ))
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(coreMapping: mapCoreErrorFromCore(error))
    }

    func recoverOnStartup() async throws -> Never {
        try requireGeneratedBindings(for: .recoverOnStartup)
    }

    func reindexFromFilesystem() async throws -> Never {
        try requireGeneratedBindings(for: .reindexFromFilesystem)
    }

    func latestScanSession() async throws -> Never {
        try requireGeneratedBindings(for: .getLatestScanSession)
    }

    func resumeScanSession(id: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .resumeScanSession)
    }

    func predictCategory(filename: String) async throws -> Never {
        try requireGeneratedBindings(for: .predictCategory)
    }

    func importFile(from sourceURL: URL) async throws -> Never {
        try requireGeneratedBindings(for: .importFile)
    }

    func deleteFile(id: Int64, hard: Bool) async throws -> Never {
        try requireGeneratedBindings(for: .deleteFile)
    }

    func renameFile(id: Int64, newName: String) async throws -> Never {
        try requireGeneratedBindings(for: .renameFile)
    }

    func moveToCategory(id: Int64, category: String) async throws -> Never {
        try requireGeneratedBindings(for: .moveToCategory)
    }

    func restoreFile(id: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .restoreFile)
    }

    func listFiles() async throws -> Never {
        try requireGeneratedBindings(for: .listFiles)
    }

    func getFile(id: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .getFile)
    }

    func listChanges() async throws -> Never {
        try requireGeneratedBindings(for: .listChanges)
    }

    func listTreeJSON(locale: String) async throws -> Never {
        try requireGeneratedBindings(for: .listTreeJSON)
    }

    func readNote(fileID: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .readNote)
    }

    func writeNote(fileID: Int64, contentMarkdown: String) async throws -> Never {
        try requireGeneratedBindings(for: .writeNote)
    }

    func syncExternalChanges() async throws -> Never {
        try requireGeneratedBindings(for: .syncExternalChanges)
    }

    func getFSEventCursor() async throws -> Never {
        try requireGeneratedBindings(for: .getFSEventCursor)
    }

    func setFSEventCursor(_ cursor: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .setFSEventCursor)
    }

    func repoPathForDiagnostics() -> String? {
        repoURL?.path
    }
}

extension CoreBridge:
    CoreConfigurationLoading,
    CoreConfigurationUpdating,
    CoreErrorMapping,
    CoreRepositoryInitializing,
    CoreRepositoryPathValidating,
    CoreScanSessionReading {}

private func loadCoreConfig(repoPath: String) throws -> RepoConfig {
    try loadConfig(repoPath: repoPath)
}

private func updateCoreConfig(repoPath: String, newConfig: RepoConfig) throws {
    try updateConfig(repoPath: repoPath, newConfig: newConfig)
}

private func validateCoreRepoPath(repoPath: String) throws -> RepoPathValidation {
    try validateRepoPath(repoPath: repoPath)
}

private func latestCoreScanSession(repoPath: String) throws -> ScanSession? {
    try getLatestScanSession(repoPath: repoPath)
}

private extension StorageMode {
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
            return "Moved"
        case .copied:
            return "Copied"
        case .indexed:
            return "Indexed"
        }
    }
}

private extension OverviewOutput {
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
            return "GeneratedOnly"
        case .rootAreaMatrixFile:
            return "RootAreaMatrixFile"
        }
    }
}
