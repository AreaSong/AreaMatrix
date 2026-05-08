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
extension CoreScanSessionReading {
    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        throw CoreError.Internal(message: "scan session resume is unavailable")
    }
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

actor CoreBridge {
    enum BridgeState: Equatable, Sendable {
        case placeholder
        case generatedBindings
    }

    private let repoURL: URL?
    private let placeholderState: CoreBridgePlaceholderState
    private let availabilityChecker: any FileAvailabilityChecking

    init(
        repoURL: URL? = nil,
        placeholderState: CoreBridgePlaceholderState = .phase0,
        availabilityChecker: any FileAvailabilityChecking = LocalFileAvailabilityChecker()
    ) {
        self.repoURL = repoURL
        self.placeholderState = placeholderState
        self.availabilityChecker = availabilityChecker
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

    func getVersion() async throws -> String {
        getCoreVersion()
    }

    func coreVersion() async throws -> String {
        getCoreVersion()
    }

    func initializeLogging(level: String) async throws -> Never {
        try requireGeneratedBindings(for: .initLogging)
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(coreValidation: try validateCoreRepoPath(repoPath: repoPath))
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(coreValidation: try validateCoreInitializedRepoPath(repoPath: repoPath))
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

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(coreSnapshot: try createCoreDiagnosticsSnapshot(repoPath: repoPath))
    }

    func latestScanSession() async throws -> Never {
        try requireGeneratedBindings(for: .getLatestScanSession)
    }

    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        ReindexReportSnapshot(coreReport: try resumeCoreScanSession(repoPath: repoPath, scanSessionId: scanSessionId))
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        try await Task.detached(priority: .userInitiated) {
            ClassifyResultSnapshot(coreResult: try predictCoreCategory(repoPath: repoPath, filename: filename))
        }.value
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

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        let availabilityChecker = availabilityChecker
        return try await Task.detached(priority: .userInitiated) {
            let coreFiles = try listCoreFiles(repoPath: repoPath, filter: FileFilter(filter))
            return await snapshots(from: coreFiles, repoPath: repoPath, availabilityChecker: availabilityChecker)
        }.value
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        let availabilityChecker = availabilityChecker
        return try await Task.detached(priority: .userInitiated) {
            let coreFile = try getCoreFile(repoPath: repoPath, fileID: fileID)
            return await snapshot(from: coreFile, repoPath: repoPath, availabilityChecker: availabilityChecker)
        }.value
    }

    func listTreeJSON(repoPath: String, locale: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try listCoreTreeJSON(repoPath: repoPath, locale: locale)
        }.value
    }

    func readNote(fileID: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .readNote)
    }

    func writeNote(fileID: Int64, contentMarkdown: String) async throws -> Never {
        try requireGeneratedBindings(for: .writeNote)
    }

    func repoPathForDiagnostics() -> String? {
        repoURL?.path
    }
}

extension CoreBridge:
    CoreConfigurationLoading,
    CoreConfigurationUpdating,
    CoreVersionReading,
    CoreDiagnosticsCollecting,
    CoreErrorMapping,
    CoreCategoryPredicting,
    CoreRepositoryInitializing,
    CoreInitializedRepositoryPathValidating,
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

private func validateCoreInitializedRepoPath(repoPath: String) throws -> RepoPathValidation {
    try validateInitializedRepoPath(repoPath: repoPath)
}

private func latestCoreScanSession(repoPath: String) throws -> ScanSession? {
    try getLatestScanSession(repoPath: repoPath)
}

private func resumeCoreScanSession(repoPath: String, scanSessionId: Int64) throws -> ReindexReport {
    try resumeScanSession(repoPath: repoPath, scanSessionId: scanSessionId)
}

private func predictCoreCategory(repoPath: String, filename: String) throws -> ClassifyResult {
    try predictCategory(repoPath: repoPath, filename: filename)
}

private func createCoreDiagnosticsSnapshot(repoPath: String) throws -> DiagnosticsSnapshot {
    try createDiagnosticsSnapshot(repoPath: repoPath)
}

private func getCoreVersion() -> String {
    getVersion()
}

private func listCoreFiles(repoPath: String, filter: FileFilter) throws -> [FileEntry] {
    try listFiles(repoPath: repoPath, filter: filter)
}

private func snapshots(
    from coreFiles: [FileEntry],
    repoPath: String,
    availabilityChecker: any FileAvailabilityChecking
) async -> [FileEntrySnapshot] {
    var snapshots: [FileEntrySnapshot] = []
    snapshots.reserveCapacity(coreFiles.count)
    for coreFile in coreFiles {
        let fileSnapshot = await snapshot(from: coreFile, repoPath: repoPath, availabilityChecker: availabilityChecker)
        snapshots.append(fileSnapshot)
    }
    return snapshots
}

private func snapshot(
    from coreFile: FileEntry,
    repoPath: String,
    availabilityChecker: any FileAvailabilityChecking
) async -> FileEntrySnapshot {
    let availability = await availabilityChecker.availability(
        repoPath: repoPath,
        relativePath: coreFile.path,
        sourcePath: coreFile.sourcePath
    )
    return FileEntrySnapshot(coreEntry: coreFile) { _, _ in availability }
}

private func getCoreFile(repoPath: String, fileID: Int64) throws -> FileEntry {
    try getFile(repoPath: repoPath, fileId: fileID)
}

private func listCoreTreeJSON(repoPath: String, locale: String) throws -> String {
    try listTreeJson(repoPath: repoPath, locale: locale)
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
