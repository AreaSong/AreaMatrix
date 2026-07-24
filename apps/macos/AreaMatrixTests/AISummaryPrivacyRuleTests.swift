@testable import AreaMatrix
import XCTest

final class AISummaryAISummaryPrivacyRuleTests: XCTestCase {
    @MainActor
    func testAISummaryGenerateCreatesDraftWithoutSavingUntilExplicitSave() async {
        let (model, summary, _) = aiSummaryModel(fileID: 606, report: aiSummaryReport(nil), scope: .localPreferred)

        await model.generate(regenerate: false)

        XCTAssertEqual(model.status, .draft)
        XCTAssertEqual(model.draftText, "Quarterly invoice with payment status and vendor context.")
        XCTAssertEqual(model.provenance?.route, .local)
        XCTAssertTrue(model.canSave)
        await summary.assertEvents([.generate(fileID: 606, regenerate: false)])

        await model.save()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Quarterly invoice with payment status and vendor context.")
        await summary.assertEvents([
            .generate(fileID: 606, regenerate: false),
            .save(fileID: 606, text: "Quarterly invoice with payment status and vendor context.", edited: false)
        ])
    }

    @MainActor
    func testAISummaryFailurePreservesDraftAndMapsCoreError() async {
        let mapper = StaticCoreErrorMapper(mapping: .aiSummarySaveFailure)
        let summary =
            AISummaryPrivacySummaryBridge(saveResult: .failure(CoreError.Db(message: "summary metadata locked")))
        let model = aiSummaryModel(
            fileID: 607, report: aiSummaryReport(nil), scope: .localPreferred, summary: summary, mapper: mapper
        ).0

        await model.generate(regenerate: false)
        model.updateDraft("Edited summary")
        await model.save()

        guard case let .failed(error) = model.operation else {
            return XCTFail("Expected save failure to stay visible.")
        }
        XCTAssertEqual(model.draftText, "Edited summary")
        XCTAssertEqual(error.message, L10n.message("Summary could not be saved."))
        XCTAssertEqual(error.detail, L10n.string("error.unmapped.message"))
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "summary metadata locked")])
    }

    @MainActor
    func testAISummaryClearOnlyCallsConfirmedSummaryClear() async {
        let (model, summary, _) = aiSummaryModel(fileID: 608, report: aiSummaryReport(nil), scope: .localPreferred)

        await model.generate(regenerate: false)
        await model.clear()

        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.draftText, "")
        XCTAssertNil(model.provenance)
        await summary.assertEvents([
            .generate(fileID: 608, regenerate: false),
            .clear(fileID: 608, confirmed: true)
        ])
    }

    @MainActor
    func testAISummaryPrivacyEvaluationUsesProviderScopeAndRealFileContext() async {
        let context = AISummaryPrivacyContext(
            repoRelativePath: "finance/confidential-invoice.PDF",
            fileName: "confidential-invoice.PDF",
            category: "finance",
            fileExtension: "PDF",
            tags: ["client-a", " confidential ", ""]
        )
        let (model, summary, privacy) = aiSummaryModel(
            fileID: 622,
            report: aiSummaryReport(nil, fields: true),
            scope: .remoteAllowed,
            privacyContext: context
        )

        await model.generate(regenerate: false)

        let request = await privacy.firstEvaluation()
        let requestContext = request?.context
        XCTAssertEqual(request?.feature, .autoSummaries)
        XCTAssertEqual(request?.route, .remote)
        await summary.assertEvents([.generate(fileID: 622, regenerate: false)])
        XCTAssertEqual(model.status, .draft)
        XCTAssertEqual(requestContext?.fileId, 622)
        XCTAssertEqual(requestContext?.repoRelativePath, "finance/confidential-invoice.PDF")
        XCTAssertEqual(requestContext?.fileName, "confidential-invoice.PDF")
        XCTAssertEqual(requestContext?.category, "finance")
        XCTAssertEqual(requestContext?.extension, "pdf")
        XCTAssertEqual(requestContext?.tags, ["client-a", "confidential"])
    }

    @MainActor
    func testAISummaryPrivacyRulesCreateSkippedSummaryCallLogTrace() async {
        // swiftlint:disable:next large_tuple
        let cases: [(Int64, AiPrivacySkippedReason, String, AISummaryEditorStatus)] = [
            (621, .privacyRule, "block:rule-confidential", .skipped(.privacyRule)),
            (640, .fieldRule, "block:privacy-rule", .skipped(.noEligibleInput))
        ]

        for item in cases {
            let (model, summary, _) = aiSummaryModel(
                fileID: item.0,
                report: aiSummaryReport(item.1),
                scope: .remoteAllowed
            )

            await model.generate(regenerate: false)

            await summary.assertEvents([
                .generateSkipped(fileID: item.0, regenerate: false, privacyPolicyRef: item.2)
            ])
            XCTAssertEqual(model.status, item.3)
            XCTAssertEqual(model.privacySkip?.sentFields, [])
            XCTAssertEqual(model.provenance?.callLogID, item.0)
        }
    }

    @MainActor
    func testAISummaryPrivacyBlocksWithoutSummaryLogWhenNoCallShouldBeRecorded() async {
        let gate = aiSummaryReport(.providerNotVerified, providerGateReason: .providerNotVerified)
        // swiftlint:disable:next large_tuple
        let cases: [(Int64, AiPrivacyEvaluationReport, AISummaryEditorStatus, AiPrivacySkippedReason)] = [
            (630, gate, .unavailable(.providerUnavailable), .providerNotVerified),
            (641, aiSummaryReport(.noEligibleInput), .skipped(.noEligibleInput), .noEligibleInput)
        ]

        for item in cases {
            let (model, summary, _) = aiSummaryModel(fileID: item.0, report: item.1, scope: .remoteAllowed)

            await model.generate(regenerate: false)

            await summary.assertNoEvents()
            XCTAssertEqual(model.status, item.2)
            XCTAssertEqual(model.privacySkip?.skippedReason, item.3)
            XCTAssertNil(model.provenance?.callLogID)
        }
    }

    @MainActor
    func testAISummaryFreezesContentLocaleBeforePrivacyGateForGeneratedAndLoggedSkipRequests() async {
        let reports = [aiSummaryReport(nil), aiSummaryReport(.privacyRule)]

        for (index, report) in reports.enumerated() {
            let localeSnapshotter = StaticRepositoryContentLocaleSnapshotter(locale: "zh-Hans")
            let (model, summary, _) = aiSummaryModel(
                fileID: Int64(650 + index),
                report: report,
                scope: .remoteAllowed,
                contentLocaleSnapshotter: localeSnapshotter
            )

            await model.generate(regenerate: false)

            await localeSnapshotter.assertRequestedRepoPaths(["/tmp/repo"])
            await summary.assertGeneratedContentLocales(["zh-Hans"])
        }
    }

    @MainActor
    func testClearConflictLoadsLatestAndRequiresFreshConfirmedClear() async {
        let observed = AISummarySavedSnapshot.aiSummarySavedSummary(fileID: 724, text: "Observed summary.")
        var latest = AISummarySavedSnapshot.aiSummarySavedSummary(fileID: 724, text: "Latest summary.")
        latest.contentRevision = 2
        let bridge = AISummaryConflictBridge(
            states: [
                AISummaryPersistedStateSnapshot(summary: observed, contentRevision: 1),
                AISummaryPersistedStateSnapshot(summary: latest, contentRevision: 2)
            ],
            clearResults: [
                .failure(CoreError.RevisionConflict(
                    resource: "ai_summary_content_revision",
                    expectedRevision: 1,
                    currentRevision: 2
                )),
                .success(AiSummaryClearReport(
                    fileId: 724,
                    cleared: true,
                    contentRevision: 3,
                    clearedAt: 1_700_000_500
                ))
            ]
        )
        let model = AISummaryEditorModel(
            repoPath: "/tmp/repo",
            fileID: 724,
            summaryStore: bridge,
            contentLocaleSnapshotter: StaticRepositoryContentLocaleSnapshotter(),
            privacyRules: AISummaryIntegrationPrivacyBridge(),
            errorMapper: RecordingCoreErrorMapper.aiSummaryIntegration()
        )

        await model.loadEntryState()
        await model.clear()

        XCTAssertEqual(model.draftText, "Latest summary.")
        XCTAssertEqual(model.clearConflictNotice?.expectedRevision, 1)
        XCTAssertEqual(model.clearConflictNotice?.currentRevision, 2)

        await model.clear()

        XCTAssertEqual(model.status, .empty)
        XCTAssertNil(model.clearConflictNotice)
        await bridge.assertClearCAS(expectedRevisions: [1, 2])
    }

    func testAITagSuggestionPrivacyRuleReferenceNormalizesCorePolicyPrefix() {
        XCTAssertEqual(normalizedAITagPrivacyRuleID(from: "rule:block:rule-confidential"), "rule-confidential")
        XCTAssertEqual(normalizedAITagPrivacyRuleID(from: "block:rule-confidential"), "rule-confidential")
        XCTAssertNil(normalizedAITagPrivacyRuleID(from: "block:privacy-rule"))
    }
}

@MainActor
private func aiSummaryModel(
    fileID: Int64,
    report: AiPrivacyEvaluationReport,
    scope: AiSummaryProviderScope,
    privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext(),
    summary: AISummaryPrivacySummaryBridge = AISummaryPrivacySummaryBridge(),
    mapper: (any CoreErrorMapping)? = nil,
    contentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting = StaticRepositoryContentLocaleSnapshotter()
    // swiftlint:disable:next large_tuple
) -> (AISummaryEditorModel, AISummaryPrivacySummaryBridge, AISummaryPrivacyRulesBridge) {
    let privacy = AISummaryPrivacyRulesBridge(report: report)
    let model = AISummaryEditorModel(
        repoPath: "/tmp/repo",
        fileID: fileID,
        summaryStore: summary,
        contentLocaleSnapshotter: contentLocaleSnapshotter,
        privacyRules: privacy,
        errorMapper: mapper ?? CoreBridge(),
        summaryProviderScope: scope,
        privacyContext: privacyContext
    )
    return (model, summary, privacy)
}

extension AiSummaryDraft {
    static func aiSummaryPrivacyDraft(request: AiSummaryGenerationRequest) -> AiSummaryDraft {
        AiSummaryDraft(
            operationId: request.operationId,
            contentLocale: request.contentLocale,
            formatContractVersion: 1,
            fileId: request.fileId,
            draftId: "draft-aiSummary",
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

    static func aiSummaryPrivacySkippedDraft(
        request: AiSummaryGenerationRequest,
        privacyPolicyRef: String
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            operationId: request.operationId,
            contentLocale: request.contentLocale,
            formatContractVersion: 1,
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
    static func aiSummary(
        _ reason: AiPrivacySkippedReason?,
        providerGateReason: AiPrivacyProviderGateReason? = nil,
        fields: Bool = false
    ) -> AiPrivacyEvaluationReport {
        let allowed = reason == nil
        let matchedRules = reason == .privacyRule ? [aiSummaryRuleMatch()] : []
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

    private static func aiSummaryRuleMatch() -> AiPrivacyRuleMatch {
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

private func aiSummaryReport(
    _ reason: AiPrivacySkippedReason?,
    providerGateReason: AiPrivacyProviderGateReason? = nil,
    fields: Bool = false
) -> AiPrivacyEvaluationReport {
    .aiSummary(reason, providerGateReason: providerGateReason, fields: fields)
}

extension AiPrivacyRulesSnapshot {
    static func aiSummaryPrivacyRules() -> AiPrivacyRulesSnapshot {
        testFixture(
            providerScope: .testFixture(
                featureScope: [.autoSummaries]
            ),
            updatedAt: 1_700_000_250
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static var aiSummarySaveFailure: CoreErrorMappingSnapshot {
        .testFixture(
            kind: .db,
            userMessage: "Summary metadata is unavailable.",
            severity: .medium,
            suggestedAction: "Retry save.",
            recoverability: .retryable,
            rawContext: "ai-summary ai-summary-core"
        )
    }
}
