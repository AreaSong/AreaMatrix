import Combine
import Foundation

@MainActor
final class ClassifierSettingsModel: ObservableObject {
    @Published private(set) var loadState: ClassifierSettingsLoadState = .loading
    @Published private(set) var draft: ClassifierSettingsDraft?
    @Published private(set) var savedConfig: RepoConfigSnapshot?
    @Published private(set) var saveError: ClassifierSettingsSaveError?
    @Published private(set) var fileActionError: ClassifierSettingsFileActionError?
    @Published var previewState = ClassifierSettingsPreviewState()
    @Published private(set) var isSaving = false
    @Published private(set) var validationState: ClassifierSettingsValidationState = .idle
    @Published private(set) var hasLastValidBackup = false
    @Published var classifierRuleEditor = ClassifierRuleEditorModelState()

    let repoPath: String
    let ruleEditor: any CoreClassifierRuleEditing

    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    let predictor: any CoreCategoryPredicting
    let errorMapper: any CoreErrorMapping
    private let classifierRulesManager: any ClassifierRulesManaging
    private let fileOpener: any RepositoryFileOpening
    private let fileRevealer: any RepositoryFileRevealing
    private let finderOpener: any RepositoryFinderOpening
    private let accessibilityAnnouncer: any AccessibilityAnnouncing
    private let onSavedCategory: ((String) -> Void)?
    private var pendingRetry: ClassifierSettingsPendingSave?
    private var loadedClassifierSlugs: Set<String> = []

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        predictor: any CoreCategoryPredicting = AppCoreServices.categoryPredictor,
        ruleEditor: any CoreClassifierRuleEditing = AppCoreServices.classifierRuleEditor,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        classifierRulesManager: any ClassifierRulesManaging =
            ClassifierSettingsPlatformServices.classifierRulesManager,
        fileOpener: any RepositoryFileOpening = ClassifierSettingsPlatformServices.fileOpener,
        fileRevealer: any RepositoryFileRevealing = ClassifierSettingsPlatformServices.fileRevealer,
        finderOpener: any RepositoryFinderOpening = ClassifierSettingsPlatformServices.finderOpener,
        accessibilityAnnouncer: any AccessibilityAnnouncing =
            ClassifierSettingsPlatformServices.accessibilityAnnouncer,
        onSavedCategory: ((String) -> Void)? = nil
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.predictor = predictor
        self.ruleEditor = ruleEditor
        self.errorMapper = errorMapper
        self.classifierRulesManager = classifierRulesManager
        self.fileOpener = fileOpener
        self.fileRevealer = fileRevealer
        self.finderOpener = finderOpener
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.onSavedCategory = onSavedCategory
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

    var previewFilename: String {
        previewState.filename
    }

    var previewResult: ClassifyResultSnapshot? {
        previewState.result
    }

    var previewError: ClassifierSettingsPreviewError? {
        previewState.error
    }

    var isPreviewing: Bool {
        previewState.isPreviewing
    }

    var validationStatusLabel: String {
        switch validationState {
        case .idle:
            L10n.string("settings.classifier.validation.notValidated")
        case .validating:
            L10n.string("settings.classifier.validation.validating")
        case .passed:
            L10n.string("settings.classifier.validation.validated")
        case .failed:
            L10n.string("settings.classifier.validation.failed")
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
            await loadClassifierRuleEditor()
            loadedClassifierSlugs = currentClassifierSlugs()
            refreshLastValidBackupAvailability()
        } catch {
            savedConfig = nil
            draft = nil
            hasLastValidBackup = false
            classifierRuleEditor = ClassifierRuleEditorModelState()
            loadedClassifierSlugs = []
            loadState = await .failed(ClassifierSettingsErrorFactory.loadError(
                for: error,
                mapper: errorMapper
            ))
        }
    }

    func openClassifierYaml() {
        guard isLoaded, !isSaving else {
            return
        }

        clearFileActionState()
        do {
            try fileOpener.openFile(
                repoPath: repoPath,
                relativePath: ClassifierSettingsPaths.classifierRelativePath
            )
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.announcement.opened"))
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: L10n.string("settings.classifier.error.open"),
                recovery: L10n.string("settings.classifier.recovery.open")
            )
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.error.open"))
        }
    }

    func revealClassifierYamlInFinder() {
        guard isLoaded, !isSaving else {
            return
        }

        clearFileActionState()
        do {
            if classifierFileExists {
                try fileRevealer.revealFile(
                    repoPath: repoPath,
                    relativePath: ClassifierSettingsPaths.classifierRelativePath
                )
            } else {
                try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            }
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.announcement.revealed"))
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: L10n.string("settings.classifier.error.reveal"),
                recovery: L10n.string("settings.classifier.recovery.reveal")
            )
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.error.reveal"))
        }
    }

    func createDefaultClassifierYaml() async {
        guard isLoaded, !isSaving, !isValidating else {
            return
        }

        clearFileActionState()
        do {
            try classifierRulesManager.createDefaultClassifier(repoPath: repoPath)
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.announcement.defaultCreated"))
            _ = await validateClassifierRules()
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: L10n.string("settings.classifier.error.createDefault"),
                recovery: L10n.string("settings.classifier.recovery.createDefault")
            )
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.error.createDefault"))
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

    func validateClassifierRules() async -> Bool {
        guard isLoaded, !isSaving, !isValidating else {
            return false
        }

        guard classifierFileExists else {
            validationState = .failed(ClassifierSettingsValidationError(
                message: L10n.string("settings.classifier.error.missingFile"),
                recovery: L10n.string("settings.classifier.recovery.missingFile")
            ))
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.error.missingFile"))
            return false
        }

        validationState = .validating
        do {
            _ = try await predictor.predictCategory(
                repoPath: repoPath,
                filename: ClassifierSettingsPaths.validationProbeFilename
            )
        } catch {
            validationState = await .failed(ClassifierSettingsErrorFactory.validationError(
                for: error,
                mapper: errorMapper
            ))
            accessibilityAnnouncer.announce(validationStateAnnouncement)
            return false
        }

        do {
            try classifierRulesManager.storeLastValidBackup(repoPath: repoPath)
            refreshLastValidBackupAvailability()
            publishSavedCategoryIfNeeded()
            validationState = .passed
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.announcement.validated"))
            return true
        } catch {
            validationState = .failed(ClassifierSettingsValidationError(
                message: L10n.string("settings.classifier.error.backup"),
                recovery: L10n.string("settings.classifier.recovery.backup")
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
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.announcement.reverted"))
        } catch {
            validationState = .failed(ClassifierSettingsValidationError(
                message: L10n.string("settings.classifier.error.revert"),
                recovery: L10n.string("settings.classifier.recovery.revert")
            ))
            accessibilityAnnouncer.announce(L10n.string("settings.classifier.error.revert"))
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
            let mappedError = await ClassifierSettingsErrorFactory.saveError(
                for: error,
                mapper: errorMapper
            )
            saveError = mappedError
            pendingRetry = ClassifierSettingsPendingSave(config: config, error: mappedError)
        }
        isSaving = false
    }

    private var classifierConfigURL: URL {
        ClassifierSettingsPaths.classifierConfigURL(repoPath: repoPath)
    }

    private var classifierFileExists: Bool {
        classifierRulesManager.classifierFileExists(repoPath: repoPath)
    }

    private func refreshLastValidBackupAvailability() {
        hasLastValidBackup = classifierRulesManager.lastValidBackupExists(repoPath: repoPath)
    }

    private func currentClassifierSlugs() -> Set<String> {
        (try? classifierRulesManager.classifierCategorySlugs(repoPath: repoPath)).map(Set.init) ?? []
    }

    func publishSavedCategoryIfNeeded() {
        let currentSlugs = currentClassifierSlugs()
        defer { loadedClassifierSlugs = currentSlugs }
        let savedCategories = currentSlugs.subtracting(loadedClassifierSlugs)
        guard savedCategories.count == 1, let savedCategory = savedCategories.first else {
            return
        }
        onSavedCategory?(savedCategory)
    }

    private var validationStateAnnouncement: String {
        if case let .failed(error) = validationState {
            return error.message
        }

        return L10n.string("settings.classifier.error.validationFailed")
    }

    private func clearFileActionState() {
        fileActionError = nil
    }

    private func clearValidationState() {
        validationState = .idle
    }

    private func clearPreviewState() {
        previewState.clear()
    }
}
