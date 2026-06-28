@testable import AreaMatrix
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
        let events = await summary.events()
        XCTAssertEqual(events, [.load])
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
        let events = await summary.events()
        XCTAssertEqual(events, [.load])
    }

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
        let events = await summary.events()
        XCTAssertEqual(events, [
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
        XCTAssertEqual(notice.title, "AI call log is unavailable")
        XCTAssertEqual(notice.reason, .callLogUnavailable)
        XCTAssertEqual(model.draftText, "")
        let events = await summary.events()
        XCTAssertEqual(events, [.generate(regenerate: false, privacyPolicyRef: nil)])
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
