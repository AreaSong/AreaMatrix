import Foundation

actor CoreBridge {
    enum BridgeState: Equatable {
        case unavailable
        case generatedBindings
    }

    private let repoURL: URL?
    private let unavailableState: CoreBridgeUnavailableState
    private let availabilityChecker: any FileAvailabilityChecking
    let remoteProviderProbePerformer: any RemoteProviderProbePerforming

    init(
        repoURL: URL? = nil,
        unavailableState: CoreBridgeUnavailableState = .generatedBindingsUnavailable,
        availabilityChecker: any FileAvailabilityChecking = LocalFileAvailabilityChecker(),
        remoteProviderProbePerformer: any RemoteProviderProbePerforming = RemoteProviderProbeService.shared
    ) {
        self.repoURL = repoURL
        self.unavailableState = unavailableState
        self.availabilityChecker = availabilityChecker
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

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        try RepoConfigSnapshot(coreConfig: loadCoreConfig(repoPath: repoPath))
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        try updateCoreConfig(
            repoPath: repoPath,
            newConfig: RepoConfig(
                repoPath: newConfig.repoPath,
                defaultMode: StorageMode(snapshotValue: newConfig.defaultMode),
                overviewOutput: OverviewOutput(snapshotValue: newConfig.overviewOutput),
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

    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex {
        try await Task.detached(priority: .userInitiated) {
            try listCoreCommandTargets(repoPath: repoPath, context: context)
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
