import Combine
import Foundation

@MainActor
// swiftlint:disable:next type_body_length
final class AISummaryEditorModel: ObservableObject {
    @Published private var contentState = AISummaryEditorContentState()
    @Published private(set) var operation: AISummaryEditorOperation = .idle
    @Published private(set) var failedAction: AISummaryEditorFailedAction?
    @Published private(set) var gateState: AISummaryEditorGateState = .unknown

    let repoPath: String
    private(set) var fileID: Int64
    private let summaryStore: any CoreAISummaryManaging
    private let privacyRules: any CoreAIPrivacyEvaluating
    private let errorMapper: any CoreErrorMapping
    private let summaryProviderScope: AiSummaryProviderScope
    private var privacyContext: AISummaryPrivacyContext
    private var generationToken = UUID()
    private var entryLoadToken = UUID()
    private var generationSnapshot: AISummaryEditorSnapshot?
    private(set) var privacySkip: AISummaryPrivacySkip?

    init(
        repoPath: String,
        fileID: Int64,
        summaryStore: any CoreAISummaryManaging = AppCoreServices.aiSummaryStore,
        privacyRules: any CoreAIPrivacyEvaluating = AppCoreServices.aiPrivacyRules,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
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

    var characterCountText: String {
        contentState.characterCountText
    }

    var status: AISummaryEditorStatus {
        contentState.status
    }

    var provenance: AISummaryProvenance? {
        contentState.provenance
    }

    var draftText: String {
        contentState.draftText
    }

    var canGenerate: Bool {
        canEdit && gateState.allowsGeneration
    }

    var canCancelGeneration: Bool {
        operation == .generating
    }

    var canRegenerate: Bool {
        canGenerate && contentState.hasSummaryContent
    }

    var canDiscard: Bool {
        canEdit && contentState.canDiscard
    }

    var canClear: Bool {
        canEdit && privacySkip == nil && contentState.hasSummaryContent
    }

    var canSave: Bool {
        canEdit && contentState.canSave
    }

    var needsExitConfirmation: Bool {
        contentState.needsExitConfirmation
    }

    private var canEdit: Bool {
        !operation.isBusy
    }

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
            operation = await .failed(
                summaryError(for: error, message: L10n.string("Summary could not be loaded."))
            )
            return
        }
        _ = await refreshGenerationGate()
        guard token == entryLoadToken else { return }
        operation = .idle
    }

    func reset(fileID: Int64) {
        guard self.fileID != fileID else { return }
        self.fileID = fileID
        contentState.reset()
        privacySkip = nil
        gateState = .unknown
        failedAction = nil
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
        guard contentState.draftText != text else { return }
        contentState.updateDraft(text)
        privacySkip = nil
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
            operation = await .failed(
                summaryError(for: error, message: L10n.string("Summary could not be generated."))
            )
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
            contentState.acceptSaveReport(report)
            operation = .idle
            return true
        } catch {
            failedAction = .save
            operation = await .failed(
                summaryError(for: error, message: L10n.string("Summary could not be saved."))
            )
            return false
        }
    }

    func discardChanges() {
        guard canDiscard else { return }
        contentState.discardChanges()
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
            contentState.clear()
            privacySkip = nil
            operation = .idle
        } catch {
            failedAction = .clear
            operation = await .failed(
                summaryError(for: error, message: L10n.string("Summary could not be cleared."))
            )
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
            let mapping = await summaryError(
                for: error,
                message: L10n.string("AI privacy rules could not be checked.")
            )
            gateState = .failed(mapping)
            return AISummaryEditorPresentationSupport.privacyUnavailableNotice(mapping)
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
        return AISummaryEditorPresentationSupport.privacyBlockedNotice(skip)
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
            operation = await .failed(
                summaryError(for: error, message: L10n.string("Summary could not be generated."))
            )
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
        contentState.apply(draft)
        switch draft.status {
        case .draft:
            break
        case .skipped:
            updateGateState(for: draft.skippedReason)
        case .unavailable:
            updateGateState(for: draft.skippedReason)
        }
    }

    private func apply(_ skip: AISummaryPrivacySkip, draft: AiSummaryDraft) {
        privacySkip = skip
        contentState.apply(skip, draft: draft)
    }

    private func apply(_ saved: AISummarySavedSnapshot?) {
        contentState.apply(saved)
        privacySkip = nil
    }

    private func updateGateState(for reason: AiSummarySkipReason?) {
        guard let reason else { return }
        gateState = .blocked(AISummaryEditorPresentationSupport.notice(for: reason))
    }

    private func saveRequest() -> AiSummarySaveRequest {
        contentState.saveRequest(fileID: fileID)
    }

    private func snapshot() -> AISummaryEditorSnapshot {
        contentState.snapshot
    }

    private func restore(_ snapshot: AISummaryEditorSnapshot) {
        contentState.restore(snapshot)
    }

    private func summaryError(for error: Error, message: String) async -> AISettingsError {
        await AISummaryEditorPresentationSupport.error(
            for: error,
            message: message,
            errorMapper: errorMapper
        )
    }
}
