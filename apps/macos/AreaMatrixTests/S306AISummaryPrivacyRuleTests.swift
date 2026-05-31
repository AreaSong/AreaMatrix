@testable import AreaMatrix
import XCTest

final class S306AISummaryPrivacyRuleTests: XCTestCase {
    @MainActor
    func testS306GenerateCreatesDraftWithoutSavingUntilExplicitSave() async {
        let (model, summary, _) = s306Model(fileID: 606, report: s306Report(nil), scope: .localPreferred)

        await model.generate(regenerate: false)

        XCTAssertEqual(model.status, .draft)
        XCTAssertEqual(model.draftText, "Quarterly invoice with payment status and vendor context.")
        XCTAssertEqual(model.provenance?.route, .local)
        XCTAssertTrue(model.canSave)
        let eventsBeforeSave = await summary.events()
        XCTAssertEqual(eventsBeforeSave, [.generate(fileID: 606, regenerate: false)])

        await model.save()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Quarterly invoice with payment status and vendor context.")
        let eventsAfterSave = await summary.events()
        XCTAssertEqual(eventsAfterSave, [
            .generate(fileID: 606, regenerate: false),
            .save(fileID: 606, text: "Quarterly invoice with payment status and vendor context.", edited: false)
        ])
    }

    @MainActor
    func testS306FailurePreservesDraftAndMapsCoreError() async {
        let mapper = S306SummaryErrorMapper()
        let summary = S306PrivacySummaryBridge(saveResult: .failure(CoreError.Db(message: "summary metadata locked")))
        let model = s306Model(
            fileID: 607, report: s306Report(nil), scope: .localPreferred, summary: summary, mapper: mapper
        ).0

        await model.generate(regenerate: false)
        model.updateDraft("Edited summary")
        await model.save()

        guard case let .failed(error) = model.operation else {
            return XCTFail("Expected save failure to stay visible.")
        }
        let mappedErrors = await mapper.errors()
        XCTAssertEqual(model.draftText, "Edited summary")
        XCTAssertEqual(error.message, "Summary could not be saved.")
        XCTAssertEqual(error.detail, "Summary metadata is unavailable.")
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "summary metadata locked")])
    }

    @MainActor
    func testS306ClearOnlyCallsConfirmedSummaryClear() async {
        let (model, summary, _) = s306Model(fileID: 608, report: s306Report(nil), scope: .localPreferred)

        await model.generate(regenerate: false)
        await model.clear()

        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.draftText, "")
        XCTAssertNil(model.provenance)
        let events = await summary.events()
        XCTAssertEqual(events, [
            .generate(fileID: 608, regenerate: false),
            .clear(fileID: 608, confirmed: true)
        ])
    }

    @MainActor
    func testS306PrivacyEvaluationUsesProviderScopeAndRealFileContext() async {
        let context = AISummaryPrivacyContext(
            repoRelativePath: "finance/confidential-invoice.PDF",
            fileName: "confidential-invoice.PDF",
            category: "finance",
            fileExtension: "PDF",
            tags: ["client-a", " confidential ", ""]
        )
        let (model, summary, privacy) = s306Model(
            fileID: 622,
            report: s306Report(nil, fields: true),
            scope: .remoteAllowed,
            privacyContext: context
        )

        await model.generate(regenerate: false)

        let request = await privacy.firstEvaluation()
        let requestContext = request?.context
        XCTAssertEqual(request?.feature, .autoSummaries)
        XCTAssertEqual(request?.route, .remote)
        let events = await summary.events()
        XCTAssertEqual(events, [.generate(fileID: 622, regenerate: false)])
        XCTAssertEqual(model.status, .draft)
        XCTAssertEqual(requestContext?.fileId, 622)
        XCTAssertEqual(requestContext?.repoRelativePath, "finance/confidential-invoice.PDF")
        XCTAssertEqual(requestContext?.fileName, "confidential-invoice.PDF")
        XCTAssertEqual(requestContext?.category, "finance")
        XCTAssertEqual(requestContext?.extension, "pdf")
        XCTAssertEqual(requestContext?.tags, ["client-a", "confidential"])
    }

    @MainActor
    func testS306PrivacyRulesCreateSkippedSummaryCallLogTrace() async {
        let cases: [(Int64, AiPrivacySkippedReason, String, AISummaryEditorStatus)] = [
            (621, .privacyRule, "block:rule-confidential", .skipped(.privacyRule)),
            (640, .fieldRule, "block:privacy-rule", .skipped(.noEligibleInput))
        ]

        for item in cases {
            let (model, summary, _) = s306Model(fileID: item.0, report: s306Report(item.1), scope: .remoteAllowed)

            await model.generate(regenerate: false)

            let events = await summary.events()
            XCTAssertEqual(events, [
                .generateSkipped(fileID: item.0, regenerate: false, privacyPolicyRef: item.2)
            ])
            XCTAssertEqual(model.status, item.3)
            XCTAssertEqual(model.privacySkip?.sentFields, [])
            XCTAssertEqual(model.provenance?.callLogID, item.0)
        }
    }

    @MainActor
    func testS306PrivacyBlocksWithoutSummaryLogWhenNoCallShouldBeRecorded() async {
        let gate = s306Report(.providerNotVerified, providerGateReason: .providerNotVerified)
        let cases: [(Int64, AiPrivacyEvaluationReport, AISummaryEditorStatus, AiPrivacySkippedReason)] = [
            (630, gate, .unavailable(.providerUnavailable), .providerNotVerified),
            (641, s306Report(.noEligibleInput), .skipped(.noEligibleInput), .noEligibleInput)
        ]

        for item in cases {
            let (model, summary, _) = s306Model(fileID: item.0, report: item.1, scope: .remoteAllowed)

            await model.generate(regenerate: false)

            let events = await summary.events()
            XCTAssertEqual(events, [])
            XCTAssertEqual(model.status, item.2)
            XCTAssertEqual(model.privacySkip?.skippedReason, item.3)
            XCTAssertNil(model.provenance?.callLogID)
        }
    }
}

@MainActor
private func s306Model(
    fileID: Int64,
    report: AiPrivacyEvaluationReport,
    scope: AiSummaryProviderScope,
    privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext(),
    summary: S306PrivacySummaryBridge = S306PrivacySummaryBridge(),
    mapper: (any CoreErrorMapping)? = nil
) -> (AISummaryEditorModel, S306PrivacySummaryBridge, S306PrivacyRulesBridge) {
    let privacy = S306PrivacyRulesBridge(report: report)
    let model = AISummaryEditorModel(
        repoPath: "/tmp/repo",
        fileID: fileID,
        summaryStore: summary,
        privacyRules: privacy,
        errorMapper: mapper ?? CoreBridge(),
        summaryProviderScope: scope,
        privacyContext: privacyContext
    )
    return (model, summary, privacy)
}

private enum S306PrivacySummaryEvent: Equatable {
    case generate(fileID: Int64, regenerate: Bool)
    case generateSkipped(fileID: Int64, regenerate: Bool, privacyPolicyRef: String?)
    case save(fileID: Int64, text: String, edited: Bool)
    case clear(fileID: Int64, confirmed: Bool)
}

private actor S306PrivacySummaryBridge: CoreAISummaryManaging {
    private let saveResult: Result<AiSummarySaveReport, Error>?
    private var recordedEvents: [S306PrivacySummaryEvent] = []

    init(saveResult: Result<AiSummarySaveReport, Error>? = nil) {
        self.saveResult = saveResult
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        nil
    }

    func generateAISummary(repoPath _: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        if let policyRef = request.privacyPolicyRef {
            recordedEvents.append(.generateSkipped(
                fileID: request.fileId,
                regenerate: request.regenerateExisting,
                privacyPolicyRef: policyRef
            ))
            return .s306PrivacySkippedDraft(request: request, privacyPolicyRef: policyRef)
        }
        recordedEvents.append(.generate(fileID: request.fileId, regenerate: request.regenerateExisting))
        return .s306PrivacyDraft(request: request)
    }

    func saveAISummary(repoPath _: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        recordedEvents.append(.save(fileID: request.fileId, text: request.summaryText, edited: request.editedByUser))
        if let saveResult {
            return try saveResult.get()
        }
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
        recordedEvents.append(.clear(fileID: request.fileId, confirmed: request.confirmed))
        return AiSummaryClearReport(fileId: request.fileId, cleared: request.confirmed, clearedAt: 1_700_000_200)
    }

    func events() -> [S306PrivacySummaryEvent] {
        recordedEvents
    }
}

private actor S306PrivacyRulesBridge: CoreAIPrivacyEvaluating {
    private let report: AiPrivacyEvaluationReport
    private var recorded: [AiPrivacyEvaluationRequest] = []

    init(report: AiPrivacyEvaluationReport) {
        self.report = report
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        return .s306PrivacyRules()
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        recorded.append(request)
        return report
    }

    func firstEvaluation() -> AiPrivacyEvaluationRequest? {
        recorded.first
    }
}

private extension AiSummaryDraft {
    static func s306PrivacyDraft(request: AiSummaryGenerationRequest) -> AiSummaryDraft {
        AiSummaryDraft(
            fileId: request.fileId,
            draftId: "draft-s306",
            status: .draft,
            summaryText: "Quarterly invoice with payment status and vendor context.",
            route: .local,
            modelName: "Local classifier v1",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            skippedReason: nil,
            privacyRuleId: nil,
            callLogId: 306,
            requiresUserSave: true,
            characterCount: 58
        )
    }

    static func s306PrivacySkippedDraft(
        request: AiSummaryGenerationRequest,
        privacyPolicyRef: String
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            fileId: request.fileId,
            draftId: nil,
            status: .skipped,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: privacyPolicyRef == "block:privacy-rule" ? .noEligibleInput : .privacyRule,
            privacyRuleId: privacyPolicyRef,
            callLogId: request.fileId,
            requiresUserSave: false,
            characterCount: 0
        )
    }
}

private extension AiPrivacyEvaluationReport {
    static func s306(
        _ reason: AiPrivacySkippedReason?,
        providerGateReason: AiPrivacyProviderGateReason? = nil,
        fields: Bool = false
    ) -> AiPrivacyEvaluationReport {
        let allowed = reason == nil
        let matchedRules = reason == .privacyRule ? [s306RuleMatch()] : []
        let blockedFields: [AiPrivacyInputField] = allowed ? [.extractedTextExcerpt] : [
            .fileName, .repoRelativePath, .extractedTextExcerpt
        ]
        return AiPrivacyEvaluationReport(
            decision: allowed ? .allowed : (reason == .fieldRule ? .denied : .skipped),
            skippedReason: reason,
            providerGateReason: providerGateReason,
            matchedRules: matchedRules,
            matchedFieldType: reason == .privacyRule ? .fileName : (reason == .fieldRule ? .extractedTextExcerpt : nil),
            allowedFields: allowed ? [.fileName, .repoRelativePath] : [],
            blockedFields: blockedFields,
            sentFields: allowed && fields ? [.fileName, .repoRelativePath] : [],
            message: allowed ? "Privacy rules allow remote summary metadata only." : "No fields were sent."
        )
    }

    private static func s306RuleMatch() -> AiPrivacyRuleMatch {
        AiPrivacyRuleMatch(
            ruleId: "rule-confidential",
            name: "Block confidential",
            kind: .keyword,
            pattern: "confidential",
            appliesTo: .remoteAi,
            matchedField: .fileName
        )
    }
}

private func s306Report(
    _ reason: AiPrivacySkippedReason?,
    providerGateReason: AiPrivacyProviderGateReason? = nil,
    fields: Bool = false
) -> AiPrivacyEvaluationReport {
    .s306(reason, providerGateReason: providerGateReason, fields: fields)
}

actor S307AITagBridge: CoreAITagSuggestionManaging {
    private let report: AiTagSuggestionReport
    private var suggestRequests: [AiTagSuggestionRequest] = []
    private var applyRequests: [ApplyAiTagSuggestionsRequest] = []

    init(_ report: AiTagSuggestionReport) {
        self.report = report
    }

    func suggestTagsWithAI(repoPath: String, request: AiTagSuggestionRequest) async throws -> AiTagSuggestionReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return s307ApplyReport(fileID: request.fileId)
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}

func s307AITagReport(
    fileID: Int64,
    status: AiTagSuggestionReportStatus = .suggested,
    skippedReason: AiTagSuggestionSkipReason? = nil,
    suggestions: [AiTagSuggestion] = []
) -> AiTagSuggestionReport {
    AiTagSuggestionReport(
        fileId: fileID,
        status: status,
        suggestions: suggestions,
        route: status == .suggested ? .local : nil,
        modelName: status == .suggested ? "Local tags model" : nil,
        generatedAt: status == .suggested ? 1_700_000_300 : nil,
        usedContext: status == .suggested ? [.fileName, .tagRegistry] : [],
        skippedReason: skippedReason,
        privacyRuleId: skippedReason == .privacyRule ? "rule-confidential" : nil,
        callLogId: 7_707,
        requiresUserConfirmation: true,
        confidenceThreshold: 0.8,
        contentsRead: status == .suggested,
        aiUsed: status == .suggested,
        networkUsed: false
    )
}

func s307AITagSuggestion(
    id: String,
    slug: String,
    confidence: Float,
    selectedByDefault: Bool = true
) -> AiTagSuggestion {
    AiTagSuggestion(
        suggestionId: id,
        slug: slug,
        displayName: slug.prefix(1).uppercased() + slug.dropFirst(),
        confidence: confidence,
        reason: "S3-07 C3-07 local tag suggestion.",
        status: .suggested,
        mergeAction: .createTag,
        matchedExistingSlug: nil,
        selectedByDefault: selectedByDefault,
        disabledReason: nil
    )
}

func s307ApplyReport(fileID: Int64) -> AiTagSuggestionApplyReport {
    let tag = s307Tag("finance")
    return AiTagSuggestionApplyReport(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: 1,
        skippedCount: 0,
        failedCount: 0,
        itemResults: [
            AiTagSuggestionApplyItemResult(
                suggestionId: "s3-07-finance",
                slug: "finance",
                status: .applied,
                error: nil
            )
        ],
        tagSet: TagSet(
            fileId: fileID,
            fileTags: [tag],
            availableTags: [tag],
            recentTags: [tag],
            updatedAt: 1_700_000_350
        ),
        undoToken: nil,
        callLogId: 7_707,
        refreshTargets: ["tags", "change_log", "undo_actions", "ai_call_log"]
    )
}

func s307Tag(_ value: String) -> TagRecord {
    TagRecord(
        value: value,
        label: value.prefix(1).uppercased() + value.dropFirst(),
        fileCount: 1,
        selected: true,
        disabled: false,
        updatedAt: 1_700_000_350
    )
}

private extension AiPrivacyRulesSnapshot {
    static func s306PrivacyRules() -> AiPrivacyRulesSnapshot {
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
            updatedAt: 1_700_000_250,
            remoteBlockedByDefault: true
        )
    }
}

private actor S306SummaryErrorMapper: CoreErrorMapping {
    private var recordedErrors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        recordedErrors.append(error)
        return CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Summary metadata is unavailable.",
            severity: .medium,
            suggestedAction: "Retry save.",
            recoverability: .retryable,
            rawContext: "S3-06 C3-06"
        )
    }

    func errors() -> [CoreError] {
        recordedErrors
    }
}
