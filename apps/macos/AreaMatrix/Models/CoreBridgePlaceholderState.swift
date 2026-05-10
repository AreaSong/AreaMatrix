import Foundation

protocol ExistingRepositoryMetadataReading: Sendable {
    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot
}

struct ExistingRepositoryMetadataSnapshot: Equatable {
    var schemaVersion: Int64
    var lastOpenedAt: Int64?
    var configuredRepoPath: String?
}

struct ConfigLoadFailure: Equatable {
    var repoPath: String
    var title: String
    var message: String
    var recoveryAction: String

    static func map(repoPath: String, error: Error) -> ConfigLoadFailure {
        if let coreError = error as? CoreError {
            return map(repoPath: repoPath, coreError: coreError)
        }

        if let bridgeError = error as? CoreBridgeError {
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Unable to load repository settings",
                message: bridgeError.localizedDescription,
                recoveryAction: "Check the Core bridge integration, then retry opening the repository."
            )
        }

        return ConfigLoadFailure(
            repoPath: repoPath,
            title: "Unable to load repository settings",
            message: error.localizedDescription,
            recoveryAction: "Retry opening the repository or start setup again with a different folder."
        )
    }

    private static func map(repoPath: String, coreError: CoreError) -> ConfigLoadFailure {
        switch coreError {
        case let .Config(reason):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository settings are invalid",
                message: "AreaMatrix could not read the saved settings: \(reason)",
                recoveryAction: "Start setup again or choose a different repository folder."
            )
        case let .PermissionDenied(path):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository settings need permission",
                message: "AreaMatrix cannot read repository settings at \(path).",
                recoveryAction: "Grant folder access, then retry opening the repository."
            )
        case let .Io(message):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository settings are unavailable",
                message: "File system error while reading settings: \(message)",
                recoveryAction: "Make sure the folder is available, then retry."
            )
        case let .Db(message):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository metadata cannot be opened",
                message: "Database error while reading settings: \(message)",
                recoveryAction: "Retry opening the repository or start setup again."
            )
        default:
            ConfigLoadFailure(
                repoPath: repoPath,
                title: "Unable to load repository settings",
                message: coreError.localizedDescription,
                recoveryAction: "Retry opening the repository or start setup again with a different folder."
            )
        }
    }
}

enum CoreBridgeBoundary: String, CaseIterable, Equatable {
    case getVersion = "get_version"
    case initLogging = "init_logging"
    case validateRepoPath = "validate_repo_path"
    case validateInitializedRepoPath = "validate_initialized_repo_path"
    case initRepo = "init_repo"
    case loadConfig = "load_config"
    case updateConfig = "update_config"
    case recoverOnStartup = "recover_on_startup"
    case reindexFromFilesystem = "reindex_from_filesystem"
    case createDiagnosticsSnapshot = "create_diagnostics_snapshot"
    case repairMetadata = "repair_metadata"
    case getLatestScanSession = "get_latest_scan_session"
    case resumeScanSession = "resume_scan_session"
    case predictCategory = "predict_category"
    case previewImport = "preview_import"
    case importFile = "import_file"
    case deleteFile = "delete_file"
    case renameFile = "rename_file"
    case previewMoveToCategory = "preview_move_to_category"
    case moveToCategory = "move_to_category"
    case restoreFile = "restore_file"
    case listFiles = "list_files"
    case getFile = "get_file"
    case listChanges = "list_changes"
    case listTreeJSON = "list_tree_json"
    case listICloudConflicts = "list_icloud_conflicts"
    case readNote = "read_note"
    case writeNote = "write_note"
    case syncExternalChanges = "sync_external_changes"
    case getFSEventCursor = "get_fs_event_cursor"
    case setFSEventCursor = "set_fs_event_cursor"
    case mapCoreError = "map_core_error"
}

protocol CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot
}

enum CoreErrorKindSnapshot: String, Equatable {
    case io = "Io"
    case db = "Db"
    case config = "Config"
    case classify = "Classify"
    case conflict = "Conflict"
    case duplicateFile = "DuplicateFile"
    case fileNotFound = "FileNotFound"
    case repoNotInitialized = "RepoNotInitialized"
    case invalidPath = "InvalidPath"
    case iCloudPlaceholder = "ICloudPlaceholder"
    case permissionDenied = "PermissionDenied"
    case `internal` = "Internal"
}

enum CoreErrorSeveritySnapshot: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
}

enum CoreErrorRecoverabilitySnapshot: String, Equatable {
    case retryable = "Retryable"
    case userActionRequired = "UserActionRequired"
    case refreshRequired = "RefreshRequired"
    case fatal = "Fatal"
}

struct CoreErrorMappingSnapshot: Equatable {
    var kind: CoreErrorKindSnapshot
    var userMessage: String
    var severity: CoreErrorSeveritySnapshot
    var suggestedAction: String
    var recoverability: CoreErrorRecoverabilitySnapshot
    var rawContext: String
}

extension CoreErrorMappingSnapshot {
    init(coreMapping: ErrorMapping) {
        kind = CoreErrorKindSnapshot(coreKind: coreMapping.kind)
        userMessage = coreMapping.userMessage
        severity = CoreErrorSeveritySnapshot(coreSeverity: coreMapping.severity)
        suggestedAction = coreMapping.suggestedAction
        recoverability = CoreErrorRecoverabilitySnapshot(coreRecoverability: coreMapping.recoverability)
        rawContext = coreMapping.rawContext
    }
}

func mapCoreErrorFromCore(_ error: CoreError) -> ErrorMapping {
    mapCoreError(input: ErrorMappingInput(coreError: error))
}

private extension ErrorMappingInput {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreError: CoreError) {
        switch coreError {
        case let .Io(message):
            self.init(kind: .io, path: nil, reason: nil, message: message)
        case let .Db(message):
            self.init(kind: .db, path: nil, reason: nil, message: message)
        case let .Config(reason):
            self.init(kind: .config, path: nil, reason: reason, message: nil)
        case let .Classify(reason):
            self.init(kind: .classify, path: nil, reason: reason, message: nil)
        case let .Conflict(path):
            self.init(kind: .conflict, path: path, reason: nil, message: nil)
        case let .DuplicateFile(existingPath):
            self.init(kind: .duplicateFile, path: existingPath, reason: nil, message: nil)
        case let .FileNotFound(path):
            self.init(kind: .fileNotFound, path: path, reason: nil, message: nil)
        case let .RepoNotInitialized(path):
            self.init(kind: .repoNotInitialized, path: path, reason: nil, message: nil)
        case let .InvalidPath(path):
            self.init(kind: .invalidPath, path: path, reason: nil, message: nil)
        case let .ICloudPlaceholder(path):
            self.init(kind: .iCloudPlaceholder, path: path, reason: nil, message: nil)
        case let .PermissionDenied(path):
            self.init(kind: .permissionDenied, path: path, reason: nil, message: nil)
        case let .Internal(message):
            self.init(kind: .internal, path: nil, reason: nil, message: message)
        }
    }
}

private extension CoreErrorKindSnapshot {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreKind: ErrorKind) {
        switch coreKind {
        case .io: self = .io
        case .db: self = .db
        case .config: self = .config
        case .classify: self = .classify
        case .conflict: self = .conflict
        case .duplicateFile: self = .duplicateFile
        case .fileNotFound: self = .fileNotFound
        case .repoNotInitialized: self = .repoNotInitialized
        case .invalidPath: self = .invalidPath
        case .iCloudPlaceholder: self = .iCloudPlaceholder
        case .permissionDenied: self = .permissionDenied
        case .internal: self = .internal
        }
    }
}

private extension CoreErrorSeveritySnapshot {
    init(coreSeverity: ErrorSeverity) {
        switch coreSeverity {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .critical: self = .critical
        }
    }
}

private extension CoreErrorRecoverabilitySnapshot {
    init(coreRecoverability: ErrorRecoverability) {
        switch coreRecoverability {
        case .retryable: self = .retryable
        case .userActionRequired: self = .userActionRequired
        case .refreshRequired: self = .refreshRequired
        case .fatal: self = .fatal
        }
    }
}

struct CoreBridgePlaceholderState: Equatable {
    let statusLabel: String
    let generatedBindingsPath: String
    let coreLibraryStatus: String
    let declaredBoundaryCount: Int

    var isPlaceholder: Bool {
        true
    }

    static let phase0 = CoreBridgePlaceholderState(
        statusLabel: "CoreBridge placeholder",
        generatedBindingsPath: "apps/macos/AreaMatrix/Bridge/Generated/area_matrix.swift",
        coreLibraryStatus: "UniFFI bindings and static library are not linked in Phase 0",
        declaredBoundaryCount: CoreBridgeBoundary.allCases.count
    )
}

enum CoreBridgeError: Error, Equatable, LocalizedError {
    case generatedBindingsUnavailable(
        boundary: CoreBridgeBoundary,
        state: CoreBridgePlaceholderState
    )

    var errorDescription: String? {
        switch self {
        case let .generatedBindingsUnavailable(boundary, state):
            "\(state.statusLabel): \(boundary.rawValue) requires generated UniFFI bindings."
        }
    }
}

struct SQLiteExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    private static let supportedSchemaVersion: Int64 = 1

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        let dbURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("index.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw CoreError.Db(message: "missing .areamatrix/index.db")
        }

        var lastError: Error?
        for openFlags in Self.openFlags {
            do {
                let openedDatabase = try Self.openMetadataDatabase(dbURL: dbURL, openFlags: openFlags)
                defer {
                    sqlite3_close(openedDatabase)
                }
                return try Self.readMetadata(database: openedDatabase)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CoreError.Db(message: "sqlite metadata read failed")
    }

    private static let openFlags: [Int32] = [
        SQLITE_OPEN_READONLY,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    ]

    private static func readMetadata(database: OpaquePointer) throws -> ExistingRepositoryMetadataSnapshot {
        let schemaVersion = try readRequiredInt64(
            database: database,
            sql: "SELECT COALESCE(MAX(version), 0) FROM schema_version"
        )
        guard schemaVersion > 0 else {
            throw CoreError.Db(message: "schema_version is empty")
        }
        guard schemaVersion <= supportedSchemaVersion else {
            throw CoreError.Config(reason: "unsupported schema version \(schemaVersion)")
        }

        let configuredRepoPath = try readOptionalConfigString(database: database, key: "repo_path")
        let lastOpenedAt = try readOptionalConfigInt64(database: database, key: "last_opened_at")
        return ExistingRepositoryMetadataSnapshot(
            schemaVersion: schemaVersion,
            lastOpenedAt: lastOpenedAt,
            configuredRepoPath: configuredRepoPath
        )
    }

    private static func openMetadataDatabase(dbURL: URL, openFlags: Int32) throws -> OpaquePointer {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(dbURL.path, &database, openFlags, nil)
        guard openResult == SQLITE_OK, let openedDatabase = database else {
            let message = sqliteMessage(database)
            if let database {
                sqlite3_close(database)
            }
            throw CoreError.Db(message: message)
        }

        return openedDatabase
    }

    private static func readRequiredInt64(database: OpaquePointer, sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let preparedStatement = statement else {
            let message = sqliteMessage(database)
            if let statement {
                sqlite3_finalize(statement)
            }
            throw CoreError.Db(message: message)
        }
        defer {
            sqlite3_finalize(preparedStatement)
        }

        guard sqlite3_step(preparedStatement) == SQLITE_ROW else {
            throw CoreError.Db(message: "schema_version row is missing")
        }

        return sqlite3_column_int64(preparedStatement, 0)
    }

    private static func readOptionalConfigString(database: OpaquePointer, key: String) throws -> String? {
        try readOptionalConfigValue(database: database, key: key)
    }

    private static func readOptionalConfigInt64(database: OpaquePointer, key: String) throws -> Int64? {
        guard let value = try readOptionalConfigValue(database: database, key: key) else {
            return nil
        }

        return Int64(value)
    }

    private static func readOptionalConfigValue(database: OpaquePointer, key: String) throws -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM repo_config WHERE key = ?1 LIMIT 1"
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let preparedStatement = statement else {
            let message = sqliteMessage(database)
            if let statement {
                sqlite3_finalize(statement)
            }
            throw CoreError.Db(message: message)
        }
        defer {
            sqlite3_finalize(preparedStatement)
        }

        sqlite3_bind_text(preparedStatement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(preparedStatement) == SQLITE_ROW else {
            return nil
        }
        guard let text = sqlite3_column_text(preparedStatement, 0) else {
            return nil
        }

        return String(cString: text)
    }

    private static func sqliteMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "sqlite metadata read failed"
        }

        return String(cString: message)
    }
}
