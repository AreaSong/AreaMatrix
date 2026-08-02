import AreaMatrixCoreBridgeContract
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
    var title: LocalizedMessage
    var message: LocalizedMessage
    var recoveryAction: LocalizedMessage

    static func map(repoPath: String, error: Error) -> ConfigLoadFailure {
        if let coreError = error as? CoreError {
            return map(repoPath: repoPath, coreError: coreError)
        }

        if let bridgeError = error as? CoreBridgeError {
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.message("repository.loadError.title"),
                message: L10n.message(
                    "repository.loadError.bridgeMessage",
                    arguments: [.string(bridgeError.localizedDescription)],
                    technicalDetail: bridgeError.localizedDescription
                ),
                recoveryAction: L10n.message("repository.loadError.bridgeRecovery")
            )
        }

        return ConfigLoadFailure(
            repoPath: repoPath,
            title: L10n.message("repository.loadError.title"),
            message: L10n.message(
                "repository.loadError.defaultMessage",
                arguments: [.string(error.localizedDescription)],
                technicalDetail: error.localizedDescription
            ),
            recoveryAction: L10n.message("repository.loadError.defaultRecovery")
        )
    }

    private static func map(repoPath: String, coreError: CoreError) -> ConfigLoadFailure {
        switch coreError {
        case let .Config(reason):
            configFailure(repoPath: repoPath, detail: reason)
        case let .PermissionDenied(path):
            permissionFailure(repoPath: repoPath, detail: path)
        case let .Io(message):
            ioFailure(repoPath: repoPath, detail: message)
        case let .Db(message):
            databaseFailure(repoPath: repoPath, detail: message)
        default:
            ConfigLoadFailure(
                repoPath: repoPath,
                title: L10n.message("repository.loadError.title"),
                message: L10n.message(
                    "repository.loadError.defaultMessage",
                    arguments: [.string(coreError.localizedDescription)],
                    technicalDetail: coreError.localizedDescription
                ),
                recoveryAction: L10n.message("repository.loadError.defaultRecovery")
            )
        }
    }

    private static func configFailure(repoPath: String, detail: String) -> ConfigLoadFailure {
        mappedFailure(
            repoPath,
            L10n.message("repository.loadError.invalidTitle"),
            L10n.message(
                "repository.loadError.invalidMessage",
                arguments: [.string(detail)],
                technicalDetail: detail
            ),
            L10n.message("repository.loadError.invalidRecovery")
        )
    }

    private static func permissionFailure(repoPath: String, detail: String) -> ConfigLoadFailure {
        mappedFailure(
            repoPath,
            L10n.message("repository.loadError.permissionTitle"),
            L10n.message(
                "repository.loadError.permissionMessage",
                arguments: [.string(detail)],
                technicalDetail: detail
            ),
            L10n.message("repository.loadError.permissionRecovery")
        )
    }

    private static func ioFailure(repoPath: String, detail: String) -> ConfigLoadFailure {
        mappedFailure(
            repoPath,
            L10n.message("repository.loadError.ioTitle"),
            L10n.message(
                "repository.loadError.ioMessage",
                arguments: [.string(detail)],
                technicalDetail: detail
            ),
            L10n.message("repository.loadError.ioRecovery")
        )
    }

    private static func databaseFailure(repoPath: String, detail: String) -> ConfigLoadFailure {
        mappedFailure(
            repoPath,
            L10n.message("repository.loadError.databaseTitle"),
            L10n.message(
                "repository.loadError.databaseMessage",
                arguments: [.string(detail)],
                technicalDetail: detail
            ),
            L10n.message("repository.loadError.databaseRecovery")
        )
    }

    private static func mappedFailure(
        _ repoPath: String,
        _ title: LocalizedMessage,
        _ message: LocalizedMessage,
        _ recovery: LocalizedMessage
    ) -> ConfigLoadFailure {
        ConfigLoadFailure(
            repoPath: repoPath,
            title: title,
            message: message,
            recoveryAction: recovery
        )
    }
}

typealias CoreBridgeBoundary = AreaMatrixCoreBridgeContract.CoreBridgeBoundary

struct CoreBridgeUnavailableState: Equatable {
    let statusLabel: LocalizedMessage
    let generatedBindingsPath: String
    let coreLibraryStatus: LocalizedMessage
    let declaredBoundaryCount: Int

    var isUnavailable: Bool {
        true
    }

    static var generatedBindingsUnavailable: CoreBridgeUnavailableState {
        CoreBridgeUnavailableState(
            statusLabel: L10n.message("bridge.unavailable.status"),
            generatedBindingsPath: "apps/macos/AreaMatrix/Bridge/Generated/area_matrix.swift",
            coreLibraryStatus: L10n.message("bridge.unavailable.libraryStatus"),
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
            L10n.format(
                "bridge.unavailable.boundaryMessage",
                L10n.resolve(state.statusLabel),
                boundary.rawValue
            )
        }
    }
}

struct SQLiteExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    private static let supportedSchemaVersion: Int64 = 3

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
