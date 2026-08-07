import AreaMatrixCoreBridgeContract
import AreaMatrixCoreBridgeRuntime
import Foundation

actor CoreBridge {
    typealias BridgeState = CoreBridgeRuntimeState

    private let repoURL: URL?
    private let unavailableState: CoreBridgeUnavailableState
    private let availabilityChecker: any FileAvailabilityChecking
    let generatedAdapter: CoreBridgeGeneratedAdapter
    let interfaceLocaleIdentifierProvider: @Sendable () -> String
    let importObservability: CoreImportObservabilityRecorder
    let remoteProviderProbePerformer: any RemoteProviderProbePerforming
    private let runtimeCoordinator: CoreBridgeRuntimeCoordinator

    init(
        repoURL: URL? = nil,
        unavailableState: CoreBridgeUnavailableState = .generatedBindingsUnavailable,
        availabilityChecker: any FileAvailabilityChecking = LocalFileAvailabilityChecker(),
        interfaceLocaleIdentifier: @escaping @Sendable () -> String = { "en" },
        importObservability: CoreImportObservabilityRecorder = .defaultForCurrentProcess,
        remoteProviderProbePerformer: any RemoteProviderProbePerforming = RemoteProviderProbeService.shared,
        runtimeCoordinator: CoreBridgeRuntimeCoordinator = CoreBridgeRuntimeCoordinator()
    ) {
        self.repoURL = repoURL
        self.unavailableState = unavailableState
        self.availabilityChecker = availabilityChecker
        interfaceLocaleIdentifierProvider = interfaceLocaleIdentifier
        self.importObservability = importObservability
        self.remoteProviderProbePerformer = remoteProviderProbePerformer
        self.runtimeCoordinator = runtimeCoordinator
        self.generatedAdapter = CoreBridgeGeneratedAdapter(runtimeCoordinator: runtimeCoordinator)
    }

    nonisolated var state: CoreBridgeRuntimeState {
        runtimeCoordinator.state
    }

    func currentState() -> CoreBridgeUnavailableState {
        unavailableState
    }

    nonisolated func coreAvailability() -> String {
        runtimeCoordinator.coreAvailability()
    }

    nonisolated func isDeclared(_ boundary: CoreBridgeBoundary) -> Bool {
        runtimeCoordinator.isDeclared(boundary)
    }

    func declaredBoundaries() async -> [CoreBridgeBoundary] {
        await runtimeCoordinator.declaredBoundaries()
    }

    func requireGeneratedBindings(for boundary: CoreBridgeBoundary) throws -> Never {
        throw CoreBridgeError.generatedBindingsUnavailable(boundary: boundary, state: unavailableState)
    }

    func getVersion() async throws -> String {
        try generatedAdapter.getCoreVersion()
    }

    func coreVersion() async throws -> String {
        try generatedAdapter.getCoreVersion()
    }

    func initializeLogging(level _: String) async throws -> Never {
        try requireGeneratedBindings(for: .initLogging)
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        try RepoPathValidationSnapshot(
            coreValidation: generatedAdapter.validateCoreRepoPath(repoPath: repoPath)
        )
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        try RepoPathValidationSnapshot(
            coreValidation: generatedAdapter.validateCoreInitializedRepoPath(repoPath: repoPath)
        )
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        try generatedAdapter.latestScanSession(repoPath: repoPath)
            .map(ScanSessionSnapshot.init(coreSession:))
    }

    func loadConfig(repoPath: String) async throws -> AppRepoConfigSnapshot {
        try AppRepoConfigSnapshot(coreConfig: generatedAdapter.loadConfig(repoPath: repoPath))
    }

    func repositoryContentLocaleSnapshot(repoPath: String) async throws -> String {
        let interfaceLocale = interfaceLocaleIdentifierProvider()
        let adapter = generatedAdapter
        let configuredLocale = try await Task.detached(priority: .userInitiated) {
            try adapter.loadConfig(repoPath: repoPath).localePolicy.rawValue
        }.value
        return try RepositoryContentLanguage(snapshotValue: configuredLocale)
            .resolvedIdentifier(interfaceLocaleIdentifier: interfaceLocale)
    }

    func updateConfig(
        repoPath: String,
        from currentConfig: AppRepoConfigSnapshot,
        to updatedConfig: AppRepoConfigSnapshot
    ) async throws -> AppRepoConfigSnapshot {
        let patch = try generatedAdapter.repoConfigPatch(from: currentConfig, to: updatedConfig)
        return try AppRepoConfigSnapshot(
            coreConfig: generatedAdapter.updateConfig(repoPath: repoPath, patch: patch)
        )
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        let contentLocale = interfaceLocaleIdentifierProvider()
        try initRepo(repoPath: repoPath, options: RepoInitOptions(
            mode: .createEmpty,
            createDefaultCategories: true,
            overviewOutput: .generatedOnly,
            localePolicy: .followInterface,
            contentLocale: ContentLocale(snapshotValue: contentLocale)
        ))
    }

    func adoptExistingRepository(repoPath: String) async throws {
        let contentLocale = interfaceLocaleIdentifierProvider()
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
        let adapter = generatedAdapter
        return try await Task.detached(priority: .userInitiated) {
            try DiagnosticsSnapshotSnapshot(
                coreSnapshot: adapter.createCoreDiagnosticsSnapshot(repoPath: repoPath)
            )
        }.value
    }

    func latestScanSession() async throws -> Never {
        try requireGeneratedBindings(for: .getLatestScanSession)
    }

    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        try ReindexReportSnapshot(
            coreReport: generatedAdapter.resumeCoreScanSession(
                repoPath: repoPath,
                scanSessionId: scanSessionId
            )
        )
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        let adapter = generatedAdapter
        return try await Task.detached(priority: .userInitiated) {
            try ClassifyResultSnapshot(
                coreResult: adapter.predictCoreCategory(
                    repoPath: repoPath,
                    filename: filename
                )
            )
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
        let adapter = generatedAdapter
        return try await Task.detached(priority: .userInitiated) {
            let coreFiles = try adapter.listCoreFiles(
                repoPath: repoPath,
                filter: FileFilter(filter)
            )
            return await adapter.snapshots(
                from: coreFiles,
                repoPath: repoPath,
                availabilityChecker: availabilityChecker
            )
        }.value
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        let availabilityChecker = availabilityChecker
        let adapter = generatedAdapter
        return try await Task.detached(priority: .userInitiated) {
            let coreFile = try adapter.getCoreFile(repoPath: repoPath, fileID: fileID)
            return await adapter.snapshot(
                from: coreFile,
                repoPath: repoPath,
                availabilityChecker: availabilityChecker
            )
        }.value
    }

    func makeFileEntrySnapshot(from coreFile: FileEntry, repoPath: String) async -> FileEntrySnapshot {
        await generatedAdapter.snapshot(
            from: coreFile,
            repoPath: repoPath,
            availabilityChecker: availabilityChecker
        )
    }

    func listTreeJSON(repoPath: String, locale: String) async throws -> String {
        let adapter = generatedAdapter
        return try await Task.detached(priority: .userInitiated) {
            try adapter.listCoreTreeJSON(repoPath: repoPath, locale: locale)
        }.value
    }

    func listCommandTargets(
        repoPath: String,
        context: CommandIndexRequestSnapshot
    ) async throws -> CoreCommandIndexSnapshot {
        let adapter = generatedAdapter
        return try await Task.detached(priority: .userInitiated) {
            try CoreCommandIndexSnapshot(coreIndex: adapter.listCoreCommandTargets(
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
