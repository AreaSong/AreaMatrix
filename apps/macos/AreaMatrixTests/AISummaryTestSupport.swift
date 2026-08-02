@testable import AreaMatrix
import XCTest

enum AISummaryPrivacySummaryEvent: Equatable {
    case generate(fileID: Int64, regenerate: Bool)
    case generateSkipped(fileID: Int64, regenerate: Bool, privacyPolicyRef: String?)
    case save(fileID: Int64, text: String, edited: Bool)
    case clear(fileID: Int64, confirmed: Bool)
}

actor AISummaryPrivacySummaryBridge: CoreAISummaryManaging {
    private let saveResult: Result<AISummarySaveReportSnapshot, Error>?
    private var recordedEvents: [AISummaryPrivacySummaryEvent] = []
    private var generatedContentLocales: [String] = []

    init(saveResult: Result<AISummarySaveReportSnapshot, Error>? = nil) {
        self.saveResult = saveResult
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        nil
    }

    func generateAISummary(repoPath _: String,
                           request: AISummaryGenerationRequestSnapshot) async throws -> AISummaryDraftSnapshot {
        generatedContentLocales.append(request.contentLocale == .zhHans ? "zh-Hans" : "en")
        if let policyRef = request.privacyPolicyRef {
            recordedEvents.append(.generateSkipped(
                fileID: request.fileID,
                regenerate: request.regenerateExisting,
                privacyPolicyRef: policyRef
            ))
            return .aiSummaryPrivacySkippedDraft(request: request, privacyPolicyRef: policyRef)
        }
        recordedEvents.append(.generate(fileID: request.fileID, regenerate: request.regenerateExisting))
        return .aiSummaryPrivacyDraft(request: request)
    }

    func saveAISummary(repoPath _: String,
                       request: AISummarySaveRequestSnapshot) async throws -> AISummarySaveReportSnapshot {
        recordedEvents.append(.save(
            fileID: request.fileID,
            text: request.summaryText,
            edited: request.ownership == .userOwned
        ))
        if let saveResult {
            return try saveResult.get()
        }
        return AISummarySaveReportSnapshot(
            fileID: request.fileID,
            contentRevision: request.expectedContentRevision + 1,
            ownership: request.ownership,
            savedSummary: request.summaryText,
            savedAt: 1_700_000_100,
            route: request.route,
            modelName: request.modelName,
            generatedAt: request.generatedAt,
            usedContext: request.usedContext,
            privacyRuleID: request.privacyRuleID,
            callLogID: request.callLogID,
            operationID: request.operationID,
            contentLocale: request.contentLocale,
            formatContractVersion: request.formatContractVersion,
            characterCount: Int64(request.summaryText.count)
        )
    }

    func clearAISummary(repoPath _: String,
                        request: AISummaryClearRequestSnapshot) async throws -> AISummaryClearReportSnapshot {
        recordedEvents.append(.clear(fileID: request.fileID, confirmed: request.confirmed))
        return AISummaryClearReportSnapshot(
            fileID: request.fileID,
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
    private let report: AIPrivacyEvaluationReportSnapshot
    private var recorded: [AIPrivacyEvaluationRequestSnapshot] = []

    init(report: AIPrivacyEvaluationReportSnapshot) {
        self.report = report
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AIPrivacyRulesSnapshot {
        .aiSummaryPrivacyRules()
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AIPrivacyEvaluationRequestSnapshot
    ) async throws -> AIPrivacyEvaluationReportSnapshot {
        recorded.append(request)
        return report
    }

    func firstEvaluation() -> AIPrivacyEvaluationRequestSnapshot? {
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
