import Combine
import Foundation

@MainActor
final class RepositorySettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded(RepositorySettingsSummary)
        case failed(RepositorySettingsLoadError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var loadedConfig: RepoConfigSnapshot?
    @Published private(set) var healthSummary: RepositorySettingsHealthSummary?
    @Published private(set) var healthError: RepositorySettingsHealthError?
    @Published private(set) var syncError: RepositorySettingsSyncError?
    @Published private(set) var repositoryActionMessage: String?
    @Published private(set) var repositoryActionError: RepositorySettingsPathActionError?
    @Published private(set) var overviewActionError: RepositorySettingsOverviewActionError?
    @Published private(set) var diagnosticsState: RepositorySettingsDiagnosticsState = .idle

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let repositoryOpener: any CoreEmptyRepositoryOpening
    private let fileLister: (any CoreFileListing)?
    private let scanSessionReader: any CoreScanSessionReading
    private let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    private let finderOpener: any RepositoryFinderOpening
    private let pathCopier: any RepositoryPathCopying
    private let generatedOverviewRevealer: any RepositoryFileRevealing
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let coreVersionLoader: any CoreVersionLoading
    private let errorMapper: any CoreErrorMapping
    private let accessibilityAnnouncer: any AccessibilityAnnouncing

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        repositoryOpener: any CoreEmptyRepositoryOpening = CoreBridge(),
        fileLister: (any CoreFileListing)? = nil,
        scanSessionReader: any CoreScanSessionReading = CoreBridge(),
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            SQLiteExistingRepositoryMetadataReader(),
        finderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        pathCopier: any RepositoryPathCopying = NSPasteboardRepositoryPathCopier(),
        generatedOverviewRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        coreVersionLoader: any CoreVersionLoading = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.repositoryOpener = repositoryOpener
        self.fileLister = fileLister ?? (repositoryOpener as? any CoreFileListing)
        self.scanSessionReader = scanSessionReader
        self.existingRepositoryMetadataReader = existingRepositoryMetadataReader
        self.finderOpener = finderOpener
        self.pathCopier = pathCopier
        self.generatedOverviewRevealer = generatedOverviewRevealer
        self.diagnosticsCollector = diagnosticsCollector
        self.coreVersionLoader = coreVersionLoader
        self.errorMapper = errorMapper
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }
}

extension RepositorySettingsModel {
    var hasConnectedRepository: Bool {
        !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isLoading: Bool {
        loadState == .loading
    }

    var summary: RepositorySettingsSummary? {
        guard case let .loaded(summary) = loadState else { return nil }
        return summary
    }

    var loadError: RepositorySettingsLoadError? {
        guard case let .failed(error) = loadState else { return nil }
        return error
    }

    func load() async {
        guard hasConnectedRepository else {
            loadedConfig = nil
            loadState = .failed(RepositorySettingsLoadError(
                message: "No repository connected.",
                recovery: "Connect Repository"
            ))
            return
        }

        loadState = .loading
        healthSummary = nil
        healthError = nil
        syncError = nil
        repositoryActionMessage = nil
        repositoryActionError = nil
        overviewActionError = nil
        diagnosticsState = .idle
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            let effectiveConfig = config.withRepositoryPath(repoPath)
            let coreVersion = await currentCoreVersion()
            loadedConfig = effectiveConfig

            if shouldSyncRepositoryPath(from: config) {
                do {
                    try await updater.updateConfig(repoPath: repoPath, newConfig: effectiveConfig)
                } catch {
                    syncError = await syncError(for: error)
                }
            }

            loadState = .loaded(RepositorySettingsSummary(
                config: effectiveConfig,
                fallbackRepoPath: repoPath,
                coreVersion: coreVersion
            ))
            await refreshHealth()
        } catch {
            loadedConfig = nil
            loadState = await .failed(loadError(for: error))
        }
    }

    func revealRepositoryInFinder() {
        clearRepositoryActionFeedback()
        do {
            try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            repositoryActionMessage = "Repository folder revealed in Finder."
        } catch {
            repositoryActionError = RepositorySettingsPathActionError(
                message: "Repository folder cannot be revealed.",
                recovery: "Check that the repository folder still exists and Finder has permission to open it."
            )
        }
    }

    func copyRepositoryPath() {
        clearRepositoryActionFeedback()
        do {
            try pathCopier.copyPath(repoPath: repoPath, relativePath: "")
            repositoryActionMessage = "Repository path copied."
            accessibilityAnnouncer.announce("Repository path copied.")
        } catch {
            repositoryActionError = RepositorySettingsPathActionError(
                message: "Repository path cannot be copied.",
                recovery: "Copy the Location row manually after checking clipboard permissions."
            )
            accessibilityAnnouncer.announce("Repository path cannot be copied.")
        }
    }

    func requestDiagnosticsExport() {
        clearRepositoryActionFeedback()
        diagnosticsState = .confirmingPrivacy
    }

    func cancelDiagnosticsExport() {
        if diagnosticsState.isConfirmingPrivacy {
            diagnosticsState = .idle
        }
    }

    func collectDiagnostics() async {
        guard diagnosticsState.isConfirmingPrivacy else { return }

        diagnosticsState = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            diagnosticsState = .collected(snapshot)
        } catch {
            diagnosticsState = await .failed(diagnosticsError(for: error))
        }
    }

    func revealGeneratedOverviewInFinder() {
        clearRepositoryActionFeedback()
        do {
            try generatedOverviewRevealer.revealFile(
                repoPath: repoPath,
                relativePath: RepositorySettingsSummary.generatedOverviewRelativePath
            )
            overviewActionError = nil
            repositoryActionMessage = "Generated overview revealed in Finder."
        } catch {
            overviewActionError = overviewError(for: error)
        }
    }

    private func refreshHealth() async {
        var summary = RepositorySettingsHealthSummary(
            databaseStatus: .ok,
            schemaVersion: nil,
            filesIndexed: nil,
            lastOpenedAt: nil,
            lastScanAt: nil,
            watcherStatus: .paused
        )

        do {
            let metadata = try await existingRepositoryMetadataReader.metadata(repoPath: repoPath)
            summary.schemaVersion = metadata.schemaVersion
            summary.lastOpenedAt = metadata.lastOpenedAt
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
        let pageSize: Int64 = 1000
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
            .locked
        case .db:
            mapping.recoverability == .retryable ? .locked : .needsRecovery
        case .config, .repoNotInitialized, .internal:
            .needsRecovery
        default:
            mapping.recoverability == .retryable ? .locked : .needsRecovery
        }
    }

    private func shouldSyncRepositoryPath(from config: RepoConfigSnapshot) -> Bool {
        repositoryMetadataDatabaseExists && config.repoPath != repoPath
    }

    private func currentCoreVersion() async -> String {
        do {
            return try await coreVersionLoader.coreVersion()
        } catch {
            return "Unknown"
        }
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

    private func overviewError(for error: Error) -> RepositorySettingsOverviewActionError {
        if let actionError = error as? RepositoryFileActionError {
            return overviewError(for: actionError)
        }

        return RepositorySettingsOverviewActionError(
            message: "Generated overview cannot be shown in Finder.",
            recovery: "Open the repository folder and check .areamatrix/generated/ permissions before retrying."
        )
    }

    private func overviewError(for error: RepositoryFileActionError) -> RepositorySettingsOverviewActionError {
        switch error {
        case .fileMissing:
            RepositorySettingsOverviewActionError(
                message: "Generated overview cannot be shown in Finder.",
                recovery: "Retry after AreaMatrix regenerates .areamatrix/generated/root.md."
            )
        case .unsafeRelativePath:
            RepositorySettingsOverviewActionError(
                message: "Generated overview path is not safe to open.",
                recovery: "Reload repository settings before retrying."
            )
        case .openRejected:
            RepositorySettingsOverviewActionError(
                message: "Finder rejected the generated overview request.",
                recovery: "Open the repository folder and check .areamatrix/generated/ permissions before retrying."
            )
        }
    }

    private func clearRepositoryActionFeedback() {
        repositoryActionMessage = nil
        repositoryActionError = nil
        overviewActionError = nil
    }

    private func diagnosticsError(for error: Error) async -> RepositorySettingsDiagnosticsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsDiagnosticsError(
                message: mapping.userMessage,
                recovery: mapping.suggestedAction
            )
        }

        return RepositorySettingsDiagnosticsError(
            message: "Diagnostics could not be exported.",
            recovery: "Retry after the repository is available."
        )
    }
}
