import AreaMatrixCoreBridgeContract
import AreaMatrixCoreBridgeRuntime
import Foundation

/// Keeps generated UniFFI calls and their first-order conversions out of the
/// runtime actor. This is the physical adapter boundary used during the
/// incremental migration to a standalone CoreBridge runtime module.
struct CoreBridgeGeneratedAdapter {
    private let runtimeCoordinator: CoreBridgeRuntimeCoordinator

    init(runtimeCoordinator: CoreBridgeRuntimeCoordinator) {
        self.runtimeCoordinator = runtimeCoordinator
    }

    private func require(_ boundary: CoreBridgeBoundary) throws {
        guard runtimeCoordinator.isDeclared(boundary) else {
            throw CoreBridgeRuntimeError.undeclaredBoundary(boundary)
        }
    }

    func loadConfig(repoPath: String) throws -> RepoConfigSnapshot {
        try require(.loadConfig)
        return try loadRepoConfig(repoPath: repoPath)
    }

    func updateConfig(repoPath: String, patch: RepoConfigPatch) throws -> RepoConfigSnapshot {
        try require(.updateConfig)
        return try updateRepoConfig(repoPath: repoPath, patch: patch)
    }

    func repoConfigPatch(
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

    func validateCoreRepoPath(repoPath: String) throws -> RepoPathValidation {
        try require(.validateRepoPath)
        return try validateRepoPath(repoPath: repoPath)
    }

    func validateCoreInitializedRepoPath(repoPath: String) throws -> RepoPathValidation {
        try require(.validateInitializedRepoPath)
        return try validateInitializedRepoPath(repoPath: repoPath)
    }

    func latestScanSession(repoPath: String) throws -> ScanSession? {
        try require(.getLatestScanSession)
        return try getLatestScanSession(repoPath: repoPath)
    }

    func resumeCoreScanSession(repoPath: String, scanSessionId: Int64) throws -> ReindexReport {
        try require(.resumeScanSession)
        return try resumeScanSession(repoPath: repoPath, scanSessionId: scanSessionId)
    }

    func predictCoreCategory(repoPath: String, filename: String) throws -> ClassifyResult {
        try require(.predictCategory)
        return try predictCategory(repoPath: repoPath, filename: filename)
    }

    func createCoreDiagnosticsSnapshot(repoPath: String) throws -> DiagnosticsSnapshot {
        try require(.createDiagnosticsSnapshot)
        return try createDiagnosticsSnapshot(repoPath: repoPath)
    }

    func getCoreVersion() throws -> String {
        try require(.getVersion)
        return getVersion()
    }

    func listCoreFiles(repoPath: String, filter: FileFilter) throws -> [FileEntry] {
        try require(.listFiles)
        return try listFiles(repoPath: repoPath, filter: filter)
    }

    func snapshots(
        from coreFiles: [FileEntry],
        repoPath: String,
        availabilityChecker: any FileAvailabilityChecking
    ) async -> [FileEntrySnapshot] {
        var snapshots: [FileEntrySnapshot] = []
        snapshots.reserveCapacity(coreFiles.count)
        for coreFile in coreFiles {
            let fileSnapshot = await snapshot(
                from: coreFile,
                repoPath: repoPath,
                availabilityChecker: availabilityChecker
            )
            snapshots.append(fileSnapshot)
        }
        return snapshots
    }

    func snapshot(
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

    func getCoreFile(repoPath: String, fileID: Int64) throws -> FileEntry {
        try require(.getFile)
        return try getFile(repoPath: repoPath, fileId: fileID)
    }

    func listCoreTreeJSON(repoPath: String, locale: String) throws -> String {
        try require(.listTreeJSON)
        return try listTreeJson(repoPath: repoPath, locale: locale)
    }

    func listCoreCommandTargets(repoPath: String, context: CommandIndexContext) throws -> CommandIndex {
        try require(.listCommandTargets)
        return try listCommandTargets(repoPath: repoPath, context: context)
    }

    func loadPlatformCapabilities(
        platform: PlatformId,
        appVersion: String
    ) throws -> PlatformCapabilities {
        try require(.getPlatformCapabilities)
        return try AreaMatrix.getPlatformCapabilities(platform: platform, appVersion: appVersion)
    }

    func inspectBindingContract(request: BindingContractRequest) throws -> BindingContractReport {
        try require(.inspectBindingContract)
        return try AreaMatrix.inspectBindingContract(request: request)
    }

    func listChanges(repoPath: String, filter: ChangeFilter) throws -> [ChangeLogEntry] {
        try require(.listChanges)
        return try AreaMatrix.listChanges(repoPath: repoPath, filter: filter)
    }

    func searchFiles(
        repoPath: String,
        query: String,
        filter: SearchFilter,
        sort: SearchSort,
        pagination: SearchPagination
    ) throws -> SearchResultPage {
        try require(.searchFiles)
        return try AreaMatrix.searchFiles(
            repoPath: repoPath,
            query: query,
            filter: filter,
            sort: sort,
            pagination: pagination
        )
    }

    func listFilterFacets(repoPath: String, query: SearchFacetQuery) throws -> SearchFacets {
        try require(.listFilterFacets)
        return try AreaMatrix.listFilterFacets(repoPath: repoPath, query: query)
    }

    func listAICalls(
        repoPath: String,
        filter: AiCallLogFilter,
        pagination: AiCallLogPagination
    ) throws -> AiCallLogPage {
        try require(.listAICalls)
        return try AreaMatrix.listAiCalls(repoPath: repoPath, filter: filter, pagination: pagination)
    }

    func clearAICallLog(
        repoPath: String,
        request: AiCallLogClearRequest
    ) throws -> AiCallLogClearReport {
        try require(.clearAICallLog)
        return try AreaMatrix.clearAiCallLog(repoPath: repoPath, request: request)
    }
}
