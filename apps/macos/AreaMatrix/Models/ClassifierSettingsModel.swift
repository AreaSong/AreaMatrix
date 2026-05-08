import Combine
import Foundation

struct ClassifierSettingsLoadError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsSaveError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsPreviewError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsPendingSave: Equatable, Sendable {
    var config: RepoConfigSnapshot
    var error: ClassifierSettingsSaveError
}

struct ClassifierSettingsDraft: Equatable, Sendable {
    var enableExtensionRules: Bool
    var enableKeywordRules: Bool
    var fallbackToInbox: Bool

    init(config: RepoConfigSnapshot) {
        enableExtensionRules = config.enableExtensionRules
        enableKeywordRules = config.enableKeywordRules
        fallbackToInbox = config.fallbackToInbox
    }
}

@MainActor
final class ClassifierSettingsModel: ObservableObject {
    enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case failed(ClassifierSettingsLoadError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var draft: ClassifierSettingsDraft?
    @Published private(set) var savedConfig: RepoConfigSnapshot?
    @Published private(set) var saveError: ClassifierSettingsSaveError?
    @Published private(set) var previewFilename = ""
    @Published private(set) var previewResult: ClassifyResultSnapshot?
    @Published private(set) var previewError: ClassifierSettingsPreviewError?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isSaving = false

    let repoPath: String

    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let predictor: any CoreCategoryPredicting
    private let errorMapper: any CoreErrorMapping
    private var pendingRetry: ClassifierSettingsPendingSave?
    private var previewGeneration = 0

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        predictor: any CoreCategoryPredicting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.predictor = predictor
        self.errorMapper = errorMapper
    }

    var isLoading: Bool {
        loadState == .loading
    }

    var isLoaded: Bool {
        loadState == .loaded
    }

    var hasRetryableSave: Bool {
        pendingRetry != nil && !isSaving
    }

    var classifierConfigPath: String {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
            .path
    }

    func load() async {
        loadState = .loading
        saveError = nil
        pendingRetry = nil
        clearPreviewState()
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            let effectiveConfig = config.withRepositoryPath(repoPath)
            savedConfig = effectiveConfig
            draft = ClassifierSettingsDraft(config: effectiveConfig)
            loadState = .loaded
        } catch {
            savedConfig = nil
            draft = nil
            loadState = .failed(await loadError(for: error))
        }
    }

    func requestEnableExtensionRules(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, let draft, isEnabled != draft.enableExtensionRules else {
            return
        }

        await persist(updating: savedConfig.withEnableExtensionRules(isEnabled))
    }

    func requestEnableKeywordRules(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, let draft, isEnabled != draft.enableKeywordRules else {
            return
        }

        await persist(updating: savedConfig.withEnableKeywordRules(isEnabled))
    }

    func requestFallbackToInbox(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, let draft, isEnabled != draft.fallbackToInbox else {
            return
        }

        await persist(updating: savedConfig.withFallbackToInbox(isEnabled))
    }

    func updatePreviewFilename(_ value: String) {
        guard previewFilename != value else {
            return
        }

        previewFilename = value
        clearPreviewState()
    }

    func previewClassification() async {
        guard isLoaded, !isSaving, !isPreviewing else {
            return
        }

        let filename = previewFilename
        guard !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        previewGeneration += 1
        let currentGeneration = previewGeneration
        isPreviewing = true
        previewResult = nil
        previewError = nil

        do {
            let result = try await predictor.predictCategory(repoPath: repoPath, filename: filename)
            guard previewGeneration == currentGeneration else {
                return
            }
            previewResult = result
        } catch {
            guard previewGeneration == currentGeneration else {
                return
            }
            let mappedError = await previewError(for: error)
            guard previewGeneration == currentGeneration else {
                return
            }
            previewError = mappedError
        }

        if previewGeneration == currentGeneration {
            isPreviewing = false
        }
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else {
            return
        }

        await persist(updating: pendingRetry.config)
    }

    private func persist(updating config: RepoConfigSnapshot) async {
        isSaving = true
        saveError = nil
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: config)
            savedConfig = config
            draft = ClassifierSettingsDraft(config: config)
            pendingRetry = nil
            clearPreviewState()
        } catch {
            if let savedConfig {
                draft = ClassifierSettingsDraft(config: savedConfig)
            }
            let mappedError = await saveError(for: error)
            saveError = mappedError
            pendingRetry = ClassifierSettingsPendingSave(config: config, error: mappedError)
        }
        isSaving = false
    }

    private func loadError(for error: Error) async -> ClassifierSettingsLoadError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return ClassifierSettingsLoadError(
                message: mapping.userMessage,
                recovery: "Retry status"
            )
        }

        return ClassifierSettingsLoadError(
            message: error.localizedDescription,
            recovery: "Retry status after the repository is available."
        )
    }

    private func saveError(for error: Error) async -> ClassifierSettingsSaveError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return ClassifierSettingsSaveError(
                message: mapping.userMessage,
                recovery: "Retry save"
            )
        }

        return ClassifierSettingsSaveError(
            message: error.localizedDescription,
            recovery: "Retry save after the repository is available."
        )
    }

    private func previewError(for error: Error) async -> ClassifierSettingsPreviewError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return ClassifierSettingsPreviewError(
                message: mapping.userMessage,
                recovery: "Retry preview"
            )
        }

        return ClassifierSettingsPreviewError(
            message: error.localizedDescription,
            recovery: "Retry preview after the repository is available."
        )
    }

    private func clearPreviewState() {
        previewGeneration += 1
        previewResult = nil
        previewError = nil
        isPreviewing = false
    }
}

private extension RepoConfigSnapshot {
    func withRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withEnableExtensionRules(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.enableExtensionRules = value
        return config
    }

    func withEnableKeywordRules(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.enableKeywordRules = value
        return config
    }

    func withFallbackToInbox(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.fallbackToInbox = value
        return config
    }
}
