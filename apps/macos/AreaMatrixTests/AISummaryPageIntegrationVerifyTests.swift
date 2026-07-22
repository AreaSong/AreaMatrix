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

private func createAISummaryMetadataDatabase(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    let dbURL = metadataURL.appendingPathComponent("index.db", isDirectory: false)

    var database: OpaquePointer?
    guard sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
          let openedDatabase = database
    else {
        let message = database.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "sqlite open failed"
        if let database {
            sqlite3_close(database)
        }
        throw CoreError.Db(message: message)
    }
    defer { sqlite3_close(openedDatabase) }

    try execAISummarySQL(
        database: openedDatabase,
        sql: """
        CREATE TABLE ai_summaries (
            file_id INTEGER PRIMARY KEY,
            summary_text TEXT NOT NULL,
            draft_id TEXT,
            route TEXT,
            model_name TEXT,
            generated_at INTEGER,
            used_context_json TEXT NOT NULL,
            privacy_rule_id TEXT,
            call_log_id INTEGER,
            edited_by_user INTEGER NOT NULL DEFAULT 0,
            saved_at INTEGER NOT NULL
        );
        INSERT INTO ai_summaries (
            file_id, summary_text, draft_id, route, model_name, generated_at,
            used_context_json, privacy_rule_id, call_log_id, edited_by_user, saved_at
        ) VALUES (
            714, 'Saved SQLite AI summary.', 'draft-714', 'remote', 'summary-model', 1700000714,
            '["filename","repo_relative_path"]', 'rule-1', 42, 1, 1700000814
        );
        """
    )
}

private func execAISummarySQL(database: OpaquePointer, sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "sqlite exec failed"
        sqlite3_free(errorMessage)
        throw CoreError.Db(message: message)
    }
}
