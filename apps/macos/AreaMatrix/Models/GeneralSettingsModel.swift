import Combine
import Foundation

enum GeneralSettingsStorageMode: String, CaseIterable, Equatable, Identifiable {
    case copy
    case move
    case indexOnly

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        switch snapshotValue {
        case "Moved":
            self = .move
        case "Indexed":
            self = .indexOnly
        default:
            self = .copy
        }
    }

    var snapshotValue: String {
        switch self {
        case .copy:
            "Copied"
        case .move:
            "Moved"
        case .indexOnly:
            "Indexed"
        }
    }

    var label: String {
        switch self {
        case .copy:
            "Copy (recommended)"
        case .move:
            "Move"
        case .indexOnly:
            "Index-only"
        }
    }

    var confirmationMessage: String? {
        switch self {
        case .copy:
            nil
        case .move:
            "Imported source files will disappear from their original location after import."
        case .indexOnly:
            "Moving source files later can make indexed entries missing."
        }
    }
}

enum GeneralSettingsOverviewOutput: String, CaseIterable, Equatable, Identifiable {
    case generatedOnly
    case rootAreaMatrixFile

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        self = snapshotValue == "RootAreaMatrixFile" ? .rootAreaMatrixFile : .generatedOnly
    }

    var snapshotValue: String {
        switch self {
        case .generatedOnly:
            "GeneratedOnly"
        case .rootAreaMatrixFile:
            "RootAreaMatrixFile"
        }
    }
}

enum GeneralSettingsLocale: String, CaseIterable, Equatable, Identifiable {
    case system
    case zhCN
    case en

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        switch snapshotValue.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "en":
            self = .en
        case "zh-CN":
            self = .zhCN
        case "system":
            self = .system
        case "zh-Hans":
            // Core's older default was zh-Hans; S1-26 now treats the default as following the system.
            self = .system
        default:
            self = .system
        }
    }

    var snapshotValue: String {
        switch self {
        case .system:
            "system"
        case .zhCN:
            "zh-CN"
        case .en:
            "en"
        }
    }

    var label: String {
        switch self {
        case .system:
            "system"
        case .zhCN:
            "zh-CN"
        case .en:
            "en"
        }
    }
}

enum GeneralSettingsAppearance: String, CaseIterable, Equatable, Identifiable {
    case system

    var id: String {
        rawValue
    }

    var label: String {
        "system"
    }
}

enum RootOverviewFileStatus: Equatable {
    case missing
    case managedBlock
    case userContent
    case unsafe(String)

    var confirmationDetail: String {
        switch self {
        case .missing:
            "A new AREAMATRIX.md will be created at the repository root."
        case .managedBlock:
            "Only the AreaMatrix managed block will be updated."
        case .userContent:
            [
                "AreaMatrix will append a clearly marked managed block to AREAMATRIX.md.",
                "Existing content will remain unchanged."
            ].joined(separator: " ")
        case let .unsafe(reason):
            reason.isEmpty ? "Cannot safely update AREAMATRIX.md" : reason
        }
    }

    var canEnableRootOverview: Bool {
        if case .unsafe = self { return false }
        return true
    }

    var requiresFinderRecovery: Bool {
        if case .unsafe = self { return true }
        return false
    }
}

struct GeneralSettingsSaveError: Equatable {
    var message: String
    var recovery: String
}

enum GeneralSettingsIgnoreRulesAlert: Equatable {
    case createDefault
}

struct GeneralSettingsPendingSave: Equatable {
    var config: RepoConfigSnapshot
    var error: GeneralSettingsSaveError
}

struct GeneralSettingsDraft: Equatable {
    var defaultStorageMode: GeneralSettingsStorageMode
    var overviewOutput: GeneralSettingsOverviewOutput
    var locale: GeneralSettingsLocale
    var appearance: GeneralSettingsAppearance

    init(config: RepoConfigSnapshot) {
        defaultStorageMode = GeneralSettingsStorageMode(snapshotValue: config.defaultMode)
        overviewOutput = GeneralSettingsOverviewOutput(snapshotValue: config.overviewOutput)
        locale = GeneralSettingsLocale(snapshotValue: config.locale)
        appearance = .system
    }
}

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
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        rootOverviewInspector: any RootOverviewFileInspecting = LocalRootOverviewFileInspector(),
        rootOverviewRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer(),
        ignoreRulesManager: any RepositoryIgnoreRulesManaging = NSWorkspaceRepositoryIgnoreRulesManager(),
        errorMapper: any CoreErrorMapping = CoreBridge()
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
                message: "AREAMATRIX.md cannot be shown in Finder.",
                recovery: "Open the repository folder and check file permissions before enabling root overview."
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
                message: "ignore.yaml cannot be opened.",
                recovery: "Check .areamatrix/ignore.yaml permissions and retry from General settings."
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
                message: "Default ignore.yaml cannot be created.",
                recovery: "AreaMatrix only writes .areamatrix/ignore.yaml; check metadata folder permissions and retry."
            )
        }
    }

    func updateLocale(_ locale: GeneralSettingsLocale) async {
        guard !isSaving, let savedConfig, locale != draft?.locale else { return }
        await persist(updating: savedConfig.withLocale(locale.snapshotValue))
    }

    func resetThisTab() async {
        guard !isSaving, let savedConfig else { return }
        let defaults = savedConfig
            .withDefaultMode(GeneralSettingsStorageMode.copy.snapshotValue)
            .withOverviewOutput(GeneralSettingsOverviewOutput.generatedOnly.snapshotValue)
            .withLocale(GeneralSettingsLocale.system.snapshotValue)
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
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return GeneralSettingsSaveError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return GeneralSettingsSaveError(
            message: error.localizedDescription,
            recovery: "Retry saving settings after the repository is available."
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
