import Combine
import Foundation

@MainActor
final class AIPrivacyRulesModel: ObservableObject {
    @Published private(set) var loadState: AIPrivacyRulesLoadState = .loading
    @Published private(set) var snapshot: AiPrivacyRulesSnapshot?
    @Published private(set) var saveError: AISettingsError?
    @Published private(set) var feedback: LocalizedMessage?
    @Published private(set) var evaluation: AiPrivacyEvaluationReport?
    @Published private(set) var featureEvaluations: [AIPrivacyRuleFeatureEvaluation] = []
    @Published private(set) var isSaving = false
    @Published private(set) var isEvaluating = false

    let repoPath: String
    private let rulesManager: any CoreAIPrivacyRulesManaging
    private let evaluator: any CoreAIPrivacyEvaluating
    private let errorMapper: any CoreErrorMapping
    private weak var settingsSync: (any AIPrivacyGateSettingsSynchronizing)?
    private var savedSnapshot: AiPrivacyRulesSnapshot?
    private var pendingSaveRequest: AiPrivacyRulesUpdateRequest?
    private var pendingSaveSuccess = L10n.message("Remote allowed fields saved.")
    private var pendingSaveFailureMessage = L10n.message("AI privacy rules could not be saved.")
    private var pendingSnapshotOnFailure: AiPrivacyRulesSnapshot?

    init(
        repoPath: String,
        rulesManager: any CoreAIPrivacyRulesManaging = CoreBridge(),
        evaluator: any CoreAIPrivacyEvaluating = AppCoreServices.aiPrivacyRules,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        settingsSync: (any AIPrivacyGateSettingsSynchronizing)? = nil
    ) {
        self.repoPath = repoPath
        self.rulesManager = rulesManager
        self.evaluator = evaluator
        self.errorMapper = errorMapper
        self.settingsSync = settingsSync
    }

    var rules: [AiPrivacyRuleRecord] {
        snapshot?.rules ?? []
    }

    var fields: [AiPrivacyFieldState] {
        snapshot?.remoteAllowedFields ?? []
    }

    var canEditRemoteFields: Bool {
        snapshot?.privacyGateEnabled == true && !isSaving
    }

    func load() async {
        loadState = .loading
        do {
            let loaded = try await rulesManager.loadAIPrivacyRules(repoPath: repoPath)
            snapshot = loaded
            savedSnapshot = loaded
            saveError = nil
            clearPendingSave()
            loadState = .loaded
        } catch {
            let error = await privacyError(for: error, message: L10n.message("AI privacy rules could not be loaded."))
            snapshot = nil
            savedSnapshot = nil
            loadState = .failed(error)
        }
    }

    @discardableResult
    func setPrivacyGate(_ enabled: Bool) async -> Bool {
        guard let snapshot, snapshot.privacyGateEnabled != enabled else { return false }
        return await save(
            snapshot,
            gate: enabled,
            rules: snapshot.ruleInputs,
            success: gateSuccess(enabled),
            failureMessage: L10n.message("Remote AI privacy gate could not be updated.")
        )
    }

    @discardableResult
    func setField(_ field: AiPrivacyInputField, allowRemote: Bool) async -> Bool {
        guard let snapshot else { return false }
        let fields = snapshot.remoteAllowedFields.map {
            AiPrivacyFieldRule(field: $0.field, allowRemote: $0.field == field ? allowRemote : $0.allowRemote)
        }
        let pendingSnapshot = AiPrivacyRulesSnapshot(
            privacyGateEnabled: snapshot.privacyGateEnabled,
            rules: snapshot.rules,
            remoteAllowedFields: fields.map { fieldRule in AiPrivacyFieldState(
                field: fieldRule.field,
                allowRemote: fieldRule.allowRemote,
                lastMatchedCount: snapshot.remoteAllowedFields.first { fieldState in
                    fieldState.field == fieldRule.field
                }?.lastMatchedCount ?? 0
            ) },
            providerScope: snapshot.providerScope,
            updatedAt: snapshot.updatedAt,
            remoteBlockedByDefault: snapshot.remoteBlockedByDefault
        )
        return await save(
            snapshot,
            gate: snapshot.privacyGateEnabled,
            rules: snapshot.ruleInputs,
            fields: fields,
            success: L10n.message("Remote allowed fields saved."),
            failureMessage: L10n.message("Privacy field settings could not be saved."),
            pendingSnapshotOnFailure: pendingSnapshot
        )
    }

    @discardableResult
    func setRuleEnabled(_ record: AiPrivacyRuleRecord, enabled: Bool) async -> Bool {
        guard let snapshot else { return false }
        var input = AiPrivacyRuleInput(aiPrivacyRulesRecord: record)
        input.enabled = enabled
        return await saveRule(input, base: snapshot, success: L10n.message("Privacy rule saved."))
    }

    @discardableResult
    func addRule(kind: AiPrivacyRuleKind, pattern: String, appliesTo: AiPrivacyRuleAppliesTo) async -> Bool {
        guard let snapshot else { return false }
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await saveRule(AiPrivacyRuleInput(
            ruleId: nil,
            name: "\(kind.aiPrivacyRulesLabel) \(trimmed)",
            kind: kind,
            pattern: trimmed,
            appliesTo: appliesTo,
            enabled: true,
            description: nil
        ), base: snapshot, success: L10n.message("Privacy rule added."))
    }

    @discardableResult
    func saveRule(_ input: AiPrivacyRuleInput) async -> Bool {
        guard let snapshot else { return false }
        let success = input.ruleId == nil
            ? L10n.message("Privacy rule added.")
            : L10n.message("Privacy rule saved.")
        return await saveRule(input, base: snapshot, success: success)
    }

    @discardableResult
    func addRules(_ inputs: [AiPrivacyRuleInput]) async -> Bool {
        guard let snapshot, !inputs.isEmpty else { return false }
        return await save(
            snapshot,
            gate: snapshot.privacyGateEnabled,
            rules: snapshot.ruleInputs + inputs,
            success: L10n.message("Recommended privacy rules added.")
        )
    }

    @discardableResult
    func deleteRule(_ record: AiPrivacyRuleRecord) async -> Bool {
        guard let snapshot else { return false }
        let rules = snapshot.rules.filter { $0.ruleId != record.ruleId }
            .map(AiPrivacyRuleInput.init(aiPrivacyRulesRecord:))
        return await save(
            snapshot,
            gate: snapshot.privacyGateEnabled,
            rules: rules,
            success: L10n.message("Privacy rule deleted.")
        )
    }

    @discardableResult
    func retrySave() async -> Bool {
        guard let pendingSaveRequest else { return false }
        return await persist(
            request: pendingSaveRequest,
            success: pendingSaveSuccess,
            failureMessage: pendingSaveFailureMessage,
            pendingSnapshotOnFailure: pendingSnapshotOnFailure
        )
    }

    func revertPendingSave() {
        snapshot = savedSnapshot
        saveError = nil
        feedback = nil
        clearPendingSave()
    }

    func evaluate(context: AIPrivacyRuleTestFileContext) async {
        guard let snapshot, !isEvaluating else { return }
        guard !context.isEmpty else { return }
        isEvaluating = true
        defer { isEvaluating = false }
        do {
            var evaluations: [AIPrivacyRuleFeatureEvaluation] = []
            for request in snapshot.aiPrivacyRulesEvaluationRequests(context: context) {
                let report = try await evaluator.evaluateAIPrivacy(repoPath: repoPath, request: request)
                evaluations.append(AIPrivacyRuleFeatureEvaluation(feature: request.feature, report: report))
            }
            featureEvaluations = evaluations
            evaluation = featureEvaluations.first { $0.feature == .autoSummaries }?.report
                ?? featureEvaluations.first?.report
            saveError = nil
        } catch {
            saveError = await privacyError(
                for: error,
                message: L10n.message("AI privacy rules could not be tested.")
            )
        }
    }

    func evaluate(repoRelativePath: String) async {
        await evaluate(context: AIPrivacyRuleTestFileContext(
            repoRelativePath: repoRelativePath,
            category: nil,
            tags: []
        ))
    }

    private func save(
        _ base: AiPrivacyRulesSnapshot,
        gate: Bool,
        rules: [AiPrivacyRuleInput],
        fields: [AiPrivacyFieldRule]? = nil,
        success: LocalizedMessage = L10n.message("Remote allowed fields saved."),
        failureMessage: LocalizedMessage = L10n.message("AI privacy rules could not be saved."),
        pendingSnapshotOnFailure: AiPrivacyRulesSnapshot? = nil
    ) async -> Bool {
        await persist(
            request: AiPrivacyRulesUpdateRequest(
                privacyGateEnabled: gate,
                rules: rules,
                remoteAllowedFields: fields ?? base.fieldRules,
                providerScope: base.providerScope,
                confirmed: true
            ),
            success: success,
            failureMessage: failureMessage,
            pendingSnapshotOnFailure: pendingSnapshotOnFailure
        )
    }

    private func saveRule(
        _ input: AiPrivacyRuleInput,
        base: AiPrivacyRulesSnapshot,
        success: LocalizedMessage
    ) async -> Bool {
        var rules = base.ruleInputs
        if let ruleID = input.ruleId, let index = rules.firstIndex(where: { $0.ruleId == ruleID }) {
            rules[index] = input
        } else {
            rules.append(input)
        }
        return await save(base, gate: base.privacyGateEnabled, rules: rules, success: success)
    }

    private func persist(
        request: AiPrivacyRulesUpdateRequest,
        success: LocalizedMessage,
        failureMessage: LocalizedMessage,
        pendingSnapshotOnFailure: AiPrivacyRulesSnapshot?
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            snapshot = try await rulesManager.updateAIPrivacyRules(
                repoPath: repoPath,
                request: request
            )
            if let syncError = await settingsSync?.syncPrivacyGateFromPrivacyRules(request.privacyGateEnabled) {
                throw AIPrivacyRulesSettingsSyncError.syncFailed(syncError)
            }
            savedSnapshot = snapshot
            saveError = nil
            feedback = success
            clearPendingSave()
            return true
        } catch {
            if let pendingSnapshotOnFailure {
                snapshot = pendingSnapshotOnFailure
            } else {
                snapshot = savedSnapshot ?? snapshot
            }
            pendingSaveRequest = request
            pendingSaveSuccess = success
            pendingSaveFailureMessage = failureMessage
            self.pendingSnapshotOnFailure = pendingSnapshotOnFailure
            saveError = await privacyError(for: error, message: failureMessage)
            return false
        }
    }

    private func clearPendingSave() {
        pendingSaveRequest = nil
        pendingSaveSuccess = L10n.message("Remote allowed fields saved.")
        pendingSaveFailureMessage = L10n.message("AI privacy rules could not be saved.")
        pendingSnapshotOnFailure = nil
    }

    private func privacyError(for error: Error, message: LocalizedMessage) async -> AISettingsError {
        if let syncError = error as? AIPrivacyRulesSettingsSyncError {
            return syncError.error
        }
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: message,
                recovery: mapping.suggestedActionDescriptor,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: L10n.message("Retry"), detail: error.localizedDescription)
    }

    private func gateSuccess(_ enabled: Bool) -> LocalizedMessage {
        enabled
            ? L10n.message("Remote AI privacy gate allowed.")
            : L10n.message("Remote AI blocked by privacy gate.")
    }
}

private enum AIPrivacyRulesSettingsSyncError: Error {
    case syncFailed(AISettingsError)

    var error: AISettingsError {
        switch self {
        case let .syncFailed(error):
            error
        }
    }
}
