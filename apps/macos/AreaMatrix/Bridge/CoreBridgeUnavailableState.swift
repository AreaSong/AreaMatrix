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
                title: L10n.string("repository.loadError.title"),
                message: bridgeError.localizedDescription,
                recoveryAction: L10n.string("repository.loadError.bridgeRecovery")
            )
        }

        return ConfigLoadFailure(
            repoPath: repoPath,
            title: L10n.string("repository.loadError.title"),
            message: error.localizedDescription,
            recoveryAction: L10n.string("repository.loadError.defaultRecovery")
        )
    }

    private static func map(repoPath: String, coreError: CoreError) -> ConfigLoadFailure {
        switch coreError {
        case let .Config(reason):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.string("repository.loadError.invalidTitle"),
                message: L10n.format("repository.loadError.invalidMessage", reason),
                recoveryAction: L10n.string("repository.loadError.invalidRecovery")
            )
        case let .PermissionDenied(path):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.string("repository.loadError.permissionTitle"),
                message: L10n.format("repository.loadError.permissionMessage", path),
                recoveryAction: L10n.string("repository.loadError.permissionRecovery")
            )
        case let .Io(message):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.string("repository.loadError.ioTitle"),
                message: L10n.format("repository.loadError.ioMessage", message),
                recoveryAction: L10n.string("repository.loadError.ioRecovery")
            )
        case let .Db(message):
            ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.string("repository.loadError.databaseTitle"),
                message: L10n.format("repository.loadError.databaseMessage", message),
                recoveryAction: L10n.string("repository.loadError.databaseRecovery")
            )
        default:
            ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.string("repository.loadError.title"),
                message: coreError.localizedDescription,
                recoveryAction: L10n.string("repository.loadError.defaultRecovery")
            )
        }
    }
}

enum CoreBridgeBoundary: String, CaseIterable, Equatable {
    case getVersion = "get_version"
    case setAppInterfaceLocale = "set_app_interface_locale"
    case initLogging = "init_logging"
    case inspectBindingContract = "inspect_binding_contract"
    case getPlatformCapabilities = "get_platform_capabilities"
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
    case previewBatchDelete = "preview_batch_delete"
    case batchDeleteToTrash = "batch_delete_to_trash"
    case listFiles = "list_files"
    case searchFiles = "search_files"
    case semanticSearch = "semantic_search"
    case buildEmbeddingIndex = "build_embedding_index"
    case getAiFallbackStatus = "get_ai_fallback_status"
    case listFilterFacets = "list_filter_facets"
    case saveClassifierRule = "save_classifier_rule"
    case createSavedSearch = "create_saved_search"
    case updateSavedSearch = "update_saved_search"
    case deleteSavedSearch = "delete_saved_search"
    case listSavedSearches = "list_saved_searches"
    case runSmartList = "run_smart_list"
    case getFile = "get_file"
    case listChanges = "list_changes"
    case listTreeJSON = "list_tree_json"
    case listICloudConflicts = "list_icloud_conflicts"
    case previewConflictVersions = "preview_conflict_versions"
    case resolveICloudConflict = "resolve_icloud_conflict"
    case detectSyncConflicts = "detect_sync_conflicts"
    case previewSyncConflictResolution = "preview_sync_conflict_resolution"
    case resolveSyncConflict = "resolve_sync_conflict"
    case readNote = "read_note"
    case writeNote = "write_note"
    case syncExternalChanges = "sync_external_changes"
    case getFSEventCursor = "get_fs_event_cursor"
    case setFSEventCursor = "set_fs_event_cursor"
    case mapCoreError = "map_core_error"
}

struct CoreBridgeUnavailableState: Equatable {
    let statusLabel: String
    let generatedBindingsPath: String
    let coreLibraryStatus: String
    let declaredBoundaryCount: Int

    var isUnavailable: Bool {
        true
    }

    static var generatedBindingsUnavailable: CoreBridgeUnavailableState {
        CoreBridgeUnavailableState(
            statusLabel: L10n.string("bridge.unavailable.status"),
            generatedBindingsPath: "apps/macos/AreaMatrix/Bridge/Generated/area_matrix.swift",
            coreLibraryStatus: L10n.string("bridge.unavailable.libraryStatus"),
            declaredBoundaryCount: CoreBridgeBoundary.allCases.count
        )
    }
}

enum CoreBridgeError: Error, Equatable, LocalizedError {
    case generatedBindingsUnavailable(
        boundary: CoreBridgeBoundary,
        state: CoreBridgeUnavailableState
    )

    var errorDescription: String? {
        switch self {
        case let .generatedBindingsUnavailable(boundary, state):
            L10n.format("bridge.unavailable.boundaryMessage", state.statusLabel, boundary.rawValue)
        }
    }
}

struct SQLiteExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    private static let supportedSchemaVersion: Int64 = 2

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        let dbURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("index.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw CoreError.Db(message: "missing .areamatrix/index.db")
        }

        let openedDatabase = try Self.openMetadataDatabase(dbURL: dbURL)
        defer {
            sqlite3_close(openedDatabase)
        }
        return try Self.readMetadata(database: openedDatabase)
    }

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

    private static func openMetadataDatabase(dbURL: URL) throws -> OpaquePointer {
        let walURL = URL(fileURLWithPath: "\(dbURL.path)-wal")
        let sharedMemoryURL = URL(fileURLWithPath: "\(dbURL.path)-shm")
        let hasWalSidecars = FileManager.default.fileExists(atPath: walURL.path)
            || FileManager.default.fileExists(atPath: sharedMemoryURL.path)
        if hasWalSidecars {
            return try openMetadataDatabase(path: dbURL.path, flags: SQLITE_OPEN_READONLY)
        }

        guard var components = URLComponents(url: dbURL, resolvingAgainstBaseURL: false) else {
            throw CoreError.Db(message: "invalid metadata database path")
        }
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        guard let immutableURI = components.string else {
            throw CoreError.Db(message: "invalid metadata database URI")
        }
        return try openMetadataDatabase(
            path: immutableURI,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        )
    }

    private static func openMetadataDatabase(path: String, flags: Int32) throws -> OpaquePointer {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &database, flags, nil)
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
