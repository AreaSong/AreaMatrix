import Combine
import Foundation

enum AdvancedSettingsOverviewOutput: String, CaseIterable, Equatable, Identifiable, Sendable {
    case generatedOnly
    case rootAreaMatrixFile

    var id: String { rawValue }

    init(snapshotValue: String) {
        self = snapshotValue == "RootAreaMatrixFile" ? .rootAreaMatrixFile : .generatedOnly
    }

    var snapshotValue: String {
        switch self {
        case .generatedOnly:
            return "GeneratedOnly"
        case .rootAreaMatrixFile:
            return "RootAreaMatrixFile"
        }
    }

    var label: String {
        switch self {
        case .generatedOnly:
            return "Generated only"
        case .rootAreaMatrixFile:
            return "Root AREAMATRIX.md"
        }
    }
}

enum AdvancedSettingsSaveKind: Equatable, Sendable {
    case overview
    case replace

    var message: String {
        switch self {
        case .overview:
            return "Could not save overview setting"
        case .replace:
            return "Could not save advanced setting"
        }
    }
}

struct AdvancedSettingsError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct AdvancedSettingsDraft: Equatable, Sendable {
    var overviewOutput: AdvancedSettingsOverviewOutput
    var allowReplaceDuringImport: Bool

    init(config: RepoConfigSnapshot) {
        overviewOutput = AdvancedSettingsOverviewOutput(snapshotValue: config.overviewOutput)
        allowReplaceDuringImport = config.allowReplaceDuringImport
    }
}

private struct AdvancedSettingsPendingSave: Equatable, Sendable {
    var config: RepoConfigSnapshot
    var kind: AdvancedSettingsSaveKind
}

@MainActor
final class AdvancedSettingsModel: ObservableObject {
    enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case failed(AdvancedSettingsError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var draft: AdvancedSettingsDraft?
    @Published private(set) var savedConfig: RepoConfigSnapshot?
    @Published private(set) var saveError: AdvancedSettingsError?
    @Published private(set) var pendingRootOverviewStatus: RootOverviewFileStatus?
    @Published private(set) var isReplaceConfirmationPending = false
    @Published private(set) var isSaving = false

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let rootOverviewInspector: any RootOverviewFileInspecting
    private let errorMapper: any CoreErrorMapping
    private var pendingRetry: AdvancedSettingsPendingSave?

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        rootOverviewInspector: any RootOverviewFileInspecting = LocalRootOverviewFileInspector(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.rootOverviewInspector = rootOverviewInspector
        self.errorMapper = errorMapper
    }

    var isLoaded: Bool { loadState == .loaded }
    var hasRetryableSave: Bool { pendingRetry != nil && !isSaving }
    var writesDisabled: Bool {
        isSaving || !isLoaded || pendingRootOverviewStatus != nil || isReplaceConfirmationPending
    }

    func load() async {
        loadState = .loading
        saveError = nil
        pendingRetry = nil
        pendingRootOverviewStatus = nil
        isReplaceConfirmationPending = false

        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
                .withAdvancedRepositoryPath(repoPath)
            savedConfig = config
            draft = AdvancedSettingsDraft(config: config)
            loadState = .loaded
        } catch {
            savedConfig = nil
            draft = nil
            loadState = .failed(await mappedError(for: error, fallbackMessage: "Unable to load advanced settings"))
        }
    }

    func requestOverviewOutput(_ output: AdvancedSettingsOverviewOutput) async {
        guard !isSaving, let savedConfig, output != draft?.overviewOutput else {
            return
        }

        if output == .rootAreaMatrixFile {
            pendingRootOverviewStatus = rootOverviewInspector.status(repoPath: repoPath)
            return
        }

        await persist(
            updating: savedConfig.withAdvancedOverviewOutput(output.snapshotValue),
            kind: .overview
        )
    }

    func confirmRootOverview() async {
        guard pendingRootOverviewStatus?.canEnableRootOverview == true, let savedConfig else {
            return
        }

        pendingRootOverviewStatus = nil
        await persist(
            updating: savedConfig.withAdvancedOverviewOutput(
                AdvancedSettingsOverviewOutput.rootAreaMatrixFile.snapshotValue
            ),
            kind: .overview
        )
    }

    func cancelRootOverview() {
        pendingRootOverviewStatus = nil
        restoreDraftFromSavedConfig()
    }

    func requestAllowReplaceDuringImport(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, isEnabled != draft?.allowReplaceDuringImport else {
            return
        }

        if isEnabled {
            isReplaceConfirmationPending = true
            return
        }

        await persist(updating: savedConfig.withAdvancedAllowReplaceDuringImport(false), kind: .replace)
    }

    func confirmAllowReplaceDuringImport() async {
        guard let savedConfig else {
            return
        }

        isReplaceConfirmationPending = false
        await persist(updating: savedConfig.withAdvancedAllowReplaceDuringImport(true), kind: .replace)
    }

    func cancelAllowReplaceDuringImport() {
        isReplaceConfirmationPending = false
        restoreDraftFromSavedConfig()
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else {
            return
        }

        await persist(updating: pendingRetry.config, kind: pendingRetry.kind)
    }

    private func persist(updating config: RepoConfigSnapshot, kind: AdvancedSettingsSaveKind) async {
        isSaving = true
        saveError = nil
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: config)
            savedConfig = config
            draft = AdvancedSettingsDraft(config: config)
            pendingRetry = nil
        } catch {
            restoreDraftFromSavedConfig()
            saveError = await mappedError(for: error, fallbackMessage: kind.message)
            pendingRetry = AdvancedSettingsPendingSave(config: config, kind: kind)
        }
        isSaving = false
    }

    private func restoreDraftFromSavedConfig() {
        if let savedConfig {
            draft = AdvancedSettingsDraft(config: savedConfig)
        }
    }

    private func mappedError(for error: Error, fallbackMessage: String) async -> AdvancedSettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AdvancedSettingsError(
                message: fallbackMessage,
                recovery: mapping.suggestedAction.isEmpty ? mapping.userMessage : mapping.suggestedAction
            )
        }

        return AdvancedSettingsError(message: fallbackMessage, recovery: error.localizedDescription)
    }
}

extension RepoConfigSnapshot {
    func withAdvancedRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withAdvancedOverviewOutput(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.overviewOutput = value
        return config
    }

    func withAdvancedAllowReplaceDuringImport(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.allowReplaceDuringImport = value
        return config
    }
}
