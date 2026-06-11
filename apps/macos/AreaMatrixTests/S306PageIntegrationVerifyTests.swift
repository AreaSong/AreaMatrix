@testable import AreaMatrix
import XCTest

final class S306PageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS306EntryLoadAllowsEmptySummaryWithoutHardcodedReadBlocker() async {
        let summary = S306IntegrationSummaryBridge(drafts: [])
        let model = s306IntegrationModel(fileID: 705, summary: summary)

        await model.loadEntryState()

        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.gateState, .allowed)
        XCTAssertTrue(model.canGenerate)
        XCTAssertFalse(model.canRegenerate)
        let events = await summary.events()
        XCTAssertEqual(events, [.load])
    }

    @MainActor
    func testS306EntryLoadShowsSavedSummaryWithMetadataAndNoUnsavedExitPrompt() async {
        let summary = S306IntegrationSummaryBridge(
            drafts: [],
            savedSummary: .s306SavedSummary(fileID: 708, text: "Previously saved AI summary.")
        )
        let model = s306IntegrationModel(fileID: 708, summary: summary)

        await model.loadEntryState()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Previously saved AI summary.")
        XCTAssertEqual(model.provenance?.route, .remote)
        XCTAssertEqual(model.provenance?.modelName, "Remote summary provider")
        XCTAssertEqual(model.provenance?.callLogID, 8708)
        XCTAssertFalse(model.needsExitConfirmation)
        XCTAssertTrue(model.canRegenerate)
        XCTAssertTrue(model.canClear)
        XCTAssertFalse(model.canSave)
        let events = await summary.events()
        XCTAssertEqual(events, [.load])
    }

    @MainActor
    func testS306SummaryPrivacyAndProvenanceStayOnDeclaredCoreBridgePath() async {
        let privacy = S306IntegrationPrivacyBridge()
        let summary = S306IntegrationSummaryBridge(drafts: [
            .s306IntegrationDraft(fileID: 706, text: "Initial AI summary.", draftID: "draft-a", callLogID: 1706),
            .s306IntegrationDraft(fileID: 706, text: "Regenerated AI summary.", draftID: "draft-b", callLogID: 2706)
        ])
        let model = s306IntegrationModel(fileID: 706, summary: summary, privacy: privacy)

        await model.generate(regenerate: false)
        await model.save()
        model.updateDraft("Unsaved local edit.")
        await model.generate(regenerate: true)
        model.discardChanges()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Initial AI summary.")
        XCTAssertEqual(model.provenance?.callLogID, 1706)

        await model.clear()

        let routes = await privacy.routes()
        let events = await summary.events()
        XCTAssertEqual(routes, [.remote, .remote])
        XCTAssertEqual(events, [
            .generate(regenerate: false, privacyPolicyRef: nil),
            .save(text: "Initial AI summary.", edited: false, callLogID: 1706),
            .generate(regenerate: true, privacyPolicyRef: nil),
            .clear(confirmed: true)
        ])
        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.draftText, "")
        XCTAssertNil(model.provenance)
    }

    @MainActor
    func testS306PrivacyGateFailurePreservesDraftAndRecordsSkippedSummaryTrace() async {
        let summary = S306IntegrationSummaryBridge(drafts: [
            .s306IntegrationDraft(fileID: 712, text: "Initial AI summary.", draftID: "draft-a", callLogID: 1712),
            .s306IntegrationPrivacySkippedDraft(
                fileID: 712,
                privacyRuleID: "block:rule-confidential",
                callLogID: 9712
            )
        ])
        let model = s306IntegrationModel(fileID: 712, summary: summary)
        await model.generate(regenerate: false)
        model.updateDraft("Keep this draft.")

        let blocked = s306IntegrationModel(
            fileID: 712,
            summary: summary,
            privacy: S306IntegrationPrivacyBridge(report: .s306DeniedPrivacyRule())
        )
        blocked.updateDraft("Keep this draft.")
        await blocked.generate(regenerate: true)

        guard case let .blocked(notice) = blocked.gateState else {
            return XCTFail("Expected privacy gate to block regenerate.")
        }
        XCTAssertEqual(notice.capability, "C3-09")
        XCTAssertEqual(blocked.draftText, "Keep this draft.")
        XCTAssertEqual(blocked.status, .skipped(.privacyRule))
        XCTAssertEqual(blocked.privacySkip?.sentFields, [])
        XCTAssertEqual(blocked.provenance?.callLogID, 9712)
        let events = await summary.events()
        XCTAssertEqual(events, [
            .generate(regenerate: false, privacyPolicyRef: nil),
            .generate(regenerate: true, privacyPolicyRef: "block:rule-confidential")
        ])
    }

    @MainActor
    func testS306SummaryUnavailableFromCoreShowsC306GateWithoutExtraCoreBridgeDependencies() async {
        let summary = S306IntegrationSummaryBridge(drafts: [
            .s306IntegrationUnavailableDraft(fileID: 713, reason: .callLogUnavailable)
        ])
        let model = s306IntegrationModel(fileID: 713, summary: summary)

        await model.generate(regenerate: false)

        guard case let .blocked(notice) = model.gateState else {
            return XCTFail("Expected C3-06 unavailable draft to block the page action.")
        }
        XCTAssertEqual(notice.title, "AI call log is unavailable")
        XCTAssertEqual(notice.reason, .callLogUnavailable)
        XCTAssertEqual(model.draftText, "")
        let events = await summary.events()
        XCTAssertEqual(events, [.generate(regenerate: false, privacyPolicyRef: nil)])
    }

    @MainActor
    func testS306ExitConfirmationSavesDiscardsOrKeepsDraftUntilUserChooses() async {
        let summary = S306IntegrationSummaryBridge(drafts: [
            .s306IntegrationDraft(fileID: 707, text: "Saved AI summary.", draftID: "draft-exit", callLogID: 1707)
        ])
        let model = s306IntegrationModel(fileID: 707, summary: summary)
        let exitController = AISummaryEditorExitController()

        await model.generate(regenerate: false)
        await model.save()
        model.updateDraft("Dirty exit draft.")
        exitController.update(needsConfirmation: model.needsExitConfirmation) {
            await model.save()
        } discardHandler: {
            model.discardChanges()
        }

        XCTAssertTrue(exitController.needsConfirmation)
        XCTAssertEqual(model.status, .dirty)
        let eventsBeforeSave = await summary.events()
        XCTAssertEqual(eventsBeforeSave, [
            .generate(regenerate: false, privacyPolicyRef: nil),
            .save(text: "Saved AI summary.", edited: false, callLogID: 1707)
        ])

        let saveResult = await exitController.saveChanges()
        XCTAssertTrue(saveResult)
        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Dirty exit draft.")

        model.updateDraft("Discard this draft.")
        exitController.update(needsConfirmation: model.needsExitConfirmation) {
            await model.save()
        } discardHandler: {
            model.discardChanges()
        }
        exitController.discardChanges()

        XCTAssertFalse(exitController.needsConfirmation)
        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Dirty exit draft.")
        let eventsAfterDiscard = await summary.events()
        XCTAssertEqual(eventsAfterDiscard, [
            .generate(regenerate: false, privacyPolicyRef: nil),
            .save(text: "Saved AI summary.", edited: false, callLogID: 1707),
            .save(text: "Dirty exit draft.", edited: true, callLogID: 1707)
        ])
    }

    func testS306DirtySelectionChangeRestoresPreviousFileUntilUserChooses() {
        let request = AISummarySelectionExitRequest(previousIDs: [707], requestedIDs: [708])
        var cancelState = AISummarySelectionExitState()

        XCTAssertEqual(
            cancelState.handleChange(previousIDs: [707], requestedIDs: [708], needsConfirmation: true),
            .restore([707])
        )
        XCTAssertEqual(cancelState.pendingRequest, request)
        XCTAssertEqual(
            cancelState.handleChange(previousIDs: [708], requestedIDs: [707], needsConfirmation: true),
            .ignoreRestoredSelection
        )
        XCTAssertEqual(cancelState.cancelPending(), [707])
        cancelState.cancelRestoreFlag()
        XCTAssertNil(cancelState.pendingRequest)

        var applyState = AISummarySelectionExitState()
        _ = applyState.handleChange(previousIDs: [707], requestedIDs: [708], needsConfirmation: true)
        _ = applyState.handleChange(previousIDs: [708], requestedIDs: [707], needsConfirmation: true)
        XCTAssertEqual(applyState.takePendingForApply(), request)
        XCTAssertEqual(
            applyState.handleChange(previousIDs: [707], requestedIDs: [708], needsConfirmation: true),
            .apply(previousIDs: [707], requestedIDs: [708])
        )
        XCTAssertNil(applyState.pendingRequest)
    }
}

@MainActor
private func s306IntegrationModel(
    fileID: Int64,
    summary: S306IntegrationSummaryBridge = S306IntegrationSummaryBridge(drafts: []),
    privacy: S306IntegrationPrivacyBridge = S306IntegrationPrivacyBridge()
) -> AISummaryEditorModel {
    AISummaryEditorModel(
        repoPath: "/tmp/repo",
        fileID: fileID,
        summaryStore: summary,
        privacyRules: privacy,
        errorMapper: S306IntegrationErrorMapper(),
        summaryProviderScope: .remoteAllowed,
        privacyContext: AISummaryPrivacyContext(
            repoRelativePath: "docs/summary.pdf",
            fileName: "summary.pdf",
            category: "docs",
            fileExtension: "pdf",
            tags: ["client"]
        )
    )
}

private enum S306IntegrationSummaryEvent: Equatable {
    case load
    case generate(regenerate: Bool, privacyPolicyRef: String?)
    case save(text: String, edited: Bool, callLogID: Int64?)
    case clear(confirmed: Bool)
}

private actor S306IntegrationSummaryBridge: CoreAISummaryManaging {
    private var drafts: [AiSummaryDraft]
    private let savedSummary: AISummarySavedSnapshot?
    private var recorded: [S306IntegrationSummaryEvent] = []

    init(drafts: [AiSummaryDraft], savedSummary: AISummarySavedSnapshot? = nil) {
        self.drafts = drafts
        self.savedSummary = savedSummary
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        recorded.append(.load)
        return savedSummary
    }

    func generateAISummary(repoPath _: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        recorded.append(.generate(
            regenerate: request.regenerateExisting,
            privacyPolicyRef: request.privacyPolicyRef
        ))
        guard !drafts.isEmpty else { throw CoreError.Internal(message: "missing S3-06 draft") }
        return drafts.removeFirst()
    }

    func saveAISummary(repoPath _: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        recorded.append(.save(text: request.summaryText, edited: request.editedByUser, callLogID: request.callLogId))
        return AiSummarySaveReport(
            fileId: request.fileId,
            savedSummary: request.summaryText,
            savedAt: 1_700_000_100,
            route: request.route,
            modelName: request.modelName,
            generatedAt: request.generatedAt,
            usedContext: request.usedContext,
            privacyRuleId: request.privacyRuleId,
            callLogId: request.callLogId,
            editedByUser: request.editedByUser,
            characterCount: Int64(request.summaryText.count)
        )
    }

    func clearAISummary(repoPath _: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport {
        recorded.append(.clear(confirmed: request.confirmed))
        return AiSummaryClearReport(fileId: request.fileId, cleared: true, clearedAt: 1_700_000_200)
    }

    func events() -> [S306IntegrationSummaryEvent] {
        recorded
    }
}

private actor S306IntegrationPrivacyBridge: CoreAIPrivacyEvaluating {
    private let report: AiPrivacyEvaluationReport
    private var recordedRoutes: [AiPrivacyEvaluationRoute] = []

    init(report: AiPrivacyEvaluationReport = .s306Allowed()) {
        self.report = report
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: true,
            rules: [],
            remoteAllowedFields: [],
            providerScope: AiPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: true,
                featureScope: [.autoSummaries]
            ),
            updatedAt: nil,
            remoteBlockedByDefault: true
        )
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        recordedRoutes.append(request.route)
        return report
    }

    func routes() -> [AiPrivacyEvaluationRoute] {
        recordedRoutes
    }
}

private struct S306IntegrationErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "\(error)",
            severity: .medium,
            suggestedAction: "Retry summary action.",
            recoverability: .retryable,
            rawContext: "S3-06 page integration"
        )
    }
}

private extension AISummarySavedSnapshot {
    static func s306SavedSummary(fileID: Int64, text: String) -> AISummarySavedSnapshot {
        AISummarySavedSnapshot(
            fileID: fileID,
            summaryText: text,
            savedAt: 1_700_000_300,
            draftID: "saved-draft-\(fileID)",
            route: .remote,
            modelName: "Remote summary provider",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            privacyRuleID: nil,
            callLogID: 8000 + fileID,
            editedByUser: false,
            characterCount: Int64(text.count)
        )
    }
}

private extension AiPrivacyEvaluationReport {
    static func s306Allowed() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            blockedFields: [],
            sentFields: [.fileName, .repoRelativePath],
            message: "Remote summary metadata allowed."
        )
    }

    static func s306DeniedPrivacyRule() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AiPrivacyRuleMatch(
                    ruleId: "rule-confidential",
                    name: "Confidential",
                    kind: .keyword,
                    pattern: "confidential",
                    appliesTo: .remoteAi,
                    matchedField: .fileName
                )
            ],
            matchedFieldType: .fileName,
            allowedFields: [],
            blockedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            sentFields: [],
            message: "A privacy rule blocked the summary input."
        )
    }
}

private extension AiSummaryDraft {
    static func s306IntegrationDraft(
        fileID: Int64,
        text: String,
        draftID: String,
        callLogID: Int64
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            fileId: fileID,
            draftId: draftID,
            status: .draft,
            summaryText: text,
            route: .remote,
            modelName: "Remote summary provider",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            skippedReason: nil,
            privacyRuleId: nil,
            callLogId: callLogID,
            requiresUserSave: true,
            characterCount: Int64(text.count)
        )
    }

    static func s306IntegrationUnavailableDraft(
        fileID: Int64,
        reason: AiSummarySkipReason
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            fileId: fileID,
            draftId: nil,
            status: .unavailable,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: reason,
            privacyRuleId: nil,
            callLogId: nil,
            requiresUserSave: false,
            characterCount: 0
        )
    }

    static func s306IntegrationPrivacySkippedDraft(
        fileID: Int64,
        privacyRuleID: String,
        callLogID: Int64
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            fileId: fileID,
            draftId: nil,
            status: .skipped,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: .privacyRule,
            privacyRuleId: privacyRuleID,
            callLogId: callLogID,
            requiresUserSave: false,
            characterCount: 0
        )
    }
}
