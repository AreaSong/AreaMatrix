@testable import AreaMatrix
import Foundation
import XCTest

actor StaticRepositoryContentLocaleSnapshotter: RepositoryContentLocaleSnapshotting {
    private let locale: String
    private var requestedRepoPaths: [String] = []

    init(locale: String = "en") {
        self.locale = locale
    }

    func repositoryContentLocaleSnapshot(repoPath: String) async throws -> String {
        requestedRepoPaths.append(repoPath)
        return locale
    }

    func assertRequestedRepoPaths(
        _ expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestedRepoPaths, expected, file: file, line: line)
    }
}

func createAISummaryMetadataDatabase(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try createTestTemporaryDirectory(at: metadataURL)
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

    try createAISummaryMetadataSchema(database: openedDatabase)
    try insertAISummaryMetadataFixtures(database: openedDatabase)
}

private func createAISummaryMetadataSchema(database: OpaquePointer) throws {
    try execAISummarySQL(database: database, sql: """
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
        saved_at INTEGER NOT NULL,
        content_revision INTEGER NOT NULL,
        ownership TEXT NOT NULL,
        operation_id TEXT,
        content_locale TEXT,
        format_contract_version INTEGER
    );
    CREATE TABLE ai_summary_revisions (
        file_id INTEGER PRIMARY KEY,
        content_revision INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    );
    """)
}

private func insertAISummaryMetadataFixtures(database: OpaquePointer) throws {
    try execAISummarySQL(database: database, sql: """
    INSERT INTO ai_summaries (
        file_id, summary_text, draft_id, route, model_name, generated_at,
        used_context_json, privacy_rule_id, call_log_id, edited_by_user, saved_at,
        content_revision, ownership, operation_id, content_locale, format_contract_version
    ) VALUES (
        714, 'Saved SQLite AI summary.', 'draft-714', 'remote', 'summary-model', 1700000714,
        '["filename","repo_relative_path"]', 'rule-1', 42, 1, 1700000814,
        3, 'user_owned', 'operation-714', 'en', 1
    );
    INSERT INTO ai_summary_revisions (file_id, content_revision, updated_at) VALUES
        (714, 3, 1700000814),
        (715, 4, 1700000914);
    """)
}

private func execAISummarySQL(database: OpaquePointer, sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "sqlite exec failed"
        sqlite3_free(errorMessage)
        throw CoreError.Db(message: message)
    }
}

enum AISummaryIntegrationSummaryEvent: Equatable {
    case load
    case generate(regenerate: Bool, privacyPolicyRef: String?)
    case save(text: String, edited: Bool, callLogID: Int64?)
    case clear(confirmed: Bool)
}

actor AISummaryIntegrationSummaryBridge: CoreAISummaryManaging {
    private var draftQueue: TestResultQueue<AiSummaryDraft>
    private let savedSummary: AISummarySavedSnapshot?
    private var recorded: [AISummaryIntegrationSummaryEvent] = []
    private var generationOperationLinks: [(operationID: String, retryOf: String?)] = []
    private var saveReplacementConfirmations: [Bool] = []

    init(drafts: [AiSummaryDraft], savedSummary: AISummarySavedSnapshot? = nil) {
        draftQueue = TestResultQueue(results: drafts.map { .success($0) }) {
            .failure(CoreError.Internal(message: "missing ai-summary draft"))
        }
        self.savedSummary = savedSummary
    }

    init(draftResults: [Result<AiSummaryDraft, Error>], savedSummary: AISummarySavedSnapshot? = nil) {
        draftQueue = TestResultQueue(results: draftResults) {
            .failure(CoreError.Internal(message: "missing ai-summary draft"))
        }
        self.savedSummary = savedSummary
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        recorded.append(.load)
        return savedSummary
    }

    func generateAISummary(repoPath _: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        generationOperationLinks.append((request.operationId, request.retryOfOperationId))
        recorded.append(.generate(
            regenerate: request.regenerateExisting,
            privacyPolicyRef: request.privacyPolicyRef
        ))
        return try draftQueue.next()
    }

    func saveAISummary(repoPath _: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        saveReplacementConfirmations.append(request.confirmReplaceUserOwned)
        recorded.append(.save(
            text: request.summaryText,
            edited: request.ownership == .userOwned,
            callLogID: request.callLogId
        ))
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
        recorded.append(.clear(confirmed: request.confirmed))
        return AiSummaryClearReport(
            fileId: request.fileId,
            cleared: true,
            contentRevision: request.expectedContentRevision + 1,
            clearedAt: 1_700_000_200
        )
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

    func assertGenerationRetryChain(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(generationOperationLinks.count, 2, file: file, line: line)
        guard generationOperationLinks.count == 2 else { return }
        XCTAssertNil(generationOperationLinks[0].retryOf, file: file, line: line)
        XCTAssertNotEqual(
            generationOperationLinks[0].operationID,
            generationOperationLinks[1].operationID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            generationOperationLinks[1].retryOf,
            generationOperationLinks[0].operationID,
            file: file,
            line: line
        )
    }

    func assertSaveReplacementConfirmations(
        _ expected: [Bool],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(saveReplacementConfirmations, expected, file: file, line: line)
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

    func assertEvaluatedRoutes(
        _ expectedRoutes: [AiPrivacyEvaluationRoute],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRoutes, expectedRoutes, file: file, line: line)
    }
}

actor AISummaryConflictBridge: CoreAISummaryManaging {
    private var stateQueue: TestResultQueue<AISummaryPersistedStateSnapshot>
    private var saveQueue: TestResultQueue<AiSummarySaveReport>
    private var clearQueue: TestResultQueue<AiSummaryClearReport>
    private var expectedRevisions: [Int64] = []
    private var confirmations: [Bool] = []
    private var clearExpectedRevisions: [Int64] = []

    init(
        states: [AISummaryPersistedStateSnapshot],
        saveResults: [Result<AiSummarySaveReport, Error>] = [],
        clearResults: [Result<AiSummaryClearReport, Error>] = []
    ) {
        stateQueue = TestResultQueue(results: states.map { .success($0) }) {
            .failure(CoreError.Internal(message: "missing AI summary state"))
        }
        saveQueue = TestResultQueue(results: saveResults) {
            .failure(CoreError.Internal(message: "missing AI summary save result"))
        }
        clearQueue = TestResultQueue(results: clearResults) {
            .failure(CoreError.Internal(message: "missing AI summary clear result"))
        }
    }

    func loadAISummaryState(
        repoPath _: String,
        fileID _: Int64
    ) async throws -> AISummaryPersistedStateSnapshot {
        try stateQueue.next()
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        try stateQueue.next().summary
    }

    func generateAISummary(repoPath _: String, request _: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        throw CoreError.Internal(message: "generation is not expected")
    }

    func saveAISummary(repoPath _: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        expectedRevisions.append(request.expectedContentRevision)
        confirmations.append(request.confirmReplaceUserOwned)
        return try saveQueue.next()
    }

    func clearAISummary(repoPath _: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport {
        clearExpectedRevisions.append(request.expectedContentRevision)
        return try clearQueue.next()
    }

    func assertSaveCAS(
        expectedRevisions expected: [Int64],
        confirmations expectedConfirmations: [Bool],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expectedRevisions, expected, file: file, line: line)
        XCTAssertEqual(confirmations, expectedConfirmations, file: file, line: line)
    }

    func assertClearCAS(
        expectedRevisions expected: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(clearExpectedRevisions, expected, file: file, line: line)
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
