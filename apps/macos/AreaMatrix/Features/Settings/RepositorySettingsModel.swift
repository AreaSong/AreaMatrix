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
    @Published private(set) var loadedConfig: AppRepoConfigSnapshot?
    @Published var healthSummary: RepositorySettingsHealthSummary?
    @Published var healthError: RepositorySettingsHealthError?
    @Published private(set) var syncError: RepositorySettingsSyncError?
    @Published private(set) var repositoryActionMessage: LocalizedMessage?
    @Published private(set) var repositoryActionError: RepositorySettingsPathActionError?
    @Published private(set) var overviewActionError: RepositorySettingsOverviewActionError?
    @Published private(set) var diagnosticsState: RepositorySettingsDiagnosticsState = .idle

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    let repositoryOpener: any CoreEmptyRepositoryOpening
    let fileLister: (any CoreFileListing)?
    let scanSessionReader: any CoreScanSessionReading
    let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    private let metadataPresenceChecker: any RepoMetadataPresenceChecking
    private let finderOpener: any RepositoryFinderOpening
    private let pathCopier: any RepositoryPathCopying
    private let generatedOverviewRevealer: any RepositoryFileRevealing
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let coreVersionLoader: any CoreVersionLoading
    let errorMapper: any CoreErrorMapping
    private let accessibilityAnnouncer: any AccessibilityAnnouncing
    private var hasPendingRepositoryPathSync = false
    private var diagnosticsGeneration = SettingsDiagnosticsGeneration()

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        repositoryOpener: any CoreEmptyRepositoryOpening = AppCoreServices.emptyRepositoryOpener,
        fileLister: (any CoreFileListing)? = nil,
        scanSessionReader: any CoreScanSessionReading = AppCoreServices.scanSessionReader,
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            RepositorySettingsPlatformServices.metadataReader,
        metadataPresenceChecker: any RepoMetadataPresenceChecking =
            RepositorySettingsPlatformServices.metadataPresenceChecker,
        finderOpener: any RepositoryFinderOpening = RepositorySettingsPlatformServices.finderOpener,
        pathCopier: any RepositoryPathCopying = RepositorySettingsPlatformServices.pathCopier,
        generatedOverviewRevealer: any RepositoryFileRevealing =
            RepositorySettingsPlatformServices.generatedOverviewRevealer,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector,
        coreVersionLoader: any CoreVersionLoading = AppCoreServices.coreVersionLoader,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = RepositorySettingsPlatformServices.accessibilityAnnouncer
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.repositoryOpener = repositoryOpener
        self.fileLister = fileLister ?? (repositoryOpener as? any CoreFileListing)
        self.scanSessionReader = scanSessionReader
        self.existingRepositoryMetadataReader = existingRepositoryMetadataReader
        self.metadataPresenceChecker = metadataPresenceChecker
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
                message: L10n.message("No repository connected."),
                recovery: L10n.message("Connect Repository")
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
        diagnosticsGeneration.invalidate()
        diagnosticsState = .idle
        hasPendingRepositoryPathSync = false
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            let effectiveConfig = config.withRepositoryPath(repoPath)
            let metadataPresence = metadataPresenceChecker.metadataPresence(repoPath: repoPath)
            let coreVersion = await currentCoreVersion()
            loadedConfig = effectiveConfig

            if metadataPresence.hasMetadataDatabase, config.repoPath != repoPath {
                await synchronizeRepositoryPath(from: config)
            }

            loadState = .loaded(RepositorySettingsSummary(
                config: loadedConfig ?? effectiveConfig,
                fallbackRepoPath: repoPath,
                coreVersion: coreVersion,
                metadataPresence: metadataPresence
            ))
            await refreshHealth()
        } catch {
            loadedConfig = nil
            loadState = await .failed(loadError(for: error))
        }
    }

    func retryRepositoryPathSync() async {
        guard hasPendingRepositoryPathSync else { return }

        syncError = nil
        do {
            let currentConfig = try await loader.loadConfig(repoPath: repoPath)
            await synchronizeRepositoryPath(from: currentConfig)
        } catch {
            syncError = await repositoryPathSyncError(for: error)
        }
    }

    func revealRepositoryInFinder() {
        clearRepositoryActionFeedback()
        do {
            try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            repositoryActionMessage = L10n.message("Repository folder revealed in Finder.")
        } catch {
            repositoryActionError = RepositorySettingsPathActionError(
                message: L10n.message("Repository folder cannot be revealed."),
                recovery: L10n
                    .message("Check that the repository folder still exists and Finder has permission to open it.")
            )
        }
    }

    func copyRepositoryPath() {
        clearRepositoryActionFeedback()
        do {
            try pathCopier.copyPath(repoPath: repoPath, relativePath: "")
            repositoryActionMessage = L10n.message("Repository path copied.")
            accessibilityAnnouncer.announce(L10n.message("Repository path copied."))
        } catch {
            repositoryActionError = RepositorySettingsPathActionError(
                message: L10n.message("Repository path cannot be copied."),
                recovery: L10n.message("Copy the Location row manually after checking clipboard permissions.")
            )
            accessibilityAnnouncer.announce(L10n.message("Repository path cannot be copied."))
        }
    }

    func requestDiagnosticsExport() {
        clearRepositoryActionFeedback()
        guard !diagnosticsState.isCollecting else { return }
        diagnosticsState = .confirmingPrivacy
    }

    func cancelDiagnosticsExport() {
        if diagnosticsState.isConfirmingPrivacy || diagnosticsState.isCollecting {
            diagnosticsGeneration.invalidate()
            diagnosticsState = .idle
        }
    }

    func collectDiagnostics() async {
        guard diagnosticsState.isConfirmingPrivacy else { return }

        let generation = diagnosticsGeneration.begin()
        diagnosticsState = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard diagnosticsGeneration.isCurrent(generation) else { return }
            diagnosticsState = .collected(snapshot)
        } catch {
            guard diagnosticsGeneration.isCurrent(generation) else { return }
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
            repositoryActionMessage = L10n.message("Generated overview revealed in Finder.")
        } catch {
            overviewActionError = overviewError(for: error)
        }
    }

    private func currentCoreVersion() async -> String? {
        do {
            return try await coreVersionLoader.coreVersion()
        } catch {
            return nil
        }
    }

    private func synchronizeRepositoryPath(from currentConfig: AppRepoConfigSnapshot) async {
        let updatedConfig = currentConfig.withRepositoryPath(repoPath)
        guard currentConfig.repoPath != repoPath else {
            loadedConfig = updatedConfig
            hasPendingRepositoryPathSync = false
            return
        }

        hasPendingRepositoryPathSync = true
        do {
            loadedConfig = try await updater.updateConfig(
                repoPath: repoPath,
                from: currentConfig,
                to: updatedConfig
            )
            hasPendingRepositoryPathSync = false
        } catch {
            syncError = await repositoryPathSyncError(for: error)
        }
    }

    private func repositoryPathSyncError(for error: Error) async -> RepositorySettingsSyncError {
        if let mapping = await errorMapper.mapKnownErrorIfPresent(error) {
            return RepositorySettingsSyncError(
                message: mapping.userMessageDescriptor,
                recovery: mapping.suggestedActionDescriptor
            )
        }
        return RepositorySettingsSyncError(
            message: L10n.message("settings.error.syncRepositoryPath", technicalDetail: error.localizedDescription),
            recovery: L10n.message("settings.error.syncRepositoryPathRecovery")
        )
    }

    private func loadError(for error: Error) async -> RepositorySettingsLoadError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return RepositorySettingsLoadError(
                message: mapping.userMessageDescriptor,
                recovery: mapping.suggestedActionDescriptor
            )
        }

        return RepositorySettingsLoadError(
            message: L10n.message("settings.error.loadRepository", technicalDetail: error.localizedDescription),
            recovery: L10n.message("Retry status after the repository is available.")
        )
    }

    private func overviewError(for error: Error) -> RepositorySettingsOverviewActionError {
        if let actionError = error as? RepositoryFileActionError {
            return overviewError(for: actionError)
        }

        return RepositorySettingsOverviewActionError(
            message: L10n.message("Generated overview cannot be shown in Finder."),
            recovery: L10n
                .message("Open the repository folder and check .areamatrix/generated/ permissions before retrying.")
        )
    }

    private func overviewError(for error: RepositoryFileActionError) -> RepositorySettingsOverviewActionError {
        switch error {
        case .fileMissing:
            RepositorySettingsOverviewActionError(
                message: L10n.message("Generated overview cannot be shown in Finder."),
                recovery: L10n.message("Retry after AreaMatrix regenerates .areamatrix/generated/root.md.")
            )
        case .unsafeRelativePath:
            RepositorySettingsOverviewActionError(
                message: L10n.message("Generated overview path is not safe to open."),
                recovery: L10n.message("Reload repository settings before retrying.")
            )
        case .openRejected:
            RepositorySettingsOverviewActionError(
                message: L10n.message("Finder rejected the generated overview request."),
                recovery: L10n
                    .message("Open the repository folder and check .areamatrix/generated/ permissions before retrying.")
            )
        }
    }

    private func clearRepositoryActionFeedback() {
        repositoryActionMessage = nil
        repositoryActionError = nil
        overviewActionError = nil
    }

    private func diagnosticsError(for error: Error) async -> RepositorySettingsDiagnosticsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return RepositorySettingsDiagnosticsError(
                message: mapping.userMessageDescriptor,
                recovery: mapping.suggestedActionDescriptor
            )
        }

        return RepositorySettingsDiagnosticsError(
            message: L10n.message("Diagnostics could not be exported."),
            recovery: L10n.message("Retry after the repository is available.")
        )
    }
}
