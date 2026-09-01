import AreaMatrixFeatureSettings
import Combine
import Foundation

@MainActor
final class ClassifierSettingsModel: ObservableObject {
    @Published private(set) var loadState: ClassifierSettingsLoadState = .loading
    @Published private(set) var draft: ClassifierSettingsDraft?
    @Published private(set) var savedConfig: AppRepoConfigSnapshot?
    @Published private(set) var saveError: ClassifierSettingsSaveError?
    @Published private(set) var fileActionError: ClassifierSettingsFileActionError?
    @Published var previewState = ClassifierSettingsPreviewState<
        ClassifyResultSnapshot,
        ClassifierSettingsPreviewError
    >()
    @Published private(set) var isSaving = false
    @Published private(set) var validationState: ClassifierSettingsValidationState = .idle
    @Published var classifierRuleEditor = ClassifierRuleEditorModelState()

    let repoPath: String
    let ruleEditor: any CoreClassifierRuleEditing
    let interfaceLocaleIdentifierProvider: @MainActor () -> String

    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    let predictor: any CoreCategoryPredicting
    let errorMapper: any CoreErrorMapping
    private let fileOpener: any RepositoryFileOpening
    private let fileRevealer: any RepositoryFileRevealing
    private let finderOpener: any RepositoryFinderOpening
    private let accessibilityAnnouncer: any AccessibilityAnnouncing
    private let onSavedCategory: ((String) -> Void)?
    private var pendingRetry: ClassifierSettingsPendingSave?
    private var loadedClassifierSlugs: Set<String> = []

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading,
        updater: any CoreConfigurationUpdating,
        predictor: any CoreCategoryPredicting,
        ruleEditor: any CoreClassifierRuleEditing,
        interfaceLocaleIdentifier: @escaping @MainActor () -> String = { "en" },
        errorMapper: any CoreErrorMapping,
        fileOpener: any RepositoryFileOpening,
        fileRevealer: any RepositoryFileRevealing,
        finderOpener: any RepositoryFinderOpening,
        accessibilityAnnouncer: any AccessibilityAnnouncing,
        onSavedCategory: ((String) -> Void)? = nil
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.predictor = predictor
        self.ruleEditor = ruleEditor
        interfaceLocaleIdentifierProvider = interfaceLocaleIdentifier
        self.errorMapper = errorMapper
        self.fileOpener = fileOpener
        self.fileRevealer = fileRevealer
        self.finderOpener = finderOpener
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.onSavedCategory = onSavedCategory
        classifierRuleEditor.interfaceLocaleIdentifier = interfaceLocaleIdentifier()
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
        classifierRuleEditor.recoveryActions.contains(.restoreLastValid) &&
            !isSaving && validationState != .validating
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
        refreshInterfaceLocaleIdentifier()
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
            refreshLoadedClassifierSlugs()
        } catch {
            savedConfig = nil
            draft = nil
            classifierRuleEditor = ClassifierRuleEditorModelState(
                interfaceLocaleIdentifier: interfaceLocaleIdentifierProvider()
            )
            loadedClassifierSlugs = []
            loadState = await .failed(ClassifierSettingsErrorFactory.loadError(
                for: error,
                mapper: errorMapper
            ))
        }
    }

    func refreshInterfaceLocaleIdentifier() {
        classifierRuleEditor.interfaceLocaleIdentifier = interfaceLocaleIdentifierProvider()
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
            accessibilityAnnouncer.announce(L10n.message("settings.classifier.announcement.opened"))
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: L10n.message("settings.classifier.error.open"),
                recovery: L10n.message("settings.classifier.recovery.open")
            )
            accessibilityAnnouncer.announce(L10n.message("settings.classifier.error.open"))
        }
    }

    func revealClassifierYamlInFinder() {
        guard isLoaded, !isSaving else {
            return
        }

        clearFileActionState()
        do {
            if classifierRuleEditor.health != .missing {
                try fileRevealer.revealFile(
                    repoPath: repoPath,
                    relativePath: ClassifierSettingsPaths.classifierRelativePath
                )
            } else {
                try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            }
            accessibilityAnnouncer.announce(L10n.message("settings.classifier.announcement.revealed"))
        } catch {
            fileActionError = ClassifierSettingsFileActionError(
                message: L10n.message("settings.classifier.error.reveal"),
                recovery: L10n.message("settings.classifier.recovery.reveal")
            )
            accessibilityAnnouncer.announce(L10n.message("settings.classifier.error.reveal"))
        }
    }

    func createDefaultClassifierYaml() async {
        guard isLoaded, !isSaving, !isValidating else { return }
        requestClassifierRecovery(.createDefault)
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

        validationState = .validating
        do {
            let snapshot = try await ruleEditor.listClassifierRules(
                repoPath: repoPath,
                editingLocale: classifierRuleEditor.editingLocale ?? preferredClassifierEditingLocale
            )
            classifierRuleEditor.replaceSnapshot(snapshot)
            guard snapshot.health == .valid else {
                validationState = .failed(ClassifierSettingsValidationError(
                    message: L10n.message("settings.classifier.error.validationFailed"),
                    recovery: L10n.message("settings.classifier.recovery.open")
                ))
                accessibilityAnnouncer.announce(validationStateAnnouncement)
                return false
            }
        } catch {
            validationState = await .failed(ClassifierSettingsErrorFactory.validationError(
                for: error,
                mapper: errorMapper
            ))
            accessibilityAnnouncer.announce(validationStateAnnouncement)
            return false
        }

        publishSavedCategoryIfNeeded()
        validationState = .passed
        accessibilityAnnouncer.announce(L10n.message("settings.classifier.announcement.validated"))
        return true
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else {
            return
        }

        await persist(updating: pendingRetry.config)
    }

    func revertToLastValid() async {
        guard canRevertToLastValid else { return }
        requestClassifierRecovery(.restoreLastValid)
        await confirmClassifierRecovery()
    }

    private func persist(updating config: AppRepoConfigSnapshot) async {
        guard let savedConfig else { return }
        isSaving = true
        saveError = nil
        do {
            let updated = try await updater.updateConfig(repoPath: repoPath, from: savedConfig, to: config)
            self.savedConfig = updated
            draft = ClassifierSettingsDraft(config: updated)
            pendingRetry = nil
            clearPreviewState()
        } catch {
            draft = ClassifierSettingsDraft(config: savedConfig)
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

    private func currentClassifierSlugs() -> Set<String> {
        Set(classifierRuleEditor.rules.map(\.slug))
    }

    func refreshLoadedClassifierSlugs() {
        loadedClassifierSlugs = currentClassifierSlugs()
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

    private var validationStateAnnouncement: LocalizedMessage {
        if case let .failed(error) = validationState {
            return error.message
        }

        return L10n.message("settings.classifier.error.validationFailed")
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
