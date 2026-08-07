import Foundation

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
        case conflict(ClassifierRuleConflictReview)
        case failed(CoreErrorMappingSnapshot)
    }

    enum RecoveryState: Equatable {
        case idle
        case recovering(ClassifierRecoveryActionState)
        case succeeded(ClassifierRecoveryActionState)
        case failed(ClassifierRecoveryActionState, CoreErrorMappingSnapshot)
    }

    var loadState = LoadState.idle
    var saveState = SaveState.idle
    var recoveryState = RecoveryState.idle
    var interfaceLocaleIdentifier = "en"
    var rules: [ClassifierRuleRecordSnapshot] = []
    var repositoryLocalePolicy = ""
    var editingLocale: ClassifierEditingLocale?
    var pendingEditingLocale: ClassifierEditingLocale?
    var selectedRuleID: String?
    var draft: ClassifierRuleEditorDraft?
    var lastValidDraft: ClassifierRuleEditorDraft?
    var defaultRuleID = ""
    var health = ClassifierConfigHealthState.valid
    var recoveryActions: [ClassifierRecoveryActionState] = []
    var pendingRecoveryAction: ClassifierRecoveryActionState?
    var warning: String?
    var hasValidatedDraft = false
    var pendingExtension = ""
    var pendingKeyword = ""
    var isShowingImpactSummary = false
    var pendingMatcherRemoval: ClassifierRuleMatcherRemoval?
    var pendingDeleteConfirmation: ClassifierRuleDeleteConfirmation?

    var isReadOnly: Bool {
        health != .valid || editingLocale == nil
    }

    var canCreateRule: Bool {
        !isBusy && !isReadOnly
    }

    var selectedRule: ClassifierRuleRecordSnapshot? {
        rules.first { $0.ruleID == selectedRuleID }
    }

    var isBusy: Bool {
        if loadState == .loading || saveState == .saving {
            return true
        }
        if case .recovering = recoveryState {
            return true
        }
        return false
    }

    var hasDirtyDraft: Bool {
        guard let draft, let lastValidDraft else { return draft != nil }
        return draft != lastValidDraft
    }

    var canSave: Bool {
        guard let draft else { return false }
        return hasDirtyDraft && hasValidatedDraft && draft.previewConfirmed && draft.validationErrors.isEmpty &&
            !isBusy && !isReadOnly
    }

    var canRevert: Bool {
        hasDirtyDraft && !isBusy
    }

    var canDeleteSelectedRule: Bool {
        guard let selectedRule else { return false }
        return !selectedRule.isDefault && rules.count > 1 && !isBusy && !isReadOnly
    }

    var conflictReview: ClassifierRuleConflictReview? {
        guard case let .conflict(review) = saveState else { return nil }
        return review
    }

    init(interfaceLocaleIdentifier: String = "en") {
        self.interfaceLocaleIdentifier = interfaceLocaleIdentifier
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
    var validationErrors: [ClassifierRuleValidationIssue] = []

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
    case keyword
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

    mutating func markLoadFailed(_ mapping: CoreErrorMappingSnapshot) {
        loadState = .failed(mapping)
        saveState = .idle
    }

    mutating func markSaveFailed(_ mapping: CoreErrorMappingSnapshot) {
        loadState = rules.isEmpty ? .idle : .loaded
        saveState = .failed(mapping)
    }

    mutating func markSaveConflict(_ review: ClassifierRuleConflictReview) {
        loadState = .loaded
        saveState = .conflict(review)
    }

    mutating func requestRecovery(_ action: ClassifierRecoveryActionState) {
        guard recoveryActions.contains(action), !isBusy else { return }
        pendingRecoveryAction = action
        recoveryState = .idle
    }

    mutating func cancelRecovery() {
        pendingRecoveryAction = nil
        if case .failed = recoveryState {
            recoveryState = .idle
        }
    }

    mutating func markRecovering(_ action: ClassifierRecoveryActionState) {
        pendingRecoveryAction = nil
        recoveryState = .recovering(action)
    }

    mutating func markRecoverySucceeded(_ action: ClassifierRecoveryActionState) {
        recoveryState = .succeeded(action)
    }

    mutating func markRecoveryFailed(
        _ action: ClassifierRecoveryActionState,
        mapping: CoreErrorMappingSnapshot
    ) {
        recoveryState = .failed(action, mapping)
    }

    mutating func replaceSnapshot(_ snapshot: ClassifierRuleEditorSnapshotState) {
        rules = snapshot.rules
        defaultRuleID = snapshot.defaultRuleID
        repositoryLocalePolicy = snapshot.repositoryLocalePolicy
        editingLocale = snapshot.editingLocale
        health = snapshot.health
        recoveryActions = snapshot.recoveryActions
        pendingEditingLocale = nil
        pendingRecoveryAction = nil
        recoveryState = .idle
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
        guard !isReadOnly else { return }
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
            categoryName: displayName(for: selectedRule),
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

    mutating func switchEditingLocale(to locale: ClassifierEditingLocale) {
        guard locale != editingLocale else { return }
        editingLocale = locale
        pendingEditingLocale = nil
        setDraftFromSelectedRule()
        hasValidatedDraft = false
        clearRiskConfirmations()
        saveState = .idle
    }

    func displayName(for rule: ClassifierRuleRecordSnapshot) -> String {
        let exact = rule.displayNames[repositoryLocalePolicy]
        if let exact, !exact.isEmpty { return exact }
        if let locale = concretePresentationLocale,
           let localized = rule.displayNames[locale.rawValue], !localized.isEmpty {
            return localized
        }
        return rule.displayNames[ClassifierEditingLocale.en.rawValue] ?? rule.slug
    }

    func fallbackDisplayName(for draft: ClassifierRuleEditorDraft) -> String? {
        guard draft.displayName.isEmpty,
              let ruleID = draft.ruleID,
              let rule = rules.first(where: { $0.ruleID == ruleID })
        else { return nil }
        let fallback = displayName(for: rule)
        return fallback == rule.slug ? rule.slug : fallback
    }

    private var concretePresentationLocale: ClassifierEditingLocale? {
        let language = RepositoryContentLanguage(snapshotValue: repositoryLocalePolicy)
        switch language {
        case .zhHans: return .zhHans
        case .en: return .en
        case .followInterface:
            return interfaceLocaleIdentifier == "zh-Hans" ? .zhHans : .en
        case .unsupported: return nil
        }
    }
}

extension ClassifierRuleEditorModelState {
    private mutating func setDraftFromSelectedRule() {
        guard let selectedRule else {
            draft = nil
            lastValidDraft = nil
            return
        }
        guard let editingLocale, health == .valid else {
            draft = nil
            lastValidDraft = nil
            return
        }
        let selectedDraft = ClassifierRuleEditorDraft(record: selectedRule, editingLocale: editingLocale)
        draft = selectedDraft
        lastValidDraft = selectedDraft
    }
}
