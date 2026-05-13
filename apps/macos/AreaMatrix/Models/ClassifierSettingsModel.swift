import Combine
import Foundation

@MainActor
final class ClassifierSettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(ClassifierSettingsLoadError)
    }

    enum ValidationState: Equatable {
        case idle
        case validating
        case passed
        case failed(ClassifierSettingsValidationError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var draft: ClassifierSettingsDraft?
    @Published private(set) var savedConfig: RepoConfigSnapshot?
    @Published private(set) var saveError: ClassifierSettingsSaveError?
    @Published private(set) var fileActionError: ClassifierSettingsFileActionError?
    @Published private(set) var previewFilename = ""
    @Published private(set) var previewResult: ClassifyResultSnapshot?
    @Published private(set) var previewError: ClassifierSettingsPreviewError?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isSaving = false
    @Published private(set) var validationState: ValidationState = .idle
    @Published private(set) var hasLastValidBackup = false

    let repoPath: String

    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let predictor: any CoreCategoryPredicting
    private let errorMapper: any CoreErrorMapping
    private let classifierRulesManager: any ClassifierRulesManaging
    private let fileOpener: any RepositoryFileOpening
    private let fileRevealer: any RepositoryFileRevealing
    private let finderOpener: any RepositoryFinderOpening
    private let accessibilityAnnouncer: any AccessibilityAnnouncing
    private var pendingRetry: ClassifierSettingsPendingSave?
    private var previewGeneration = 0

    private static let classifierRelativePath = ".areamatrix/classifier.yaml"
    private static let validationProbeFilename = "AreaMatrixValidationProbe.txt"

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        predictor: any CoreCategoryPredicting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        classifierRulesManager: any ClassifierRulesManaging = FileSystemClassifierRulesManager(),
        fileOpener: any RepositoryFileOpening = NSWorkspaceRepositoryFileOpener(),
        fileRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer(),
        finderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.predictor = predictor
        self.errorMapper = errorMapper
        self.classifierRulesManager = classifierRulesManager
        self.fileOpener = fileOpener
        self.fileRevealer = fileRevealer
        self.finderOpener = finderOpener
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }
}

extension ClassifierSettingsModel {
    var isLoading: Bool {
        loadState == .loading
    }

    var isLoaded: Bool {
        loadState == .loaded
    }

    var hasRetryableSave: Bool {
        pendingRetry != nil && !isSaving
    }

    var canRevertToLastValid: Bool {
        hasLastValidBackup && !isSaving && validationState != .validating
    }

    var classifierConfigPath: String {
        classifierConfigURL.path
    }

    var isValidating: Bool {
        validationState == .validating
    }

    var validationError: ClassifierSettingsValidationError? {
        if case let .failed(error) = validationState {
            return error
        }

        return nil
    }

    var validationStatusLabel: String {
        switch validationState {
        case .idle:
            "Not validated"
        case .validating:
            "Validating..."
        case .passed:
            "Validated"
        case .failed:
            "Failed"
        }
    }

    func load() async {
        loadState = .loading
        saveError = nil
        pendingRetry = nil
        clearFileActionState()
        clearValidationState()
        clearPreviewState()
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            let effectiveConfig = config.withClassifierRepositoryPath(repoPath)
            savedConfig = effectiveConfig
            draft = ClassifierSettingsDraft(config: effectiveConfig)
            loadState = .loaded
            refreshLastValidBackupAvailability()
        } catch {
            savedConfig = nil
            draft = nil
            hasLastValidBackup = false
            loadState = await .failed(loadError(for: error))
        }
    }

    func openClassifierYaml() {
        guard isLoaded, !isSaving else {
            return
        }

        clearFileActionState()
        do {
            try fileOpener.openFile(repoPath: repoPath, relativePath: Self.classifierRelativePath)
            accessibilityAnnouncer.announce("classifier.yaml opened.")
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: "无法打开分类规则文件",
                recovery: "Use Reveal in Finder or Create default to restore classifier.yaml."
            )
            accessibilityAnnouncer.announce("无法打开分类规则文件")
        }
    }

    func revealClassifierYamlInFinder() {
        guard isLoaded, !isSaving else {
            return
        }

        clearFileActionState()
        do {
            if classifierFileExists {
                try fileRevealer.revealFile(repoPath: repoPath, relativePath: Self.classifierRelativePath)
            } else {
                try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            }
            accessibilityAnnouncer.announce("classifier.yaml revealed in Finder.")
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: "无法在 Finder 中定位分类规则文件",
                recovery: "Check that the repository folder still exists and Finder has permission."
            )
            accessibilityAnnouncer.announce("无法在 Finder 中定位分类规则文件")
        }
    }

    func createDefaultClassifierYaml() async {
        guard isLoaded, !isSaving, !isValidating else {
            return
        }

        clearFileActionState()
        do {
            try classifierRulesManager.createDefaultClassifier(repoPath: repoPath)
            accessibilityAnnouncer.announce("默认 classifier.yaml 已创建")
            _ = await validateClassifierRules()
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: "无法创建默认分类规则文件",
                recovery: "Check .areamatrix write permission and try again."
            )
            accessibilityAnnouncer.announce("无法创建默认分类规则文件")
        }
    }

    func requestEnableExtensionRules(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, let draft, isEnabled != draft.enableExtensionRules else {
            return
        }

        await persist(updating: savedConfig.withClassifierEnableExtensionRules(isEnabled))
    }

    func requestEnableKeywordRules(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, let draft, isEnabled != draft.enableKeywordRules else {
            return
        }

        await persist(updating: savedConfig.withClassifierEnableKeywordRules(isEnabled))
    }

    func requestFallbackToInbox(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, let draft, isEnabled != draft.fallbackToInbox else {
            return
        }

        await persist(updating: savedConfig.withClassifierFallbackToInbox(isEnabled))
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

    func validateClassifierRules() async -> Bool {
        guard isLoaded, !isSaving, !isValidating else {
            return false
        }

        guard classifierFileExists else {
            validationState = .failed(ClassifierSettingsValidationError(
                message: "分类规则文件不存在",
                recovery: "Use Create default or Reveal in Finder to restore classifier.yaml."
            ))
            accessibilityAnnouncer.announce("分类规则文件不存在")
            return false
        }

        validationState = .validating
        do {
            _ = try await predictor.predictCategory(
                repoPath: repoPath,
                filename: Self.validationProbeFilename
            )
        } catch {
            validationState = await .failed(validationError(for: error))
            accessibilityAnnouncer.announce(validationStateAnnouncement)
            return false
        }

        do {
            try classifierRulesManager.storeLastValidBackup(repoPath: repoPath)
            refreshLastValidBackupAvailability()
            validationState = .passed
            accessibilityAnnouncer.announce("分类规则校验通过")
            return true
        } catch {
            validationState = .failed(ClassifierSettingsValidationError(
                message: "分类规则已通过校验，但无法保存 last valid backup",
                recovery: "Check .areamatrix write permission and run Validate again."
            ))
            accessibilityAnnouncer.announce(validationStateAnnouncement)
            return false
        }
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else {
            return
        }

        await persist(updating: pendingRetry.config)
    }

    func revertToLastValid() async {
        guard canRevertToLastValid else {
            return
        }

        clearFileActionState()
        do {
            try classifierRulesManager.restoreLastValidBackup(repoPath: repoPath)
            accessibilityAnnouncer.announce("已恢复上次有效分类规则")
        } catch {
            validationState = .failed(ClassifierSettingsValidationError(
                message: "无法恢复上次有效分类规则",
                recovery: "Validate a working classifier.yaml before trying Revert again."
            ))
            accessibilityAnnouncer.announce("无法恢复上次有效分类规则")
            return
        }

        _ = await validateClassifierRules()
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

    private var classifierConfigURL: URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
    }

    private var classifierFileExists: Bool {
        classifierRulesManager.classifierFileExists(repoPath: repoPath)
    }

    private func refreshLastValidBackupAvailability() {
        hasLastValidBackup = classifierRulesManager.lastValidBackupExists(repoPath: repoPath)
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

    private func validationError(for error: Error) async -> ClassifierSettingsValidationError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            if case let .Config(reason) = coreError {
                return ClassifierSettingsValidationError(
                    message: ClassifierValidationErrorFormatter.message(
                        coreReason: reason,
                        mappedMessage: mapping.userMessage
                    ),
                    recovery: "Open classifier.yaml and fix the reported line and field."
                )
            }

            return ClassifierSettingsValidationError(
                message: mapping.userMessage,
                recovery: "Open classifier.yaml and fix the reported line."
            )
        }

        return ClassifierSettingsValidationError(
            message: error.localizedDescription,
            recovery: "Open classifier.yaml and try again."
        )
    }

    private var validationStateAnnouncement: String {
        if case let .failed(error) = validationState {
            return error.message
        }

        return "分类规则校验失败"
    }

    private func clearFileActionState() {
        fileActionError = nil
    }

    private func clearValidationState() {
        validationState = .idle
    }

    private func clearPreviewState() {
        previewGeneration += 1
        previewResult = nil
        previewError = nil
        isPreviewing = false
    }
}
