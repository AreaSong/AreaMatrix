import Combine
import Foundation

struct AISummarySavedSnapshot: Equatable {
    var fileID: Int64
    var summaryText: String
    var savedAt: Int64
    var draftID: String?
    var route: AiSummaryRoute?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AiSummaryInputField]
    var privacyRuleID: String?
    var callLogID: Int64?
    var editedByUser: Bool
    var characterCount: Int64
}

@MainActor
final class AIPrivacyRulesModel: ObservableObject {
    @Published private(set) var loadState: AIPrivacyRulesLoadState = .loading
    @Published private(set) var snapshot: AiPrivacyRulesSnapshot?
    @Published private(set) var saveError: AISettingsError?
    @Published private(set) var feedback: String?
    @Published private(set) var evaluation: AiPrivacyEvaluationReport?
    @Published private(set) var isSaving = false
    @Published private(set) var isEvaluating = false

    let repoPath: String
    private let rulesManager: any CoreAIPrivacyRulesManaging
    private let evaluator: any CoreAIPrivacyEvaluating
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        rulesManager: any CoreAIPrivacyRulesManaging = CoreBridge(),
        evaluator: any CoreAIPrivacyEvaluating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.rulesManager = rulesManager
        self.evaluator = evaluator
        self.errorMapper = errorMapper
    }

    var rules: [AiPrivacyRuleRecord] {
        snapshot?.rules ?? []
    }

    var fields: [AiPrivacyFieldState] {
        snapshot?.remoteAllowedFields ?? []
    }

    var canEditRemoteFields: Bool {
        snapshot?.privacyGateEnabled == true && !isSaving
    }

    func load() async {
        loadState = .loading
        do {
            snapshot = try await rulesManager.loadAIPrivacyRules(repoPath: repoPath)
            saveError = nil
            loadState = .loaded
        } catch {
            let error = await privacyError(for: error, message: "AI privacy rules could not be loaded.")
            snapshot = nil
            loadState = .failed(error)
        }
    }

    @discardableResult
    func setPrivacyGate(_ enabled: Bool) async -> Bool {
        guard let snapshot, snapshot.privacyGateEnabled != enabled else { return false }
        return await save(snapshot, gate: enabled, rules: snapshot.ruleInputs, success: gateSuccess(enabled))
    }

    func setField(_ field: AiPrivacyInputField, allowRemote: Bool) async {
        guard let snapshot else { return }
        let fields = snapshot.remoteAllowedFields.map {
            AiPrivacyFieldRule(field: $0.field, allowRemote: $0.field == field ? allowRemote : $0.allowRemote)
        }
        _ = await save(snapshot, gate: snapshot.privacyGateEnabled, rules: snapshot.ruleInputs, fields: fields)
    }

    func setRuleEnabled(_ record: AiPrivacyRuleRecord, enabled: Bool) async {
        guard let snapshot else { return }
        let rules = snapshot.rules.map { rule -> AiPrivacyRuleInput in
            var input = AiPrivacyRuleInput(s309Record: rule)
            if rule.ruleId == record.ruleId { input.enabled = enabled }
            return input
        }
        _ = await save(snapshot, gate: snapshot.privacyGateEnabled, rules: rules, success: "Privacy rule saved.")
    }

    @discardableResult
    func addRule(kind: AiPrivacyRuleKind, pattern: String, appliesTo: AiPrivacyRuleAppliesTo) async -> Bool {
        guard let snapshot else { return false }
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var rules = snapshot.ruleInputs
        rules.append(AiPrivacyRuleInput(
            ruleId: nil,
            name: "\(kind.s309Label) \(trimmed)",
            kind: kind,
            pattern: trimmed,
            appliesTo: appliesTo,
            enabled: true,
            description: nil
        ))
        return await save(snapshot, gate: snapshot.privacyGateEnabled, rules: rules, success: "Privacy rule added.")
    }

    func deleteRule(_ record: AiPrivacyRuleRecord) async {
        guard let snapshot else { return }
        let rules = snapshot.rules.filter { $0.ruleId != record.ruleId }.map(AiPrivacyRuleInput.init(s309Record:))
        _ = await save(snapshot, gate: snapshot.privacyGateEnabled, rules: rules, success: "Privacy rule deleted.")
    }

    func evaluate(repoRelativePath: String) async {
        guard let snapshot, !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }
        do {
            evaluation = try await evaluator.evaluateAIPrivacy(
                repoPath: repoPath,
                request: snapshot.s309EvaluationRequest(repoRelativePath: repoRelativePath)
            )
            saveError = nil
        } catch {
            saveError = await privacyError(for: error, message: "AI privacy rules could not be tested.")
        }
    }

    private func save(
        _ base: AiPrivacyRulesSnapshot,
        gate: Bool,
        rules: [AiPrivacyRuleInput],
        fields: [AiPrivacyFieldRule]? = nil,
        success: String = "Remote allowed fields saved."
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            snapshot = try await rulesManager.updateAIPrivacyRules(
                repoPath: repoPath,
                request: AiPrivacyRulesUpdateRequest(
                    privacyGateEnabled: gate,
                    rules: rules,
                    remoteAllowedFields: fields ?? base.fieldRules,
                    providerScope: base.providerScope,
                    confirmed: true
                )
            )
            saveError = nil
            feedback = success
            return true
        } catch {
            saveError = await privacyError(for: error, message: "AI privacy rules could not be saved.")
            return false
        }
    }

    private func privacyError(for error: Error, message: String) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(message: message, recovery: mapping.suggestedAction, detail: mapping.userMessage)
        }
        return AISettingsError(message: message, recovery: "Retry", detail: error.localizedDescription)
    }

    private func gateSuccess(_ enabled: Bool) -> String {
        enabled ? "Remote AI privacy gate allowed." : "Remote AI blocked by privacy gate."
    }
}

struct SQLiteAISummaryMetadataReader {
    func savedSummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot? {
        try await Task.detached(priority: .userInitiated) {
            try Self.readSavedSummary(repoPath: repoPath, fileID: fileID)
        }.value
    }

    private static func readSavedSummary(repoPath: String, fileID: Int64) throws -> AISummarySavedSnapshot? {
        let dbURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("index.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw CoreError.Db(message: "missing .areamatrix/index.db")
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let openedDatabase = database else {
            let message = sqliteMessage(database)
            if let database {
                sqlite3_close(database)
            }
            throw CoreError.Db(message: message)
        }
        defer { sqlite3_close(openedDatabase) }

        guard try tableExists(database: openedDatabase) else { return nil }
        return try readSummary(database: openedDatabase, fileID: fileID)
    }

    private static func tableExists(database: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ai_summaries'"
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let preparedStatement = statement else {
            let message = sqliteMessage(database)
            if let statement {
                sqlite3_finalize(statement)
            }
            throw CoreError.Db(message: message)
        }
        defer { sqlite3_finalize(preparedStatement) }

        return sqlite3_step(preparedStatement) == SQLITE_ROW
    }

    private static func readSummary(database: OpaquePointer, fileID: Int64) throws -> AISummarySavedSnapshot? {
        var statement: OpaquePointer?
        let sql = """
        SELECT summary_text, saved_at, draft_id, route, model_name, generated_at, used_context_json,
               privacy_rule_id, call_log_id, edited_by_user
        FROM ai_summaries
        WHERE file_id = ?1
        LIMIT 1
        """
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let preparedStatement = statement else {
            let message = sqliteMessage(database)
            if let statement {
                sqlite3_finalize(statement)
            }
            throw CoreError.Db(message: message)
        }
        defer { sqlite3_finalize(preparedStatement) }

        sqlite3_bind_int64(preparedStatement, 1, fileID)
        guard sqlite3_step(preparedStatement) == SQLITE_ROW else { return nil }

        let summaryText = try requiredString(preparedStatement, index: 0, column: "summary_text")
        let savedAt = sqlite3_column_int64(preparedStatement, 1)
        let usedContext = try decodeUsedContext(optionalString(preparedStatement, index: 6) ?? "[]")
        return try AISummarySavedSnapshot(
            fileID: fileID,
            summaryText: summaryText,
            savedAt: savedAt,
            draftID: optionalString(preparedStatement, index: 2),
            route: decodeRoute(optionalString(preparedStatement, index: 3)),
            modelName: optionalString(preparedStatement, index: 4),
            generatedAt: optionalInt64(preparedStatement, index: 5),
            usedContext: usedContext,
            privacyRuleID: optionalString(preparedStatement, index: 7),
            callLogID: optionalInt64(preparedStatement, index: 8),
            editedByUser: sqlite3_column_int64(preparedStatement, 9) != 0,
            characterCount: Int64(summaryText.count)
        )
    }

    private static func requiredString(
        _ statement: OpaquePointer,
        index: Int32,
        column: String
    ) throws -> String {
        guard let value = optionalString(statement, index: index) else {
            throw CoreError.Db(message: "\(column) is missing")
        }
        return value
    }

    private static func optionalString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: text)
    }

    private static func optionalInt64(_ statement: OpaquePointer, index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private static func decodeRoute(_ value: String?) throws -> AiSummaryRoute? {
        guard let value else { return nil }
        switch value {
        case "local":
            return .local
        case "remote":
            return .remote
        default:
            throw CoreError.Db(message: "unknown AI summary route: \(value)")
        }
    }

    private static func decodeUsedContext(_ json: String) throws -> [AiSummaryInputField] {
        let names = try JSONDecoder().decode([String].self, from: Data(json.utf8))
        return try names.map(decodeUsedContextField)
    }

    private static func decodeUsedContextField(_ value: String) throws -> AiSummaryInputField {
        switch value {
        case "filename":
            return .fileName
        case "repo_relative_path":
            return .repoRelativePath
        case "extracted_text_excerpt":
            return .extractedTextExcerpt
        case "ai_summary":
            return .existingAiSummary
        case "note_summary":
            return .noteSummary
        case "tag_category_context":
            return .tagCategoryContext
        default:
            throw CoreError.Db(message: "unknown AI summary context field: \(value)")
        }
    }

    private static func sqliteMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "sqlite summary metadata read failed"
        }
        return String(cString: message)
    }
}
