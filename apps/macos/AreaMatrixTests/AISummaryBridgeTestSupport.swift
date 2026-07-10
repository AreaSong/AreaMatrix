@testable import AreaMatrix
import XCTest

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

    func assertEvents(
        _ expectedEvents: [AISummaryIntegrationSummaryEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded, expectedEvents, file: file, line: line)
    }

    func assertNoEvents(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertEvents([], file: file, line: line)
    }
}

actor AISummaryIntegrationPrivacyBridge: CoreAIPrivacyEvaluating {
    private let report: AiPrivacyEvaluationReport
    private var recordedRoutes: [AiPrivacyEvaluationRoute] = []

    init(report: AiPrivacyEvaluationReport = .aiSummaryAllowed()) {
        self.report = report
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot.testFixture(
            privacyGateEnabled: true,
            providerScope: .testFixture(
                featureScope: [.autoSummaries]
            )
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

extension RecordingCoreErrorMapper {
    static func aiSummaryIntegration() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: .db,
                userMessage: "\(error)",
                severity: .medium,
                suggestedAction: "Retry summary action.",
                recoverability: .retryable,
                rawContext: "ai-summary page integration"
            )
        }
    }
}
