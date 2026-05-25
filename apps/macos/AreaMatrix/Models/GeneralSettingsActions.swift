import Foundation

extension OnboardingModel {
    @MainActor
    func showGeneralSettings(opening: RepositoryOpeningResult) {
        settingsGeneralSelectedTab = "general"
        route = .settingsGeneral(opening)
        toastMessage = nil
    }

    @MainActor
    func closeGeneralSettings(opening: RepositoryOpeningResult) {
        route = Self.mainRoute(for: opening)
    }

    @MainActor
    func refreshAfterGeneralSettings(opening: RepositoryOpeningResult) async {
        do {
            let refreshed = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: opening.config.repoPath)
            finishSuccessfulRepositoryOpen(refreshed)
        } catch {
            await routeMainOpeningFailure(error, repoPath: opening.config.repoPath)
        }
    }
}

extension ClassifierSettingsModel {
    func loadClassifierRuleEditor() async {
        guard isLoaded else { return }
        classifierRuleEditor.markLoading()
        do {
            let snapshot = try await ruleEditor.listClassifierRules(repoPath: repoPath)
            classifierRuleEditor.replaceSnapshot(snapshot)
        } catch {
            await classifierRuleEditor.markFailed(mappedClassifierRuleEditorError(error))
        }
    }

    func createClassifierRule() {
        classifierRuleEditor.createDraft()
    }

    func selectClassifierRule(ruleID: String) {
        classifierRuleEditor.select(ruleID: ruleID)
    }

    func updateClassifierRuleDraft(_ draft: ClassifierRuleEditorDraft) {
        classifierRuleEditor.updateDraft(draft)
    }

    func addClassifierRuleExtension(_ value: String) {
        classifierRuleEditor.addExtension(value)
    }

    func addClassifierRuleKeyword(_ value: String) {
        classifierRuleEditor.addKeyword(value)
    }

    func requestRemoveClassifierRuleExtension(_ value: String) {
        classifierRuleEditor.requestRemoveExtension(value)
    }

    func requestRemoveClassifierRuleKeyword(_ value: String) {
        classifierRuleEditor.requestRemoveKeyword(value)
    }

    func requestClassifierRuleImpactSummary() {
        classifierRuleEditor.requestImpactSummary()
    }

    func confirmClassifierRuleImpactSummary() {
        classifierRuleEditor.confirmImpactSummary()
    }

    func validateClassifierRuleDraft() {
        classifierRuleEditor.validateDraft()
    }

    func saveClassifierRuleDraft() async {
        guard !classifierRuleEditor.isBusy else { return }
        guard classifierRuleEditor.validateDraft() else { return }

        classifierRuleEditor.markSaving()
        do {
            let snapshot = try await saveClassifierRuleRequest()
            classifierRuleEditor.replaceSnapshot(snapshot)
            publishSavedCategoryIfNeeded()
        } catch {
            await classifierRuleEditor.markFailed(mappedClassifierRuleEditorError(error))
        }
    }

    func requestDeleteSelectedClassifierRule() {
        classifierRuleEditor.requestDeleteSelectedRule()
    }

    func cancelClassifierRuleRiskConfirmation() {
        classifierRuleEditor.clearRiskConfirmations()
    }

    func confirmDeleteSelectedClassifierRule() async {
        guard let request = classifierRuleEditor.deleteRequest, !classifierRuleEditor.isBusy else {
            return
        }

        classifierRuleEditor.markSaving()
        do {
            let snapshot = try await ruleEditor.deleteClassifierRule(repoPath: repoPath, request: request)
            classifierRuleEditor.replaceSnapshot(snapshot)
        } catch {
            await classifierRuleEditor.markFailed(mappedClassifierRuleEditorError(error))
        }
    }

    func revertClassifierRuleDraft() {
        classifierRuleEditor.revertDraft()
    }

    private func saveClassifierRuleRequest() async throws -> ClassifierRuleEditorSnapshotState {
        if let request = classifierRuleEditor.createRequest {
            return try await ruleEditor.createClassifierRule(repoPath: repoPath, request: request)
        }
        if let request = classifierRuleEditor.updateRequest {
            return try await ruleEditor.updateClassifierRule(repoPath: repoPath, request: request)
        }
        throw CoreError.Config(reason: "No classifier rule draft is selected.")
    }

    private func mappedClassifierRuleEditorError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

struct ClassifierRuleEditorModelState: Equatable {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(CoreErrorMappingSnapshot)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved(String)
        case failed(CoreErrorMappingSnapshot)
    }

    var loadState = LoadState.idle
    var saveState = SaveState.idle
    var rules: [ClassifierRuleRecordSnapshot] = []
    var selectedRuleID: String?
    var draft: ClassifierRuleEditorDraft?
    var lastValidDraft: ClassifierRuleEditorDraft?
    var defaultRuleID = ""
    var warning: String?
    var hasValidatedDraft = false
    var pendingExtension = ""
    var pendingKeyword = ""
    var isShowingImpactSummary = false
    var pendingMatcherRemoval: ClassifierRuleMatcherRemoval?
    var pendingDeleteConfirmation: ClassifierRuleDeleteConfirmation?

    var selectedRule: ClassifierRuleRecordSnapshot? {
        rules.first { $0.ruleID == selectedRuleID }
    }

    var isBusy: Bool {
        loadState == .loading || saveState == .saving
    }

    var hasDirtyDraft: Bool {
        guard let draft, let lastValidDraft else { return draft != nil }
        return draft != lastValidDraft
    }

    var canSave: Bool {
        guard let draft else { return false }
        return hasDirtyDraft && hasValidatedDraft && draft.previewConfirmed && draft.validationErrors.isEmpty && !isBusy
    }

    var canRevert: Bool {
        hasDirtyDraft && !isBusy
    }

    var canDeleteSelectedRule: Bool {
        guard let selectedRule else { return false }
        return !selectedRule.isDefault && rules.count > 1 && !isBusy
    }
}

struct ClassifierRuleEditorDraft: Equatable {
    var ruleID: String?
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String
    var isDefault: Bool
    var previewConfirmed: Bool
    var validationErrors: [String] = []

    static var empty: ClassifierRuleEditorDraft {
        ClassifierRuleEditorDraft(
            ruleID: nil,
            slug: "",
            displayName: "",
            description: "",
            extensions: [],
            keywords: [],
            priority: 0,
            namingTemplate: "",
            isDefault: false,
            previewConfirmed: true
        )
    }
}

enum ClassifierRuleMatcherKind: String, Equatable {
    case fileExtension = "extension"
    case keyword = "keyword"
}

struct ClassifierRuleMatcherRemoval: Equatable {
    var kind: ClassifierRuleMatcherKind
    var value: String
    var categoryName: String
}

struct ClassifierRuleDeleteConfirmation: Equatable {
    var ruleID: String
    var categoryName: String
    var replacementCategory: String?
}

extension ClassifierRuleEditorModelState {
    mutating func markLoading() {
        loadState = .loading
        saveState = .idle
    }

    mutating func markSaving() {
        saveState = .saving
    }

    mutating func markFailed(_ mapping: CoreErrorMappingSnapshot) {
        loadState = rules.isEmpty ? .failed(mapping) : .loaded
        saveState = .failed(mapping)
    }

    mutating func replaceSnapshot(_ snapshot: ClassifierRuleEditorSnapshotState) {
        rules = snapshot.rules
        defaultRuleID = snapshot.defaultRuleID
        warning = snapshot.warning
        loadState = .loaded
        let selected = snapshot.updatedRuleID ?? selectedRuleID ?? rules.first?.ruleID
        selectedRuleID = rules.contains { $0.ruleID == selected } ? selected : rules.first?.ruleID
        setDraftFromSelectedRule()
        hasValidatedDraft = false
        clearRiskConfirmations()
        saveState = snapshot.updatedRuleID.map { .saved($0) } ?? .idle
    }

    mutating func createDraft() {
        selectedRuleID = nil
        draft = .empty
        lastValidDraft = nil
        hasValidatedDraft = false
        clearRiskConfirmations()
        saveState = .idle
    }

    mutating func select(ruleID: String) {
        selectedRuleID = ruleID
        setDraftFromSelectedRule()
        hasValidatedDraft = false
        clearRiskConfirmations()
        saveState = .idle
    }

    mutating func updateDraft(_ newDraft: ClassifierRuleEditorDraft) {
        draft = newDraft.normalizedForEditing()
        hasValidatedDraft = false
        clearRiskConfirmations()
        saveState = .idle
    }

    @discardableResult
    mutating func validateDraft() -> Bool {
        guard var draft else { return false }
        draft.validationErrors = ClassifierRuleEditorValidation.errors(for: draft, existingRules: rules)
        self.draft = draft
        hasValidatedDraft = true
        saveState = .idle
        return draft.validationErrors.isEmpty
    }

    mutating func revertDraft() {
        draft = lastValidDraft
        hasValidatedDraft = false
        saveState = .idle
    }

    mutating func addExtension(_ value: String) {
        guard var draft else { return }
        let normalized = ClassifierRuleEditorValidation.normalizedExtension(value)
        guard !normalized.isEmpty, !draft.extensions.contains(normalized) else { return }
        draft.extensions.append(normalized)
        updateDraft(draft)
    }

    mutating func addKeyword(_ value: String) {
        guard var draft else { return }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !draft.keywords.contains(normalized) else { return }
        draft.keywords.append(normalized)
        updateDraft(draft)
    }

    mutating func requestRemoveExtension(_ value: String) {
        requestMatcherRemoval(kind: .fileExtension, value: value)
    }

    mutating func requestRemoveKeyword(_ value: String) {
        requestMatcherRemoval(kind: .keyword, value: value)
    }

    mutating func requestImpactSummary() {
        guard draft != nil else { return }
        isShowingImpactSummary = true
        pendingDeleteConfirmation = nil
        saveState = .idle
    }

    mutating func confirmImpactSummary() {
        if let pendingMatcherRemoval {
            confirm(pendingMatcherRemoval)
            return
        }
        guard var draft else { return }
        draft.previewConfirmed = true
        isShowingImpactSummary = false
        updateDraft(draft)
    }

    mutating func requestDeleteSelectedRule() {
        guard let selectedRule, canDeleteSelectedRule else { return }
        pendingDeleteConfirmation = ClassifierRuleDeleteConfirmation(
            ruleID: selectedRule.ruleID,
            categoryName: selectedRule.displayName.isEmpty ? selectedRule.slug : selectedRule.displayName,
            replacementCategory: defaultRuleID.isEmpty ? nil : defaultRuleID
        )
        isShowingImpactSummary = false
        pendingMatcherRemoval = nil
        saveState = .idle
    }

    mutating func clearRiskConfirmations() {
        isShowingImpactSummary = false
        pendingMatcherRemoval = nil
        pendingDeleteConfirmation = nil
    }

    private mutating func requestMatcherRemoval(kind: ClassifierRuleMatcherKind, value: String) {
        guard let draft else { return }
        pendingMatcherRemoval = ClassifierRuleMatcherRemoval(
            kind: kind,
            value: value,
            categoryName: draft.displayName.isEmpty ? draft.slug : draft.displayName
        )
        isShowingImpactSummary = true
        pendingDeleteConfirmation = nil
        saveState = .idle
    }

    private mutating func confirm(_ removal: ClassifierRuleMatcherRemoval) {
        guard var draft else { return }
        if removal.kind == .fileExtension {
            draft.extensions.removeAll { $0 == removal.value }
        } else {
            draft.keywords.removeAll { $0 == removal.value }
        }
        draft.previewConfirmed = true
        self.draft = draft.normalizedForEditing()
        hasValidatedDraft = false
        clearRiskConfirmations()
        saveState = .idle
    }
}

extension ClassifierRuleEditorModelState {
    var createRequest: ClassifierRuleCreateRequestSnapshot? {
        guard let draft, draft.ruleID == nil, draft.validationErrors.isEmpty else { return nil }
        return ClassifierRuleCreateRequestSnapshot(
            slug: draft.slug,
            displayName: draft.displayName,
            description: draft.description,
            extensions: draft.extensions,
            keywords: draft.keywords,
            priority: draft.priority,
            namingTemplate: draft.namingTemplateValue
        )
    }

    var updateRequest: ClassifierRuleUpdateSnapshot? {
        guard let draft, let ruleID = draft.ruleID, draft.validationErrors.isEmpty else { return nil }
        return ClassifierRuleUpdateSnapshot(
            ruleID: ruleID,
            slug: draft.slug,
            displayName: draft.displayName,
            description: draft.description,
            extensions: draft.extensions,
            keywords: draft.keywords,
            priority: draft.priority,
            namingTemplate: draft.namingTemplateValue,
            previewConfirmed: draft.previewConfirmed
        )
    }

    var deleteRequest: ClassifierRuleDeleteRequestSnapshot? {
        guard let selectedRule, canDeleteSelectedRule else { return nil }
        guard pendingDeleteConfirmation?.ruleID == selectedRule.ruleID else { return nil }
        return ClassifierRuleDeleteRequestSnapshot(
            ruleID: selectedRule.ruleID,
            replacementCategory: defaultRuleID.isEmpty ? nil : defaultRuleID,
            previewConfirmed: true
        )
    }

    private mutating func setDraftFromSelectedRule() {
        guard let selectedRule else {
            draft = nil
            lastValidDraft = nil
            return
        }
        let selectedDraft = ClassifierRuleEditorDraft(record: selectedRule)
        draft = selectedDraft
        lastValidDraft = selectedDraft
    }
}

extension ClassifierRuleEditorDraft {
    init(record: ClassifierRuleRecordSnapshot) {
        ruleID = record.ruleID
        slug = record.slug
        displayName = record.displayName
        description = record.description
        extensions = record.extensions
        keywords = record.keywords
        priority = record.priority
        namingTemplate = record.namingTemplate ?? ""
        isDefault = record.isDefault
        previewConfirmed = true
    }

    var namingTemplateValue: String? {
        let trimmed = namingTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedForEditing() -> ClassifierRuleEditorDraft {
        var copy = self
        copy.slug = copy.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.displayName = copy.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.description = copy.description.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.namingTemplate = copy.namingTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.extensions = copy.extensions.map(ClassifierRuleEditorValidation.normalizedExtension)
        copy.keywords = copy.keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return copy
    }
}
