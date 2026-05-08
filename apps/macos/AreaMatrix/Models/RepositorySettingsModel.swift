import Combine
import Foundation

struct RepositorySettingsLoadError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct RepositorySettingsSyncError: Equatable, Sendable {
    var message: String
    var recovery: String
}

enum RepositorySettingsDatabaseStatus: Equatable, Sendable {
    case ok
    case locked
    case needsRecovery

    var label: String {
        switch self {
        case .ok:
            return "OK"
        case .locked:
            return "Locked"
        case .needsRecovery:
            return "Needs recovery"
        }
    }
}

enum RepositorySettingsWatcherStatus: Equatable, Sendable {
    case running
    case paused

    var label: String {
        switch self {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        }
    }
}

struct RepositorySettingsHealthSummary: Equatable, Sendable {
    var databaseStatus: RepositorySettingsDatabaseStatus
    var schemaVersion: Int64?
    var filesIndexed: Int64?
    var lastScanAt: Int64?
    var watcherStatus: RepositorySettingsWatcherStatus
}

struct RepositorySettingsHealthError: Equatable, Sendable {
    var databaseStatus: RepositorySettingsDatabaseStatus
    var message: String
    var recovery: String
}

struct RepositorySettingsSummary: Equatable, Sendable {
    var repositoryName: String
    var location: String
    var metadataStatus: String
    var overviewMode: String
    var generatedPath: String
    var rootFile: String
    var readmePolicy: String

    init(config: RepoConfigSnapshot, fallbackRepoPath: String) {
        let resolvedPath = config.repoPath.isEmpty || config.repoPath != fallbackRepoPath
            ? fallbackRepoPath
            : config.repoPath
        repositoryName = Self.repositoryName(for: resolvedPath)
        location = resolvedPath
        metadataStatus = Self.metadataStatus(for: resolvedPath)
        overviewMode = Self.overviewModeLabel(for: config.overviewOutput)
        generatedPath = ".areamatrix/generated/root.md"
        rootFile = config.overviewOutput == "RootAreaMatrixFile" ? "AREAMATRIX.md" : "Off"
        readmePolicy = "User file, never managed by AreaMatrix"
    }

    private static func repositoryName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "AreaMatrix" : name
    }

    private static func metadataStatus(for path: String) -> String {
        let metadataURL = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
        return FileManager.default.fileExists(atPath: metadataURL.path)
            ? ".areamatrix/ found"
            : ".areamatrix/ missing"
    }

    private static func overviewModeLabel(for value: String) -> String {
        value == "RootAreaMatrixFile" ? "Root AREAMATRIX.md enabled" : "Generated only"
    }
}

@MainActor
final class RepositorySettingsModel: ObservableObject {
    enum LoadState: Equatable, Sendable {
        case loading
        case loaded(RepositorySettingsSummary)
        case failed(RepositorySettingsLoadError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var loadedConfig: RepoConfigSnapshot?
    @Published private(set) var healthSummary: RepositorySettingsHealthSummary?
    @Published private(set) var healthError: RepositorySettingsHealthError?
    @Published private(set) var syncError: RepositorySettingsSyncError?

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let repositoryOpener: any CoreEmptyRepositoryOpening
    private let fileLister: (any CoreFileListing)?
    private let scanSessionReader: any CoreScanSessionReading
    private let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        repositoryOpener: any CoreEmptyRepositoryOpening = CoreBridge(),
        fileLister: (any CoreFileListing)? = nil,
        scanSessionReader: any CoreScanSessionReading = CoreBridge(),
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading = SQLiteExistingRepositoryMetadataReader(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.repositoryOpener = repositoryOpener
        self.fileLister = fileLister ?? (repositoryOpener as? any CoreFileListing)
        self.scanSessionReader = scanSessionReader
        self.existingRepositoryMetadataReader = existingRepositoryMetadataReader
        self.errorMapper = errorMapper
    }

    var isLoading: Bool {
        loadState == .loading
    }

    var summary: RepositorySettingsSummary? {
        guard case .loaded(let summary) = loadState else { return nil }
        return summary
    }

    var loadError: RepositorySettingsLoadError? {
        guard case .failed(let error) = loadState else { return nil }
        return error
    }

    func load() async {
        loadState = .loading
        healthSummary = nil
        healthError = nil
        syncError = nil
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            let effectiveConfig = config.withRepositoryPath(repoPath)
            loadedConfig = effectiveConfig

            if shouldSyncRepositoryPath(from: config) {
                do {
                    try await updater.updateConfig(repoPath: repoPath, newConfig: effectiveConfig)
                } catch {
                    syncError = await syncError(for: error)
                }
            }

            loadState = .loaded(RepositorySettingsSummary(config: effectiveConfig, fallbackRepoPath: repoPath))
            await refreshHealth()
        } catch {
            loadedConfig = nil
            loadState = .failed(await loadError(for: error))
        }
    }

    private func refreshHealth() async {
        var summary = RepositorySettingsHealthSummary(
            databaseStatus: .ok,
            schemaVersion: nil,
            filesIndexed: nil,
            lastScanAt: nil,
            watcherStatus: .paused
        )

        do {
            let metadata = try await existingRepositoryMetadataReader.metadata(repoPath: repoPath)
            summary.schemaVersion = metadata.schemaVersion
        } catch {
            summary = await applyHealthError(error, summary: summary)
            healthSummary = summary
            return
        }

        do {
            summary.filesIndexed = try await indexedFileCount()
        } catch {
            summary = await applyHealthError(error, summary: summary)
            healthSummary = summary
            return
        }

        do {
            let scanSession = try await scanSessionReader.latestScanSession(repoPath: repoPath)
            if let scanSession {
                summary.lastScanAt = scanSession.finishedAt ?? scanSession.updatedAt
                summary.watcherStatus = scanSession.status == .running ? .running : .paused
            }
        } catch {
            summary = await applyHealthError(error, summary: summary)
        }

        healthSummary = summary
    }

    private func indexedFileCount() async throws -> Int64 {
        guard let fileLister else {
            let opening = try await repositoryOpener.openConfiguredRepository(repoPath: repoPath)
            return opening.tree.totalFileCount
        }

        return try await Self.countIndexedFiles(repoPath: repoPath, fileLister: fileLister)
    }

    private static func countIndexedFiles(
        repoPath: String,
        fileLister: any CoreFileListing
    ) async throws -> Int64 {
        let pageSize: Int64 = 1_000
        var offset: Int64 = 0
        var total: Int64 = 0

        while true {
            let files = try await fileLister.listFiles(
                repoPath: repoPath,
                filter: FileFilterSnapshot(
                    category: nil,
                    includeDeleted: false,
                    importedAfter: nil,
                    importedBefore: nil,
                    limit: pageSize,
                    offset: offset
                )
            )
            total += Int64(files.count)
            guard Int64(files.count) == pageSize else {
                return total
            }
            offset += pageSize
        }
    }

    private func applyHealthError(
        _ error: Error,
        summary: RepositorySettingsHealthSummary
    ) async -> RepositorySettingsHealthSummary {
        var updatedSummary = summary
        if let coreError = error as? CoreError {
            let mappingResult = await errorMapper.mapCoreError(coreError)
            let status = databaseStatus(for: mappingResult)
            updatedSummary.databaseStatus = status
            healthError = RepositorySettingsHealthError(
                databaseStatus: status,
                message: mappingResult.userMessage,
                recovery: mappingResult.suggestedAction
            )
        } else {
            updatedSummary.databaseStatus = .needsRecovery
            healthError = RepositorySettingsHealthError(
                databaseStatus: .needsRecovery,
                message: error.localizedDescription,
                recovery: "Retry status after the repository is available."
            )
        }
        return updatedSummary
    }

    private func databaseStatus(for mapping: CoreErrorMappingSnapshot) -> RepositorySettingsDatabaseStatus {
        switch mapping.kind {
        case .permissionDenied:
            return .locked
        case .db:
            return mapping.recoverability == .retryable ? .locked : .needsRecovery
        case .config, .repoNotInitialized, .internal:
            return .needsRecovery
        default:
            return mapping.recoverability == .retryable ? .locked : .needsRecovery
        }
    }

    private func shouldSyncRepositoryPath(from config: RepoConfigSnapshot) -> Bool {
        repositoryMetadataDatabaseExists && config.repoPath != repoPath
    }

    private var repositoryMetadataDatabaseExists: Bool {
        let databaseURL = URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix/index.db", isDirectory: false)
        return FileManager.default.fileExists(atPath: databaseURL.path)
    }

    private func loadError(for error: Error) async -> RepositorySettingsLoadError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsLoadError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return RepositorySettingsLoadError(
            message: error.localizedDescription,
            recovery: "Retry status after the repository is available."
        )
    }

    private func syncError(for error: Error) async -> RepositorySettingsSyncError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsSyncError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return RepositorySettingsSyncError(
            message: error.localizedDescription,
            recovery: "Retry status after the repository can be written."
        )
    }
}

private extension RepoConfigSnapshot {
    func withRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }
}
