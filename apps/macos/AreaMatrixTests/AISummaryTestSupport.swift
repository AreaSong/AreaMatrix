@testable import AreaMatrix

@MainActor
func aiSummaryIntegrationModel(
    fileID: Int64,
    summary: AISummaryIntegrationSummaryBridge = AISummaryIntegrationSummaryBridge(drafts: []),
    privacy: AISummaryIntegrationPrivacyBridge = AISummaryIntegrationPrivacyBridge()
) -> AISummaryEditorModel {
    AISummaryEditorModel(
        repoPath: "/tmp/repo",
        fileID: fileID,
        summaryStore: summary,
        privacyRules: privacy,
        errorMapper: AISummaryIntegrationErrorMapper(),
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

enum AISummaryIntegrationSummaryEvent: Equatable {
    case load
    case generate(regenerate: Bool, privacyPolicyRef: String?)
    case save(text: String, edited: Bool, callLogID: Int64?)
    case clear(confirmed: Bool)
}

actor AISummaryIntegrationSummaryBridge: CoreAISummaryManaging {
    private var drafts: [AiSummaryDraft]
    private let savedSummary: AISummarySavedSnapshot?
    private var recorded: [AISummaryIntegrationSummaryEvent] = []

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
        guard !drafts.isEmpty else { throw CoreError.Internal(message: "missing ai-summary draft") }
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

    func events() -> [AISummaryIntegrationSummaryEvent] {
        recorded
    }
}

actor AISummaryIntegrationPrivacyBridge: CoreAIPrivacyEvaluating {
    private let report: AiPrivacyEvaluationReport
    private var recordedRoutes: [AiPrivacyEvaluationRoute] = []

    init(report: AiPrivacyEvaluationReport = .aiSummaryAllowed()) {
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

private struct AISummaryIntegrationErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "\(error)",
            severity: .medium,
            suggestedAction: "Retry summary action.",
            recoverability: .retryable,
            rawContext: "ai-summary page integration"
        )
    }
}

extension AISummarySavedSnapshot {
    static func aiSummarySavedSummary(fileID: Int64, text: String) -> AISummarySavedSnapshot {
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

extension AiPrivacyEvaluationReport {
    static func aiSummaryAllowed() -> AiPrivacyEvaluationReport {
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

    static func aiSummaryDeniedPrivacyRule() -> AiPrivacyEvaluationReport {
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

extension AiSummaryDraft {
    static func aiSummaryIntegrationDraft(
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

    static func aiSummaryIntegrationUnavailableDraft(
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

    static func aiSummaryIntegrationPrivacySkippedDraft(
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
