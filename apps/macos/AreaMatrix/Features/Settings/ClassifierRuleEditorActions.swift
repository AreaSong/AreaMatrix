import Foundation

private enum ClassifierRuleEditorActionError: LocalizedError {
    case missingRuleDraft

    var errorDescription: String? {
        switch self {
        case .missingRuleDraft:
            L10n.string("settings.classifier.ruleDraftMissing")
        }
    }
}

struct ClassifierRuleConflictReview: Equatable {
    var code: String
    var frozenEditingLocale: ClassifierEditingLocale
    var localDraft: ClassifierRuleEditorDraft
    var latestSnapshot: ClassifierRuleEditorSnapshotState

    var latestDraft: ClassifierRuleEditorDraft? {
        guard let ruleID = localDraft.ruleID,
              let rule = latestSnapshot.rules.first(where: { $0.ruleID == ruleID })
        else { return nil }
        return ClassifierRuleEditorDraft(record: rule, editingLocale: frozenEditingLocale)
    }
}

extension ClassifierSettingsModel {
    func loadClassifierRuleEditor() async {
        guard isLoaded else { return }
        classifierRuleEditor.markLoading()
        do {
            let snapshot = try await ruleEditor.listClassifierRules(
                repoPath: repoPath,
                editingLocale: preferredClassifierEditingLocale
            )
            classifierRuleEditor.replaceSnapshot(snapshot)
        } catch {
            await classifierRuleEditor.markLoadFailed(mappedClassifierRuleEditorError(error))
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

    @discardableResult
    func saveClassifierRuleDraft() async -> Bool {
        guard !classifierRuleEditor.isBusy else { return false }
        guard classifierRuleEditor.validateDraft() else { return false }

        classifierRuleEditor.markSaving()
        do {
            let snapshot = try await saveClassifierRuleRequest()
            classifierRuleEditor.replaceSnapshot(snapshot)
            publishSavedCategoryIfNeeded()
            return true
        } catch {
            if await captureClassifierRuleConflict(error) {
                return false
            }
            await classifierRuleEditor.markSaveFailed(mappedClassifierRuleEditorError(error))
            return false
        }
    }

    func reloadLatestClassifierRuleConflict() {
        guard let review = classifierRuleEditor.conflictReview else { return }
        classifierRuleEditor.replaceSnapshot(review.latestSnapshot)
    }

    func reviewLatestClassifierRuleConflict() {
        guard let review = classifierRuleEditor.conflictReview else { return }
        classifierRuleEditor.rebaseConflictForReview(review)
    }

    func requestClassifierEditingLocale(_ locale: ClassifierEditingLocale) {
        guard locale != classifierRuleEditor.editingLocale else { return }
        if classifierRuleEditor.hasDirtyDraft {
            classifierRuleEditor.pendingEditingLocale = locale
        } else {
            classifierRuleEditor.switchEditingLocale(to: locale)
        }
    }

    func saveAndSwitchClassifierEditingLocale() async {
        guard let locale = classifierRuleEditor.pendingEditingLocale else { return }
        if await saveClassifierRuleDraft() {
            classifierRuleEditor.switchEditingLocale(to: locale)
        }
    }

    func discardAndSwitchClassifierEditingLocale() {
        guard let locale = classifierRuleEditor.pendingEditingLocale else { return }
        classifierRuleEditor.revertDraft()
        classifierRuleEditor.switchEditingLocale(to: locale)
    }

    func cancelClassifierEditingLocaleSwitch() {
        classifierRuleEditor.pendingEditingLocale = nil
    }

    func requestClassifierRecovery(_ action: ClassifierRecoveryActionState) {
        classifierRuleEditor.requestRecovery(action)
    }

    func cancelClassifierRecovery() {
        classifierRuleEditor.cancelRecovery()
    }

    func confirmClassifierRecovery() async {
        guard let action = classifierRuleEditor.pendingRecoveryAction,
              !classifierRuleEditor.isBusy
        else { return }

        classifierRuleEditor.markRecovering(action)
        do {
            let snapshot = try await performClassifierRecovery(action)
            classifierRuleEditor.replaceSnapshot(snapshot)
            classifierRuleEditor.markRecoverySucceeded(action)
            refreshLoadedClassifierSlugs()
        } catch {
            let mapping = await mappedClassifierRuleEditorError(error)
            classifierRuleEditor.markRecoveryFailed(action, mapping: mapping)
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
            await classifierRuleEditor.markSaveFailed(mappedClassifierRuleEditorError(error))
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
        throw ClassifierRuleEditorActionError.missingRuleDraft
    }

    private func captureClassifierRuleConflict(_ error: Error) async -> Bool {
        guard let conflict = CoreConflictSnapshot(error),
              ["classifier_rule_observed_state", "repository_locale_policy"].contains(conflict.path),
              let locale = classifierRuleEditor.editingLocale,
              let localDraft = classifierRuleEditor.draft
        else { return false }
        do {
            let latest = try await ruleEditor.listClassifierRules(repoPath: repoPath, editingLocale: locale)
            classifierRuleEditor.markSaveConflict(ClassifierRuleConflictReview(
                code: conflict.path,
                frozenEditingLocale: locale,
                localDraft: localDraft,
                latestSnapshot: latest
            ))
        } catch {
            await classifierRuleEditor.markSaveFailed(mappedClassifierRuleEditorError(error))
        }
        return true
    }

    private func performClassifierRecovery(
        _ action: ClassifierRecoveryActionState
    ) async throws -> ClassifierRuleEditorSnapshotState {
        let editingLocale = classifierRuleEditor.editingLocale ?? preferredClassifierEditingLocale
        switch action {
        case .createDefault:
            return try await ruleEditor.createDefaultClassifier(
                repoPath: repoPath,
                confirmed: true,
                editingLocale: editingLocale
            )
        case .restoreDefault:
            return try await ruleEditor.restoreDefaultClassifier(
                repoPath: repoPath,
                confirmed: true,
                editingLocale: editingLocale
            )
        case .restoreLastValid:
            return try await ruleEditor.restoreLastValidClassifier(
                repoPath: repoPath,
                confirmed: true,
                editingLocale: editingLocale
            )
        }
    }

    private func mappedClassifierRuleEditorError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }

    var preferredClassifierEditingLocale: ClassifierEditingLocale? {
        guard let locale = savedConfig?.locale else { return nil }
        switch RepositoryContentLanguage(snapshotValue: locale) {
        case .zhHans: return ClassifierEditingLocale.zhHans
        case .en: return ClassifierEditingLocale.en
        case .followInterface:
            return AppLanguageRuntime.shared.resolvedIdentifier() == "zh-Hans" ? .zhHans : .en
        case .unsupported: return nil
        }
    }
}

private extension ClassifierRuleEditorModelState {
    mutating func rebaseConflictForReview(_ review: ClassifierRuleConflictReview) {
        let latest = review.latestSnapshot
        rules = latest.rules
        defaultRuleID = latest.defaultRuleID
        repositoryLocalePolicy = latest.repositoryLocalePolicy
        editingLocale = review.frozenEditingLocale
        health = latest.health
        recoveryActions = latest.recoveryActions
        warning = latest.warning
        selectedRuleID = review.localDraft.ruleID
        draft = review.localDraft
        lastValidDraft = review.latestDraft
        hasValidatedDraft = review.localDraft.validationErrors.isEmpty && review.latestDraft != nil
        loadState = .loaded
        saveState = .idle
        clearRiskConfirmations()
    }
}

extension ClassifierRuleEditorModelState {
    var createRequest: ClassifierRuleCreateRequestSnapshot? {
        guard let draft, let editingLocale, draft.ruleID == nil, draft.validationErrors.isEmpty else { return nil }
        return ClassifierRuleCreateRequestSnapshot(
            repositoryLocalePolicy: repositoryLocalePolicy,
            editingLocale: editingLocale,
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
        guard let draft, let baseline = lastValidDraft, let editingLocale,
              let ruleID = draft.ruleID, baseline.ruleID == ruleID,
              draft.validationErrors.isEmpty
        else { return nil }
        return ClassifierRuleUpdateSnapshot(
            repositoryLocalePolicy: repositoryLocalePolicy,
            editingLocale: editingLocale,
            ruleID: ruleID,
            observed: ClassifierRuleObservedStateSnapshot(draft: baseline),
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
}

extension ClassifierRuleEditorDraft {
    init(record: ClassifierRuleRecordSnapshot, editingLocale: ClassifierEditingLocale) {
        ruleID = record.ruleID
        slug = record.slug
        displayName = record.displayName(for: editingLocale)
        description = record.description(for: editingLocale)
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

extension ClassifierRuleObservedStateSnapshot {
    init(draft: ClassifierRuleEditorDraft) {
        ruleID = draft.ruleID ?? ""
        slug = draft.slug
        displayName = draft.displayName
        description = draft.description
        extensions = draft.extensions
        keywords = draft.keywords
        priority = draft.priority
        namingTemplate = draft.namingTemplateValue
    }
}
