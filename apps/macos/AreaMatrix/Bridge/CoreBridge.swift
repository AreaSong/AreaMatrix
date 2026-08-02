import Foundation

actor CoreBridge {
    enum BridgeState: Equatable {
        case unavailable
        case generatedBindings
    }

    private let repoURL: URL?
    private let unavailableState: CoreBridgeUnavailableState
    private let availabilityChecker: any FileAvailabilityChecking
    let importObservability: CoreImportObservabilityRecorder
    let remoteProviderProbePerformer: any RemoteProviderProbePerforming

    init(
        repoURL: URL? = nil,
        unavailableState: CoreBridgeUnavailableState = .generatedBindingsUnavailable,
        availabilityChecker: any FileAvailabilityChecking = LocalFileAvailabilityChecker(),
        importObservability: CoreImportObservabilityRecorder = .defaultForCurrentProcess,
        remoteProviderProbePerformer: any RemoteProviderProbePerforming = RemoteProviderProbeService.shared
    ) {
        self.repoURL = repoURL
        self.unavailableState = unavailableState
        self.availabilityChecker = availabilityChecker
        self.importObservability = importObservability
        self.remoteProviderProbePerformer = remoteProviderProbePerformer
    }

    nonisolated var state: BridgeState {
        .generatedBindings
    }

    func currentState() -> CoreBridgeUnavailableState {
        unavailableState
    }

    nonisolated func coreAvailability() -> String {
        "generated-bindings"
    }

    func declaredBoundaries() -> [CoreBridgeBoundary] {
        CoreBridgeBoundary.allCases
    }

    func requireGeneratedBindings(for boundary: CoreBridgeBoundary) throws -> Never {
        throw CoreBridgeError.generatedBindingsUnavailable(boundary: boundary, state: unavailableState)
    }

    func getVersion() async throws -> String {
        getCoreVersion()
    }

    func coreVersion() async throws -> String {
        getCoreVersion()
    }

    func initializeLogging(level _: String) async throws -> Never {
        try requireGeneratedBindings(for: .initLogging)
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        try RepoPathValidationSnapshot(coreValidation: validateCoreRepoPath(repoPath: repoPath))
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        try RepoPathValidationSnapshot(coreValidation: validateCoreInitializedRepoPath(repoPath: repoPath))
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        try latestCoreScanSession(repoPath: repoPath).map(ScanSessionSnapshot.init(coreSession:))
    }

    func loadConfig(repoPath: String) async throws -> AppRepoConfigSnapshot {
        try AppRepoConfigSnapshot(coreConfig: loadCoreConfig(repoPath: repoPath))
    }

    func repositoryContentLocaleSnapshot(repoPath: String) async throws -> String {
        let interfaceLocale = AppLanguageRuntime.shared.resolvedIdentifier()
        let configuredLocale = try await Task.detached(priority: .userInitiated) {
            try loadCoreConfig(repoPath: repoPath).localePolicy.rawValue
        }.value
        return try RepositoryContentLanguage(snapshotValue: configuredLocale)
            .resolvedIdentifier(interfaceLocaleIdentifier: interfaceLocale)
    }

    func updateConfig(
        repoPath: String,
        from currentConfig: AppRepoConfigSnapshot,
        to updatedConfig: AppRepoConfigSnapshot
    ) async throws -> AppRepoConfigSnapshot {
        let patch = try repoConfigPatch(from: currentConfig, to: updatedConfig)
        return try AppRepoConfigSnapshot(coreConfig: updateCoreConfig(repoPath: repoPath, patch: patch))
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        let contentLocale = AppLanguageRuntime.shared.resolvedIdentifier()
        try initRepo(repoPath: repoPath, options: RepoInitOptions(
            mode: .createEmpty,
            createDefaultCategories: true,
            overviewOutput: .generatedOnly,
            localePolicy: .followInterface,
            contentLocale: ContentLocale(snapshotValue: contentLocale)
        ))
    }

    func adoptExistingRepository(repoPath: String) async throws {
        let contentLocale = AppLanguageRuntime.shared.resolvedIdentifier()
        try initRepo(repoPath: repoPath, options: RepoInitOptions(
            mode: .adoptExisting,
            createDefaultCategories: false,
            overviewOutput: .generatedOnly,
            localePolicy: .followInterface,
            contentLocale: ContentLocale(snapshotValue: contentLocale)
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
        try await Task.detached(priority: .userInitiated) {
            try DiagnosticsSnapshotSnapshot(coreSnapshot: createCoreDiagnosticsSnapshot(repoPath: repoPath))
        }.value
    }

    func latestScanSession() async throws -> Never {
        try requireGeneratedBindings(for: .getLatestScanSession)
    }

    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        try ReindexReportSnapshot(coreReport: resumeCoreScanSession(repoPath: repoPath, scanSessionId: scanSessionId))
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ClassifyResultSnapshot(coreResult: predictCoreCategory(repoPath: repoPath, filename: filename))
        }.value
    }

    func importFile(from _: URL) async throws -> Never {
        try requireGeneratedBindings(for: .importFile)
    }

    func deleteFile(id _: Int64, hard _: Bool) async throws -> Never {
        try requireGeneratedBindings(for: .deleteFile)
    }

    func renameFile(id _: Int64, newName _: String) async throws -> Never {
        try requireGeneratedBindings(for: .renameFile)
    }

    func moveToCategory(id _: Int64, category _: String) async throws -> Never {
        try requireGeneratedBindings(for: .moveToCategory)
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

    func makeFileEntrySnapshot(from coreFile: FileEntry, repoPath: String) async -> FileEntrySnapshot {
        await snapshot(from: coreFile, repoPath: repoPath, availabilityChecker: availabilityChecker)
    }

    func listTreeJSON(repoPath: String, locale: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try listCoreTreeJSON(repoPath: repoPath, locale: locale)
        }.value
    }

    func listCommandTargets(
        repoPath: String,
        context: CommandIndexRequestSnapshot
    ) async throws -> CoreCommandIndexSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreCommandIndexSnapshot(coreIndex: listCoreCommandTargets(
                repoPath: repoPath,
                context: CommandIndexContext(snapshot: context)
            ))
        }.value
    }

    func readNote(fileID _: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .readNote)
    }

    func writeNote(fileID _: Int64, contentMarkdown _: String) async throws -> Never {
        try requireGeneratedBindings(for: .writeNote)
    }

    func repoPathForDiagnostics() -> String? {
        repoURL?.path
    }
}

/// Process-scoped Core runtime used by the App composition root.
///
/// Feature tests and high-risk flows may still construct an isolated bridge
/// explicitly. Production service defaults share this instance so Core
/// observation, probe coordination, and actor state do not fan out across a
/// new bridge for every protocol lookup.
enum CoreBridgeRuntime {
    static let shared = CoreBridge()
}

extension CoreBridge: CoreVersionLoading {}

extension CoreBridge:
    CoreConfigurationLoading,
    CoreConfigurationUpdating,
    CoreVersionReading,
    CoreDiagnosticsCollecting,
    CoreErrorMapping,
    CoreCategoryPredicting,
    CoreCommandIndexing,
    CoreRepositoryInitializing,
    CoreInitializedRepositoryPathValidating,
    CoreRepositoryPathValidating,
    CoreScanSessionReading {}

private func loadCoreConfig(repoPath: String) throws -> RepoConfigSnapshot {
    try loadRepoConfig(repoPath: repoPath)
}

private func updateCoreConfig(repoPath: String, patch: RepoConfigPatch) throws -> RepoConfigSnapshot {
    try updateRepoConfig(repoPath: repoPath, patch: patch)
}

private func repoConfigPatch(
    from current: AppRepoConfigSnapshot,
    to updated: AppRepoConfigSnapshot
) throws -> RepoConfigPatch {
    try RepoConfigPatch(
        expectedRevision: current.revision,
        repoPath: current.repoPath == updated.repoPath ? nil : updated.repoPath,
        defaultMode: current.defaultMode == updated.defaultMode
            ? nil : StorageMode(snapshotValue: updated.defaultMode),
        overviewOutput: current.overviewOutput == updated.overviewOutput
            ? nil : OverviewOutput(snapshotValue: updated.overviewOutput),
        aiEnabled: current.aiEnabled == updated.aiEnabled ? nil : updated.aiEnabled,
        localePolicy: current.locale == updated.locale
            ? nil : RepositoryLocalePolicy(snapshotValue: updated.locale),
        icloudWarn: current.iCloudWarn == updated.iCloudWarn ? nil : updated.iCloudWarn,
        enableExtensionRules: current.enableExtensionRules == updated.enableExtensionRules
            ? nil : updated.enableExtensionRules,
        enableKeywordRules: current.enableKeywordRules == updated.enableKeywordRules
            ? nil : updated.enableKeywordRules,
        fallbackToInbox: current.fallbackToInbox == updated.fallbackToInbox
            ? nil : updated.fallbackToInbox,
        allowReplaceDuringImport: current.allowReplaceDuringImport == updated.allowReplaceDuringImport
            ? nil : updated.allowReplaceDuringImport
    )
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
        sourcePath: coreFile.sourcePath,
        coreStatus: coreFile.availabilityStatus
    )
    return FileEntrySnapshot(coreEntry: coreFile) { _, _ in availability }
}

private func getCoreFile(repoPath: String, fileID: Int64) throws -> FileEntry {
    try getFile(repoPath: repoPath, fileId: fileID)
}

private func listCoreTreeJSON(repoPath: String, locale: String) throws -> String {
    try listTreeJson(repoPath: repoPath, locale: locale)
}

private func listCoreCommandTargets(repoPath: String, context: CommandIndexContext) throws -> CommandIndex {
    try listCommandTargets(repoPath: repoPath, context: context)
}
