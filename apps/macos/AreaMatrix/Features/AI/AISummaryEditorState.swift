import Combine
import Foundation

@MainActor
final class AISummaryEditorModel: ObservableObject {
    @Published private(set) var contentState = AISummaryEditorContentState()
    @Published var operation: AISummaryEditorOperation = .idle
    @Published var failedAction: AISummaryEditorFailedAction?
    @Published private(set) var gateState: AISummaryEditorGateState = .unknown
    @Published private(set) var replacementReview: AISummaryReplacementReview?
    @Published private(set) var saveConflictReview: AISummarySaveConflictReview?
    @Published var clearConflictNotice: AISummaryClearConflictNotice?

    let repoPath: String
    private(set) var fileID: Int64
    let summaryStore: any CoreAISummaryManaging
    private let contentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting
    private let privacyRules: any CoreAIPrivacyEvaluating
    let errorMapper: any CoreErrorMapping
    private let summaryProviderScope: AISummaryProviderScopeState
    private var privacyContext: AISummaryPrivacyContext
    private var generationToken = UUID()
    private var entryLoadToken = UUID()
    private var generationSnapshot: AISummaryEditorSnapshot?
    var failedGenerationAttempt: AISummaryGenerationAttempt?
    var confirmedReplacement = false
    private(set) var privacySkip: AISummaryPrivacySkip?

    init(
        repoPath: String,
        fileID: Int64,
        summaryStore: any CoreAISummaryManaging,
        contentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting,
        privacyRules: any CoreAIPrivacyEvaluating,
        errorMapper: any CoreErrorMapping,
        summaryProviderScope: AISummaryProviderScopeState = .localPreferred,
        privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext()
    ) {
        self.repoPath = repoPath
        self.fileID = fileID
        self.summaryStore = summaryStore
        self.contentLocaleSnapshotter = contentLocaleSnapshotter
        self.privacyRules = privacyRules
        self.errorMapper = errorMapper
        self.summaryProviderScope = summaryProviderScope
        self.privacyContext = privacyContext
    }
}

extension AISummaryEditorModel {
    func loadEntryState() async {
        guard !operation.isBusy else { return }
        let token = UUID()
        entryLoadToken = token
        operation = .loading
        failedAction = nil
        do {
            let saved = try await summaryStore.loadAISummaryState(repoPath: repoPath, fileID: fileID)
            guard token == entryLoadToken else { return }
            apply(saved)
        } catch {
            guard token == entryLoadToken else { return }
            failedAction = .load
            operation = await .failed(
                summaryError(for: error, message: L10n.message("Summary could not be loaded."))
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
        replacementReview = nil
        saveConflictReview = nil
        clearConflictNotice = nil
        confirmedReplacement = false
        failedGenerationAttempt = nil
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

    func generate(regenerate: Bool, retryOfOperationID: String? = nil) async {
        guard canEdit else { return }
        guard let contentLocale = await generationContentLocale() else { return }
        let preGateSnapshot = snapshot()
        let attempt = AISummaryGenerationAttempt(
            operationID: UUID().uuidString.lowercased(),
            retryOfOperationID: retryOfOperationID,
            regenerate: regenerate
        )
        if let blocked = await refreshGenerationGate() {
            await handleBlockedGenerate(
                blocked,
                snapshot: preGateSnapshot,
                contentLocale: contentLocale,
                attempt: attempt
            )
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
                request: generationRequestFactory.makeGenerationRequest(
                    regenerate,
                    contentLocale: contentLocale,
                    attempt: attempt
                )
            )
            guard token == generationToken else { return }
            operation = .idle
            failedGenerationAttempt = nil
            apply(draft)
        } catch {
            guard token == generationToken else { return }
            failedGenerationAttempt = attempt
            failedAction = .generate
            operation = await .failed(
                summaryError(for: error, message: L10n.message("Summary could not be generated."))
            )
        }
    }

    private func generationContentLocale() async -> String? {
        do {
            return try await contentLocaleSnapshotter.repositoryContentLocaleSnapshot(repoPath: repoPath)
        } catch {
            failedAction = .generate
            operation = await .failed(
                summaryError(for: error, message: L10n.message("Summary could not be generated."))
            )
            return nil
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
        if !confirmedReplacement,
           let review = contentState.currentDraftReplacementReview() {
            replacementReview = review
            return false
        }
        guard canSave, let request = saveRequest() else { return false }
        operation = .saving
        failedAction = nil
        do {
            let report = try await summaryStore.saveAISummary(repoPath: repoPath, request: request)
            contentState.acceptSaveReport(report)
            replacementReview = nil
            confirmedReplacement = false
            operation = .idle
            return true
        } catch {
            if await applySaveConflictIfPresent(error, request: request) {
                return false
            }
            failedAction = .save
            operation = await .failed(
                summaryError(for: error, message: L10n.message("Summary could not be saved."))
            )
            return false
        }
    }

    func discardChanges() {
        guard canDiscard else { return }
        contentState.discardChanges()
        replacementReview = nil
        confirmedReplacement = false
        privacySkip = nil
        failedAction = nil
        operation = .idle
    }

    @discardableResult
    func replaceReviewedSummary() async -> Bool {
        guard let review = replacementReview else { return false }
        if review.source == .generatedCandidate {
            contentState.applyReplacementCandidate(review)
        }
        replacementReview = nil
        confirmedReplacement = true
        return await save()
    }

    func keepExistingSummary() {
        guard let review = replacementReview else { return }
        if review.source == .currentDraft {
            contentState.discardChanges()
        }
        replacementReview = nil
        confirmedReplacement = false
    }

    func continueEditingReplacement() {
        guard let review = replacementReview else { return }
        if review.source == .generatedCandidate {
            contentState.applyReplacementCandidate(review)
        }
        replacementReview = nil
        confirmedReplacement = false
    }

    func clear() async {
        guard canClear else { return }
        operation = .clearing
        failedAction = nil
        do {
            let report = try await summaryStore.clearAISummary(
                repoPath: repoPath,
                request: AISummaryClearRequestSnapshot(
                    fileID: fileID,
                    expectedContentRevision: contentState.expectedContentRevision,
                    confirmed: true
                )
            )
            contentState.clear(report)
            clearConflictNotice = nil
            privacySkip = nil
            operation = .idle
        } catch {
            if await applyClearConflictIfPresent(error) {
                return
            }
            failedAction = .clear
            operation = await .failed(
                summaryError(for: error, message: L10n.message("Summary could not be cleared."))
            )
        }
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
                message: L10n.message("AI privacy rules could not be checked.")
            )
            gateState = .failed(mapping)
            return AISummaryEditorPresentationSupport.privacyUnavailableNotice(mapping)
        }
    }

    private func privacyGateBlock() async throws -> AISummaryEditorNotice? {
        let snapshot = try await privacyRules.loadAIPrivacyRules(repoPath: repoPath)
        let report = try await privacyRules.evaluateAIPrivacy(
            repoPath: repoPath,
            request: generationRequestFactory.makePrivacyEvaluationRequest(snapshot: snapshot)
        )
        guard report.decision != .allowed else { return nil }
        let skip = AISummaryPrivacySkip(report: report)
        return AISummaryEditorPresentationSupport.privacyBlockedNotice(skip)
    }

    private func handleBlockedGenerate(
        _ block: AISummaryEditorNotice,
        snapshot: AISummaryEditorSnapshot,
        contentLocale: String,
        attempt: AISummaryGenerationAttempt
    ) async {
        restore(snapshot)
        switch block.reason {
        case let .privacyBlocked(skip), let .noEligibleInput(skip):
            await applyPrivacyBlockedGenerate(
                skip,
                contentLocale: contentLocale,
                attempt: attempt
            )
        default:
            failedAction = nil
            operation = .idle
        }
    }

    private func applyPrivacyBlockedGenerate(
        _ skip: AISummaryPrivacySkip,
        contentLocale: String,
        attempt: AISummaryGenerationAttempt
    ) async {
        guard skip.privacyPolicyRefForSummaryLog != nil else {
            apply(skip)
            failedAction = nil
            operation = .idle
            return
        }
        operation = .generating
        failedAction = nil
        do {
            let draft = try await generationRequestFactory.makeLoggedPrivacySkipDraft(
                skip,
                summaryStore: summaryStore,
                repoPath: repoPath,
                contentLocale: contentLocale,
                attempt: attempt
            )
            apply(skip, draft: draft)
            operation = .idle
        } catch {
            failedGenerationAttempt = attempt
            failedAction = .generate
            operation = await .failed(
                summaryError(for: error, message: L10n.message("Summary could not be generated."))
            )
        }
    }

    private var generationRequestFactory: AISummaryGenerationRequestFactory {
        AISummaryGenerationRequestFactory(
            fileID: fileID,
            providerScope: summaryProviderScope,
            privacyContext: privacyContext
        )
    }

    private func apply(_ draft: AISummaryDraftSnapshot) {
        privacySkip = nil
        if let review = contentState.replacementReview(candidate: draft) {
            replacementReview = review
            return
        }
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

    private func apply(_ skip: AISummaryPrivacySkip, draft: AISummaryDraftSnapshot) {
        privacySkip = skip
        contentState.apply(skip, draft: draft)
    }

    private func apply(_ skip: AISummaryPrivacySkip) {
        privacySkip = skip
        contentState.apply(skip)
    }

    func apply(_ state: AISummaryPersistedStateSnapshot) {
        contentState.apply(state)
        privacySkip = nil
    }

    func reloadLatestAfterSaveConflict() {
        guard let review = saveConflictReview else { return }
        apply(review.latestState)
        saveConflictReview = nil
        confirmedReplacement = false
        operation = .idle
    }

    func reviewLatestAfterSaveConflict() {
        guard let review = saveConflictReview else { return }
        contentState.rebaseSavedSummary(review.latestState)
        saveConflictReview = nil
        confirmedReplacement = false
        operation = .idle
    }

    private func applySaveConflictIfPresent(
        _ error: Error,
        request: AISummarySaveRequestSnapshot
    ) async -> Bool {
        guard let conflict = coreRevisionConflict(
            from: error,
            resource: "ai_summary_content_revision"
        ) else {
            return false
        }
        do {
            let latest = try await summaryStore.loadAISummaryState(repoPath: repoPath, fileID: fileID)
            saveConflictReview = AISummarySaveConflictReview(
                observedText: contentState.savedText,
                latestState: latest,
                localText: request.summaryText,
                expectedRevision: conflict.expectedRevision,
                currentRevision: conflict.currentRevision
            )
            confirmedReplacement = false
            failedAction = nil
            operation = .idle
            return true
        } catch {
            return false
        }
    }

    private func updateGateState(for reason: AISummarySkipReasonState?) {
        guard let reason else { return }
        gateState = .blocked(AISummaryEditorPresentationSupport.notice(for: reason))
    }

    private func restore(_ snapshot: AISummaryEditorSnapshot) {
        contentState.restore(snapshot)
    }
}
