import Foundation

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
