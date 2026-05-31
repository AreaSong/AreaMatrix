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

struct SQLiteAISummaryMetadataReader: Sendable {
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
        return AISummarySavedSnapshot(
            fileID: fileID,
            summaryText: summaryText,
            savedAt: savedAt,
            draftID: optionalString(preparedStatement, index: 2),
            route: try decodeRoute(optionalString(preparedStatement, index: 3)),
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
