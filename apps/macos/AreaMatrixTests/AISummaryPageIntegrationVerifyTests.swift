@testable import AreaMatrix
import Combine
import XCTest

final class AISummaryPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testAISummaryEntryLoadAllowsEmptySummaryWithoutHardcodedReadBlocker() async {
        let summary = AISummaryIntegrationSummaryBridge(drafts: [])
        let model = aiSummaryIntegrationModel(fileID: 705, summary: summary)

        await model.loadEntryState()

        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.gateState, .allowed)
        XCTAssertTrue(model.canGenerate)
        XCTAssertFalse(model.canRegenerate)
        await summary.assertEvents([.load])
    }

    @MainActor
    func testAISummaryEntryLoadShowsSavedSummaryWithMetadataAndNoUnsavedExitPrompt() async {
        let summary = AISummaryIntegrationSummaryBridge(
            drafts: [],
            savedSummary: .aiSummarySavedSummary(fileID: 708, text: "Previously saved AI summary.")
        )
        let model = aiSummaryIntegrationModel(fileID: 708, summary: summary)

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
        await summary.assertEvents([.load])
    }

    @MainActor
    func testUserOwnedSummaryGenerationRequiresSideBySideReplacementReview() async {
        let saved = AISummarySavedSnapshot.aiSummarySavedSummary(
            fileID: 720,
            text: "Current user summary.",
            ownership: .userOwned
        )
        let summary = AISummaryIntegrationSummaryBridge(
            drafts: [
                .aiSummaryIntegrationDraft(
                    fileID: 720,
                    text: "New generated candidate.",
                    draftID: "replacement",
                    callLogID: 1720
                )
            ],
            savedSummary: saved
        )
        let model = aiSummaryIntegrationModel(fileID: 720, summary: summary)

        await model.loadEntryState()
        await model.generate(regenerate: true)

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Current user summary.")
        XCTAssertEqual(model.replacementReview?.savedText, "Current user summary.")
        XCTAssertEqual(model.replacementReview?.candidateText, "New generated candidate.")
        XCTAssertEqual(model.replacementReview?.savedProvenance.ownership, .userOwned)
        await summary.assertSaveReplacementConfirmations([])

        model.continueEditingReplacement()
        XCTAssertEqual(model.status, .dirty)
        XCTAssertEqual(model.draftText, "New generated candidate.")

        let savedWithoutConfirmation = await model.save()
        XCTAssertFalse(savedWithoutConfirmation)
        XCTAssertNotNil(model.replacementReview)
        await summary.assertSaveReplacementConfirmations([])

        let replaced = await model.replaceReviewedSummary()
        XCTAssertTrue(replaced)
        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.provenance?.ownership, .userOwned)
        await summary.assertSaveReplacementConfirmations([true])
    }

    @MainActor
    func testUserOwnedSummaryCanKeepGeneratedCandidateWithoutChangingSavedValue() async {
        let summary = AISummaryIntegrationSummaryBridge(
            drafts: [
                .aiSummaryIntegrationDraft(
                    fileID: 721,
                    text: "Discarded candidate.",
                    draftID: "discarded",
                    callLogID: 1721
                )
            ],
            savedSummary: .aiSummarySavedSummary(
                fileID: 721,
                text: "Keep this user summary.",
                ownership: .userOwned
            )
        )
        let model = aiSummaryIntegrationModel(fileID: 721, summary: summary)

        await model.loadEntryState()
        await model.generate(regenerate: true)
        model.keepExistingSummary()

        XCTAssertNil(model.replacementReview)
        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Keep this user summary.")
        await summary.assertSaveReplacementConfirmations([])
    }

    @MainActor
    func testRetryGenerationCreatesLinkedNewOperationIdentity() async {
        let draft = AISummaryDraftSnapshot.aiSummaryIntegrationDraft(
            fileID: 722,
            text: "Retry succeeded.",
            draftID: "retry",
            callLogID: 1722
        )
        let summary = AISummaryIntegrationSummaryBridge(draftResults: [
            .failure(CoreError.Db(message: "provider temporarily unavailable")),
            .success(draft)
        ])
        let model = aiSummaryIntegrationModel(fileID: 722, summary: summary)

        await model.generate(regenerate: false)
        XCTAssertEqual(model.failedAction, .generate)

        await model.retryGeneration()

        XCTAssertEqual(model.status, .draft)
        XCTAssertEqual(model.draftText, "Retry succeeded.")
        await summary.assertGenerationRetryChain()
    }

    @MainActor
    func testSaveConflictRetainsDraftLoadsLatestAndRequiresSecondConfirmedSave() async {
        let context = makeAISummarySaveConflictContext()
        let bridge = context.bridge
        let model = context.model

        await model.loadEntryState()
        model.updateDraft("My retained local draft.")
        let firstSave = await model.save()
        XCTAssertFalse(firstSave)
        XCTAssertNotNil(model.replacementReview)
        let conflictedSave = await model.replaceReviewedSummary()
        XCTAssertFalse(conflictedSave)

        XCTAssertEqual(model.draftText, "My retained local draft.")
        XCTAssertEqual(
            model.saveConflictReview?.latestState.summary?.summaryText,
            "Latest summary from another window."
        )
        XCTAssertEqual(model.saveConflictReview?.localText, "My retained local draft.")

        model.reviewLatestAfterSaveConflict()
        XCTAssertNil(model.saveConflictReview)
        XCTAssertEqual(model.status, .dirty)
        let unconfirmedSecondSave = await model.save()
        XCTAssertFalse(unconfirmedSecondSave)
        let secondSave = await model.replaceReviewedSummary()
        XCTAssertTrue(secondSave)
        XCTAssertEqual(model.status, .saved)
        await bridge.assertSaveCAS(expectedRevisions: [1, 2], confirmations: [true, true])
    }
}

extension AISummaryPageIntegrationVerifyTests {
    @MainActor
    func testAISummarySummaryPrivacyAndProvenanceStayOnDeclaredCoreBridgePath() async {
        let privacy = AISummaryIntegrationPrivacyBridge()
        let summary = AISummaryIntegrationSummaryBridge(drafts: [
            .aiSummaryIntegrationDraft(fileID: 706, text: "Initial AI summary.", draftID: "draft-a", callLogID: 1706),
            .aiSummaryIntegrationDraft(
                fileID: 706,
                text: "Regenerated AI summary.",
                draftID: "draft-b",
                callLogID: 2706
            )
        ])
        let model = aiSummaryIntegrationModel(fileID: 706, summary: summary, privacy: privacy)

        await model.generate(regenerate: false)
        await model.save()
        model.updateDraft("Unsaved local edit.")
        await model.generate(regenerate: true)
        model.discardChanges()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Initial AI summary.")
        XCTAssertEqual(model.provenance?.callLogID, 1706)

        await model.clear()

        await privacy.assertEvaluatedRoutes([.remote, .remote])
        await summary.assertEvents([
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
    func testAISummaryPrivacyGateFailurePreservesDraftAndRecordsSkippedSummaryTrace() async {
        let summary = AISummaryIntegrationSummaryBridge(drafts: [
            .aiSummaryIntegrationDraft(fileID: 712, text: "Initial AI summary.", draftID: "draft-a", callLogID: 1712),
            .aiSummaryIntegrationPrivacySkippedDraft(
                fileID: 712,
                privacyRuleID: "block:rule-confidential",
                callLogID: 9712
            )
        ])
        let model = aiSummaryIntegrationModel(fileID: 712, summary: summary)
        await model.generate(regenerate: false)
        model.updateDraft("Keep this draft.")

        let blocked = aiSummaryIntegrationModel(
            fileID: 712,
            summary: summary,
            privacy: AISummaryIntegrationPrivacyBridge(report: .aiSummaryDeniedPrivacyRule())
        )
        blocked.updateDraft("Keep this draft.")
        await blocked.generate(regenerate: true)

        guard case let .blocked(notice) = blocked.gateState else {
            return XCTFail("Expected privacy gate to block regenerate.")
        }
        XCTAssertEqual(notice.capability, "ai-privacy-rules-core")
        XCTAssertEqual(blocked.draftText, "Keep this draft.")
        XCTAssertEqual(blocked.status, .skipped(.privacyRule))
        XCTAssertEqual(blocked.privacySkip?.sentFields, [])
        XCTAssertEqual(blocked.provenance?.callLogID, 9712)
        await summary.assertEvents([
            .generate(regenerate: false, privacyPolicyRef: nil),
            .generate(regenerate: true, privacyPolicyRef: "block:rule-confidential")
        ])
    }

    @MainActor
    func testAISummarySummaryUnavailableFromCoreShowsAISummaryCoreGateWithoutExtraCoreBridgeDependencies() async {
        let summary = AISummaryIntegrationSummaryBridge(drafts: [
            .aiSummaryIntegrationUnavailableDraft(fileID: 713, reason: .callLogUnavailable)
        ])
        let model = aiSummaryIntegrationModel(fileID: 713, summary: summary)

        await model.generate(regenerate: false)

        guard case let .blocked(notice) = model.gateState else {
            return XCTFail("Expected ai-summary-core unavailable draft to block the page action.")
        }
        XCTAssertEqual(notice.title, L10n.string("AI call log is unavailable"))
        XCTAssertEqual(notice.reason, .callLogUnavailable)
        XCTAssertEqual(model.draftText, "")
        await summary.assertEvents([.generate(regenerate: false, privacyPolicyRef: nil)])
    }

    func testDefaultCoreBridgeLoadsSavedAISummaryFromSQLiteMetadata() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AISummaryMetadataReaderTests")
        defer { removeTestTemporaryItems(repoURL) }
        try createAISummaryMetadataDatabase(in: repoURL)

        let saved = try await CoreBridge().loadSavedAISummary(repoPath: repoURL.path, fileID: 714)

        XCTAssertEqual(saved?.fileID, 714)
        XCTAssertEqual(saved?.summaryText, "Saved SQLite AI summary.")
        XCTAssertEqual(saved?.route, .remote)
        XCTAssertEqual(saved?.modelName, "summary-model")
        XCTAssertEqual(saved?.usedContext, [.fileName, .repoRelativePath])
        XCTAssertEqual(saved?.privacyRuleID, "rule-1")
        XCTAssertEqual(saved?.callLogID, 42)
        XCTAssertTrue(saved?.editedByUser == true)
        XCTAssertEqual(saved?.characterCount, Int64("Saved SQLite AI summary.".count))

        let tombstone = try await CoreBridge().loadAISummaryState(repoPath: repoURL.path, fileID: 715)
        XCTAssertNil(tombstone.summary)
        XCTAssertEqual(tombstone.contentRevision, 4)
    }

    @MainActor
    func testAISummaryDraftUpdatePublishesEditorViewChange() {
        let model = aiSummaryIntegrationModel(fileID: 714)
        var publishCount = 0
        let cancellable = model.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        model.updateDraft("Local draft update.")

        XCTAssertEqual(model.draftText, "Local draft update.")
        XCTAssertGreaterThanOrEqual(publishCount, 1)
    }

    @MainActor
    func testAISummaryExitConfirmationSavesDiscardsOrKeepsDraftUntilUserChooses() async {
        let summary = AISummaryIntegrationSummaryBridge(drafts: [
            .aiSummaryIntegrationDraft(fileID: 707, text: "Saved AI summary.", draftID: "draft-exit", callLogID: 1707)
        ])
        let model = aiSummaryIntegrationModel(fileID: 707, summary: summary)
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
        await summary.assertEvents([
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
        await summary.assertEvents([
            .generate(regenerate: false, privacyPolicyRef: nil),
            .save(text: "Saved AI summary.", edited: false, callLogID: 1707),
            .save(text: "Dirty exit draft.", edited: true, callLogID: 1707)
        ])
    }

    func testAISummaryDirtySelectionChangeRestoresPreviousFileUntilUserChooses() {
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
private func makeAISummarySaveConflictContext() -> (
    bridge: AISummaryConflictBridge,
    model: AISummaryEditorModel
) {
    let observed = AISummarySavedSnapshot.aiSummarySavedSummary(
        fileID: 723,
        text: "Observed user summary.",
        ownership: .userOwned
    )
    var latest = AISummarySavedSnapshot.aiSummarySavedSummary(
        fileID: 723,
        text: "Latest summary from another window.",
        ownership: .userOwned
    )
    latest.contentRevision = 2
    let bridge = AISummaryConflictBridge(
        states: [
            AISummaryPersistedStateSnapshot(summary: observed, contentRevision: 1),
            AISummaryPersistedStateSnapshot(summary: latest, contentRevision: 2)
        ],
        saveResults: [
            .failure(CoreError.RevisionConflict(
                resource: "ai_summary_content_revision",
                expectedRevision: 1,
                currentRevision: 2
            )),
            .success(makeAISummaryFinalReport(observed: observed))
        ]
    )
    let model = AISummaryEditorModel(
        repoPath: "/tmp/repo",
        fileID: 723,
        summaryStore: bridge,
        contentLocaleSnapshotter: StaticRepositoryContentLocaleSnapshotter(),
        privacyRules: AISummaryIntegrationPrivacyBridge(),
        errorMapper: RecordingCoreErrorMapper.aiSummaryIntegration()
    )
    return (bridge, model)
}

private func makeAISummaryFinalReport(observed: AISummarySavedSnapshot) -> AISummarySaveReportSnapshot {
    AISummarySaveReportSnapshot(
        fileID: 723,
        contentRevision: 3,
        ownership: .userOwned,
        savedSummary: "My retained local draft.",
        savedAt: 1_700_000_400,
        route: observed.route,
        modelName: observed.modelName,
        generatedAt: observed.generatedAt,
        usedContext: observed.usedContext,
        privacyRuleID: observed.privacyRuleID,
        callLogID: observed.callLogID,
        operationID: observed.operationID ?? "saved-operation-723",
        contentLocale: observed.contentLocale ?? .en,
        formatContractVersion: observed.formatContractVersion ?? 1,
        characterCount: Int64("My retained local draft.".count)
    )
}
