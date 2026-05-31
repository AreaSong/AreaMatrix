import Combine
import Foundation

@MainActor
final class AISummaryEditorModel: ObservableObject {
    @Published private(set) var status: AISummaryEditorStatus = .empty
    @Published private(set) var operation: AISummaryEditorOperation = .idle
    @Published private(set) var failedAction: AISummaryEditorFailedAction?
    @Published private(set) var provenance: AISummaryProvenance?
    @Published private(set) var gateState: AISummaryEditorGateState = .unknown
    @Published var draftText = ""

    let repoPath: String
    private(set) var fileID: Int64
    private let summaryStore: any CoreAISummaryManaging
    private let privacyRules: any CoreAIPrivacyEvaluating
    private let errorMapper: any CoreErrorMapping
    private let summaryProviderScope: AiSummaryProviderScope
    private var privacyContext: AISummaryPrivacyContext
    private var savedText: String?
    private var savedProvenance: AISummaryProvenance?
    private var baselineText: String?
    private var generationToken = UUID()
    private var entryLoadToken = UUID()
    private var generationSnapshot: AISummaryEditorSnapshot?
    private(set) var privacySkip: AISummaryPrivacySkip?

    init(
        repoPath: String,
        fileID: Int64,
        summaryStore: any CoreAISummaryManaging = CoreBridge(),
        privacyRules: any CoreAIPrivacyEvaluating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        summaryProviderScope: AiSummaryProviderScope = .localPreferred,
        privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext()
    ) {
        self.repoPath = repoPath
        self.fileID = fileID
        self.summaryStore = summaryStore
        self.privacyRules = privacyRules
        self.errorMapper = errorMapper
        self.summaryProviderScope = summaryProviderScope
        self.privacyContext = privacyContext
    }

    var characterCountText: String { "\(draftText.count) characters" }
    var canGenerate: Bool { canEdit && gateState.allowsGeneration }
    var canCancelGeneration: Bool { operation == .generating }
    var canRegenerate: Bool { canGenerate && (!draftText.isEmpty || savedText != nil || provenance != nil) }
    var canDiscard: Bool { canEdit && (status == .dirty || status == .draft) }
    var canClear: Bool {
        canEdit && privacySkip == nil && (!draftText.isEmpty || savedText != nil || provenance != nil)
    }

    var canSave: Bool {
        canEdit && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (status == .dirty || status == .draft)
    }

    var needsExitConfirmation: Bool { status == .dirty || status == .draft }

    private var canEdit: Bool { !operation.isBusy }

    func loadEntryState() async {
        guard !operation.isBusy else { return }
        let token = UUID()
        entryLoadToken = token
        operation = .loading
        failedAction = nil
        do {
            let saved = try await summaryStore.loadSavedAISummary(repoPath: repoPath, fileID: fileID)
            guard token == entryLoadToken else { return }
            apply(saved)
        } catch {
            guard token == entryLoadToken else { return }
            failedAction = .load
            operation = .failed(await summaryError(for: error, message: "Summary could not be loaded."))
            return
        }
        _ = await refreshGenerationGate()
        guard token == entryLoadToken else { return }
        operation = .idle
    }

    func reset(fileID: Int64) {
        guard self.fileID != fileID else { return }
        self.fileID = fileID
        draftText = ""
        savedText = nil
        baselineText = nil
        provenance = nil
        savedProvenance = nil
        privacySkip = nil
        gateState = .unknown
        failedAction = nil
        status = .empty
        operation = .idle
        generationToken = UUID()
        entryLoadToken = UUID()
    }

    func updatePrivacyContext(_ context: AISummaryPrivacyContext) {
        guard privacyContext != context else { return }
        privacyContext = context
        gateState = .unknown
    }

    func updateDraft(_ text: String) {
        guard draftText != text else { return }
        draftText = text
        privacySkip = nil
        if text.isEmpty, savedText == nil, provenance == nil { status = .empty }
        else if text == baselineText, savedText != nil { status = .saved }
        else if text == baselineText { status = .draft }
        else { status = .dirty }
    }

    func generate(regenerate: Bool) async {
        guard canEdit else { return }
        let preGateSnapshot = snapshot()
        if let blocked = await refreshGenerationGate() {
            await handleBlockedGenerate(blocked, snapshot: preGateSnapshot, regenerate: regenerate)
            return
        }

        let token = UUID()
        generationToken = token
        generationSnapshot = snapshot()
        operation = .generating
        failedAction = nil
        do {
            let draft = try await summaryStore.generateAISummary(
                repoPath: repoPath,
                request: generationRequest(regenerate)
            )
            guard token == generationToken else { return }
            operation = .idle
            apply(draft)
        } catch {
            guard token == generationToken else { return }
            failedAction = .generate
            operation = .failed(await summaryError(for: error, message: "Summary could not be generated."))
        }
    }

    func cancelGeneration() {
        guard canCancelGeneration else { return }
        generationToken = UUID()
        if let generationSnapshot { restore(generationSnapshot) }
        failedAction = nil
        operation = .idle
    }

    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        operation = .saving
        failedAction = nil
        do {
            let report = try await summaryStore.saveAISummary(repoPath: repoPath, request: saveRequest())
            let saved = AISummaryProvenance(report: report)
            savedText = report.savedSummary
            draftText = report.savedSummary
            baselineText = report.savedSummary
            savedProvenance = saved
            provenance = saved
            status = .saved
            operation = .idle
            return true
        } catch {
            failedAction = .save
            operation = .failed(await summaryError(for: error, message: "Summary could not be saved."))
            return false
        }
    }

    func discardChanges() {
        guard canDiscard else { return }
        draftText = savedText ?? ""
        baselineText = savedText
        status = savedText == nil ? .empty : .saved
        provenance = savedProvenance
        privacySkip = nil
        failedAction = nil
        operation = .idle
    }

    func clear() async {
        guard canClear else { return }
        operation = .clearing
        failedAction = nil
        do {
            _ = try await summaryStore.clearAISummary(
                repoPath: repoPath,
                request: AiSummaryClearRequest(fileId: fileID, confirmed: true)
            )
            draftText = ""
            savedText = nil
            savedProvenance = nil
            baselineText = nil
            provenance = nil
            privacySkip = nil
            status = .empty
            operation = .idle
        } catch {
            failedAction = .clear
            operation = .failed(await summaryError(for: error, message: "Summary could not be cleared."))
        }
    }

    func cancelFailedAction() {
        guard failedAction != nil else { return }
        failedAction = nil
        operation = .idle
    }

    private func refreshGenerationGate() async -> AISummaryEditorNotice? {
        gateState = .checking
        do {
            let block = try await privacyGateBlock()
            if let block {
                gateState = .blocked(block)
                return block
            }
            privacySkip = nil
            gateState = .allowed
            return nil
        } catch {
            let mapping = await summaryError(for: error, message: "AI privacy rules could not be checked.")
            gateState = .failed(mapping)
            return gateNotice(
                title: "AI privacy rules could not be checked",
                detail: mapping.detail,
                recovery: mapping.recovery,
                reason: .privacyUnavailable,
                opensAISettings: false,
                capability: "C3-09"
            )
        }
    }

    private func privacyGateBlock() async throws -> AISummaryEditorNotice? {
        let snapshot = try await privacyRules.loadAIPrivacyRules(repoPath: repoPath)
        let report = try await privacyRules.evaluateAIPrivacy(
            repoPath: repoPath,
            request: privacyEvaluationRequest(snapshot: snapshot)
        )
        guard report.decision != .allowed else { return nil }
        let skip = AISummaryPrivacySkip(report: report)
        let reason: AISummaryEditorGateReason = skip.reasonLabel == "No eligible summary input" ?
            .noEligibleInput(skip) : .privacyBlocked(skip)
        return gateNotice(
            title: skip.reasonLabel,
            detail: skip.message,
            recovery: "Review privacy rules before generating this summary.",
            reason: reason,
            opensAISettings: false,
            capability: "C3-09",
            privacyRuleID: skip.ruleID
        )
    }

    private func handleBlockedGenerate(
        _ block: AISummaryEditorNotice,
        snapshot: AISummaryEditorSnapshot,
        regenerate: Bool
    ) async {
        restore(snapshot)
        switch block.reason {
        case let .privacyBlocked(skip), let .noEligibleInput(skip):
            await applyPrivacyBlockedGenerate(skip, regenerate: regenerate)
        default:
            failedAction = nil
            operation = .idle
        }
    }

    private func applyPrivacyBlockedGenerate(_ skip: AISummaryPrivacySkip, regenerate: Bool) async {
        operation = .generating
        failedAction = nil
        do {
            let draft = try await loggedPrivacySkipDraft(skip, regenerate: regenerate)
            apply(skip, draft: draft)
            operation = .idle
        } catch {
            failedAction = .generate
            operation = .failed(await summaryError(for: error, message: "Summary could not be generated."))
        }
    }

    private func generationRequest(
        _ regenerate: Bool,
        privacyPolicyRef: String? = nil
    ) -> AiSummaryGenerationRequest {
        AiSummaryGenerationRequest(
            fileId: fileID,
            providerScope: summaryProviderScope,
            contextPolicy: .metadataAndExtractedText,
            privacyPolicyRef: privacyPolicyRef,
            regenerateExisting: regenerate
        )
    }

    private func privacyEvaluationRequest(snapshot: AiPrivacyRulesSnapshot) -> AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
            feature: .autoSummaries,
            route: AiPrivacyEvaluationRoute(summaryProviderScope: summaryProviderScope),
            requestedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            privacyGateEnabled: snapshot.privacyGateEnabled,
            providerScope: snapshot.providerScope,
            rules: snapshot.rules.map(AiPrivacyRuleInput.init(summaryRule:)),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AiPrivacyFieldRule.init(state:)),
            context: privacyEvaluationContext()
        )
    }

    private func privacyEvaluationContext() -> AiPrivacyEvaluationContext {
        var context = privacyContext.coreContext
        context.fileId = fileID
        return context
    }

    private func loggedPrivacySkipDraft(
        _ skip: AISummaryPrivacySkip,
        regenerate: Bool
    ) async throws -> AiSummaryDraft {
        guard let policyRef = skip.privacyPolicyRefForSummaryLog else {
            return skip.unloggedDraft(fileID: fileID)
        }
        return try await summaryStore.generateAISummary(
            repoPath: repoPath,
            request: generationRequest(regenerate, privacyPolicyRef: policyRef)
        )
    }

    private func apply(_ draft: AiSummaryDraft) {
        privacySkip = nil
        provenance = AISummaryProvenance(draft: draft)
        switch draft.status {
        case .draft:
            let text = draft.summaryText ?? ""
            draftText = text
            baselineText = text
            status = .draft
        case .skipped:
            status = .skipped(draft.skippedReason)
            updateGateState(for: draft.skippedReason)
        case .unavailable:
            status = .unavailable(draft.skippedReason)
            updateGateState(for: draft.skippedReason)
        }
    }

    private func apply(_ skip: AISummaryPrivacySkip, draft: AiSummaryDraft) {
        privacySkip = skip
        provenance = AISummaryProvenance(draft: draft)
        status = skip.editorStatus
    }

    private func apply(_ saved: AISummarySavedSnapshot?) {
        guard let saved else {
            draftText = ""
            savedText = nil
            savedProvenance = nil
            baselineText = nil
            provenance = nil
            privacySkip = nil
            status = .empty
            return
        }
        let savedProvenance = AISummaryProvenance(saved: saved)
        draftText = saved.summaryText
        savedText = saved.summaryText
        baselineText = saved.summaryText
        self.savedProvenance = savedProvenance
        provenance = savedProvenance
        privacySkip = nil
        status = .saved
    }

    private func updateGateState(for reason: AiSummarySkipReason?) {
        guard let reason else { return }
        gateState = .blocked(notice(for: reason))
    }

    private func notice(for reason: AiSummarySkipReason) -> AISummaryEditorNotice {
        switch reason {
        case .aiDisabled:
            .aiDisabled()
        case .featureDisabled:
            .featureDisabled(nil)
        case .providerUnavailable:
            .providerUnavailable(nil)
        case .privacyRule:
            gateNotice(
                title: aiSummarySkipReasonLabel(reason),
                detail: "No content was sent because the summary was skipped by privacy rules.",
                recovery: "Review privacy rules before generating this summary.",
                reason: .privacyBlocked(AISummaryPrivacySkip(summaryReason: reason)),
                opensAISettings: false,
                capability: "C3-09"
            )
        case .noEligibleInput:
            gateNotice(
                title: aiSummarySkipReasonLabel(reason),
                detail: "This file has no eligible metadata or extracted text for AI summaries.",
                recovery: "Return to detail or choose a file with readable summary input.",
                reason: .noEligibleInput(AISummaryPrivacySkip(summaryReason: reason)),
                opensAISettings: false,
                capability: "C3-09"
            )
        case .callLogUnavailable:
            gateNotice(
                title: aiSummarySkipReasonLabel(reason),
                detail: "Summary generation cannot proceed because AI call logging is unavailable.",
                recovery: "Retry after repository metadata is writable.",
                reason: .callLogUnavailable,
                opensAISettings: false
            )
        }
    }

    private func saveRequest() -> AiSummarySaveRequest {
        AiSummarySaveRequest(
            fileId: fileID,
            summaryText: draftText,
            draftId: provenance?.draftID,
            route: provenance?.route,
            modelName: provenance?.modelName,
            generatedAt: provenance?.generatedAt,
            usedContext: provenance?.usedContext ?? [],
            privacyRuleId: provenance?.privacyRuleID,
            callLogId: provenance?.callLogID,
            editedByUser: status == .dirty
        )
    }

    private func snapshot() -> AISummaryEditorSnapshot {
        AISummaryEditorSnapshot(
            draftText: draftText,
            savedText: savedText,
            savedProvenance: savedProvenance,
            baselineText: baselineText,
            provenance: provenance,
            status: status
        )
    }

    private func restore(_ snapshot: AISummaryEditorSnapshot) {
        draftText = snapshot.draftText
        savedText = snapshot.savedText
        baselineText = snapshot.baselineText
        savedProvenance = snapshot.savedProvenance
        provenance = snapshot.provenance
        status = snapshot.status
    }

    private func summaryError(for error: Error, message: String) async -> AISettingsError {
        guard let coreError = error as? CoreError else {
            return AISettingsError(
                message: message,
                recovery: "Retry or return to detail.",
                detail: error.localizedDescription
            )
        }
        let mapping = await errorMapper.mapCoreError(coreError)
        return AISettingsError(
            message: message,
            recovery: mapping.suggestedAction.isEmpty ? "Retry or return to detail." : mapping.suggestedAction,
            detail: mapping.userMessage
        )
    }

    private func gateNotice(
        title: String,
        detail: String,
        recovery: String,
        reason: AISummaryEditorGateReason,
        opensAISettings: Bool,
        capability: String = "C3-06",
        privacyRuleID: String? = nil
    ) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: title,
            detail: detail,
            recovery: recovery,
            capability: capability,
            opensAISettings: opensAISettings,
            privacyRuleID: privacyRuleID,
            reason: reason
        )
    }

}
