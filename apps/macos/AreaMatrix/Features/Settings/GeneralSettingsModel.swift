import Combine
import Foundation

@MainActor
final class GeneralSettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(GeneralSettingsSaveError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var draft: GeneralSettingsDraft?
    @Published private(set) var savedConfig: RepoConfigSnapshot?
    @Published private(set) var pendingStorageConfirmation: GeneralSettingsStorageMode?
    @Published private(set) var pendingRootOverviewStatus: RootOverviewFileStatus?
    @Published private(set) var pendingIgnoreRulesAlert: GeneralSettingsIgnoreRulesAlert?
    @Published private(set) var saveError: GeneralSettingsSaveError?
    @Published private(set) var isSaving = false

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let rootOverviewInspector: any RootOverviewFileInspecting
    private let rootOverviewRevealer: any RepositoryFileRevealing
    private let ignoreRulesManager: any RepositoryIgnoreRulesManaging
    private let errorMapper: any CoreErrorMapping
    private var pendingRetry: GeneralSettingsPendingSave?

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        rootOverviewInspector: any RootOverviewFileInspecting =
            GeneralSettingsPlatformServices.rootOverviewInspector,
        rootOverviewRevealer: any RepositoryFileRevealing =
            GeneralSettingsPlatformServices.rootOverviewRevealer,
        ignoreRulesManager: any RepositoryIgnoreRulesManaging =
            GeneralSettingsPlatformServices.ignoreRulesManager,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.rootOverviewInspector = rootOverviewInspector
        self.rootOverviewRevealer = rootOverviewRevealer
        self.ignoreRulesManager = ignoreRulesManager
        self.errorMapper = errorMapper
    }

    var hasRetryableSave: Bool {
        pendingRetry != nil && !isSaving
    }

    var isLoaded: Bool {
        loadState == .loaded
    }

    func load() async {
        loadState = .loading
        saveError = nil
        pendingRetry = nil
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            savedConfig = config
            draft = GeneralSettingsDraft(config: config)
            loadState = .loaded
        } catch {
            loadState = await .failed(saveError(for: error))
        }
    }

    func requestStorageMode(_ mode: GeneralSettingsStorageMode) async {
        guard !isSaving, let savedConfig else { return }
        if mode == draft?.defaultStorageMode { return }

        if mode.confirmationMessage != nil {
            pendingStorageConfirmation = mode
            return
        }

        await persist(updating: savedConfig.withDefaultMode(mode.snapshotValue))
    }

    func confirmPendingStorageMode() async {
        guard let mode = pendingStorageConfirmation, let savedConfig else { return }
        pendingStorageConfirmation = nil
        await persist(updating: savedConfig.withDefaultMode(mode.snapshotValue))
    }

    func cancelPendingStorageMode() {
        pendingStorageConfirmation = nil
        if let savedConfig {
            draft = GeneralSettingsDraft(config: savedConfig)
        }
    }

    func requestOverviewOutput(_ output: GeneralSettingsOverviewOutput) async {
        guard !isSaving, let savedConfig else { return }
        if output == draft?.overviewOutput { return }

        if output == .rootAreaMatrixFile {
            pendingRootOverviewStatus = rootOverviewInspector.status(repoPath: repoPath)
            return
        }

        await persist(updating: savedConfig.withOverviewOutput(output.snapshotValue))
    }

    func confirmRootOverview() async {
        guard pendingRootOverviewStatus?.canEnableRootOverview == true, let savedConfig else { return }
        pendingRootOverviewStatus = nil
        await persist(updating: savedConfig
            .withOverviewOutput(GeneralSettingsOverviewOutput.rootAreaMatrixFile.snapshotValue))
    }

    func cancelRootOverview() {
        pendingRootOverviewStatus = nil
        if let savedConfig {
            draft = GeneralSettingsDraft(config: savedConfig)
        }
    }

    func revealRootOverviewInFinder() {
        do {
            try rootOverviewRevealer.revealFile(repoPath: repoPath, relativePath: "AREAMATRIX.md")
            saveError = nil
        } catch {
            saveError = GeneralSettingsSaveError(
                message: L10n.string("AREAMATRIX.md cannot be shown in Finder."),
                recovery: L10n
                    .string("Open the repository folder and check file permissions before enabling root overview.")
            )
        }
    }

    func openIgnoreRules() {
        do {
            try ignoreRulesManager.openIgnoreRules(repoPath: repoPath)
            saveError = nil
        } catch RepositoryIgnoreRulesError.ignoreRulesMissing {
            pendingIgnoreRulesAlert = .createDefault
            saveError = nil
        } catch {
            saveError = GeneralSettingsSaveError(
                message: L10n.string("ignore.yaml cannot be opened."),
                recovery: L10n.string("Check .areamatrix/ignore.yaml permissions and retry from General settings.")
            )
        }
    }

    func cancelCreateDefaultIgnoreRules() {
        pendingIgnoreRulesAlert = nil
    }

    func createDefaultIgnoreRulesAndOpen() {
        pendingIgnoreRulesAlert = nil
        do {
            try ignoreRulesManager.createDefaultIgnoreRules(repoPath: repoPath)
            try ignoreRulesManager.openIgnoreRules(repoPath: repoPath)
            saveError = nil
        } catch {
            saveError = GeneralSettingsSaveError(
                message: L10n.string("Default ignore.yaml cannot be created."),
                recovery: L10n
                    .string(
                        "AreaMatrix only writes .areamatrix/ignore.yaml; check metadata folder permissions and retry."
                    )
            )
        }
    }

    func updateContentLanguage(_ language: RepositoryContentLanguage) async {
        guard !isSaving, let savedConfig, language != draft?.contentLanguage else { return }
        await persist(updating: savedConfig.withLocale(language.snapshotValue))
    }

    func resetThisTab() async {
        guard !isSaving, let savedConfig else { return }
        let defaults = savedConfig
            .withDefaultMode(GeneralSettingsStorageMode.copy.snapshotValue)
            .withOverviewOutput(GeneralSettingsOverviewOutput.generatedOnly.snapshotValue)
            .withLocale(RepositoryContentLanguage.followInterface.snapshotValue)
        await persist(updating: defaults)
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else { return }
        await persist(updating: pendingRetry.config)
    }

    private func persist(updating config: RepoConfigSnapshot) async {
        isSaving = true
        saveError = nil
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: config)
            savedConfig = config
            draft = GeneralSettingsDraft(config: config)
            pendingRetry = nil
        } catch {
            if let savedConfig {
                draft = GeneralSettingsDraft(config: savedConfig)
            }
            let mappedError = await saveError(for: error)
            saveError = mappedError
            pendingRetry = GeneralSettingsPendingSave(config: config, error: mappedError)
        }
        isSaving = false
    }

    private func saveError(for error: Error) async -> GeneralSettingsSaveError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return GeneralSettingsSaveError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return GeneralSettingsSaveError(
            message: error.localizedDescription,
            recovery: L10n.string("Retry saving settings after the repository is available.")
        )
    }
}

extension RepoConfigSnapshot {
    func withDefaultMode(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.defaultMode = value
        return config
    }

    func withOverviewOutput(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.overviewOutput = value
        return config
    }

    func withLocale(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.locale = value
        return config
    }
}
