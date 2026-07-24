@testable import AreaMatrix
import XCTest

enum AISummaryPrivacySummaryEvent: Equatable {
    case generate(fileID: Int64, regenerate: Bool)
    case generateSkipped(fileID: Int64, regenerate: Bool, privacyPolicyRef: String?)
    case save(fileID: Int64, text: String, edited: Bool)
    case clear(fileID: Int64, confirmed: Bool)
}

actor AISummaryPrivacySummaryBridge: CoreAISummaryManaging {
    private let saveResult: Result<AiSummarySaveReport, Error>?
    private var recordedEvents: [AISummaryPrivacySummaryEvent] = []
    private var generatedContentLocales: [String] = []

    init(saveResult: Result<AiSummarySaveReport, Error>? = nil) {
        self.saveResult = saveResult
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        nil
    }

    func generateAISummary(repoPath _: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        generatedContentLocales.append(request.contentLocale == .zhHans ? "zh-Hans" : "en")
        if let policyRef = request.privacyPolicyRef {
            recordedEvents.append(.generateSkipped(
                fileID: request.fileId,
                regenerate: request.regenerateExisting,
                privacyPolicyRef: policyRef
            ))
            return .aiSummaryPrivacySkippedDraft(request: request, privacyPolicyRef: policyRef)
        }
        recordedEvents.append(.generate(fileID: request.fileId, regenerate: request.regenerateExisting))
        return .aiSummaryPrivacyDraft(request: request)
    }

    func saveAISummary(repoPath _: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        recordedEvents.append(.save(
            fileID: request.fileId,
            text: request.summaryText,
            edited: request.ownership == .userOwned
        ))
        if let saveResult {
            return try saveResult.get()
        }
        return AiSummarySaveReport(
            fileId: request.fileId,
            contentRevision: request.expectedContentRevision + 1,
            ownership: request.ownership,
            savedSummary: request.summaryText,
            savedAt: 1_700_000_100,
            route: request.route,
            modelName: request.modelName,
            generatedAt: request.generatedAt,
            usedContext: request.usedContext,
            privacyRuleId: request.privacyRuleId,
            callLogId: request.callLogId,
            operationId: request.operationId,
            contentLocale: request.contentLocale,
            formatContractVersion: request.formatContractVersion,
            characterCount: Int64(request.summaryText.count)
        )
    }

    func clearAISummary(repoPath _: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport {
        recordedEvents.append(.clear(fileID: request.fileId, confirmed: request.confirmed))
        return AiSummaryClearReport(
            fileId: request.fileId,
            cleared: request.confirmed,
            contentRevision: request.expectedContentRevision + 1,
            clearedAt: 1_700_000_200
        )
    }

    func assertEvents(
        _ expectedEvents: [AISummaryPrivacySummaryEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedEvents, expectedEvents, file: file, line: line)
    }

    func assertNoEvents(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertEvents([], file: file, line: line)
    }

    func assertGeneratedContentLocales(
        _ expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(generatedContentLocales, expected, file: file, line: line)
    }
}

actor AISummaryPrivacyRulesBridge: CoreAIPrivacyEvaluating {
    private let report: AiPrivacyEvaluationReport
    private var recorded: [AiPrivacyEvaluationRequest] = []

    init(report: AiPrivacyEvaluationReport) {
        self.report = report
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        .aiSummaryPrivacyRules()
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
        contentLocaleSnapshotter: StaticRepositoryContentLocaleSnapshotter(),
        privacyRules: privacy,
        errorMapper: RecordingCoreErrorMapper.aiSummaryIntegration(),
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
