import Foundation

enum CoreBridgeBoundary: String, CaseIterable, Equatable, Sendable {
    case getVersion = "get_version"
    case initLogging = "init_logging"
    case validateRepoPath = "validate_repo_path"
    case initRepo = "init_repo"
    case loadConfig = "load_config"
    case updateConfig = "update_config"
    case recoverOnStartup = "recover_on_startup"
    case reindexFromFilesystem = "reindex_from_filesystem"
    case getLatestScanSession = "get_latest_scan_session"
    case resumeScanSession = "resume_scan_session"
    case predictCategory = "predict_category"
    case importFile = "import_file"
    case deleteFile = "delete_file"
    case renameFile = "rename_file"
    case moveToCategory = "move_to_category"
    case restoreFile = "restore_file"
    case listFiles = "list_files"
    case getFile = "get_file"
    case listChanges = "list_changes"
    case listTreeJSON = "list_tree_json"
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

enum CoreErrorKindSnapshot: String, Equatable, Sendable {
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

enum CoreErrorSeveritySnapshot: String, Equatable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
}

enum CoreErrorRecoverabilitySnapshot: String, Equatable, Sendable {
    case retryable = "Retryable"
    case userActionRequired = "UserActionRequired"
    case refreshRequired = "RefreshRequired"
    case fatal = "Fatal"
}

struct CoreErrorMappingSnapshot: Equatable, Sendable {
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
    init(coreError: CoreError) {
        switch coreError {
        case .Io(let message):
            self.init(kind: .io, path: nil, reason: nil, message: message)
        case .Db(let message):
            self.init(kind: .db, path: nil, reason: nil, message: message)
        case .Config(let reason):
            self.init(kind: .config, path: nil, reason: reason, message: nil)
        case .Classify(let reason):
            self.init(kind: .classify, path: nil, reason: reason, message: nil)
        case .Conflict(let path):
            self.init(kind: .conflict, path: path, reason: nil, message: nil)
        case .DuplicateFile(let existingPath):
            self.init(kind: .duplicateFile, path: existingPath, reason: nil, message: nil)
        case .FileNotFound(let path):
            self.init(kind: .fileNotFound, path: path, reason: nil, message: nil)
        case .RepoNotInitialized(let path):
            self.init(kind: .repoNotInitialized, path: path, reason: nil, message: nil)
        case .InvalidPath(let path):
            self.init(kind: .invalidPath, path: path, reason: nil, message: nil)
        case .ICloudPlaceholder(let path):
            self.init(kind: .iCloudPlaceholder, path: path, reason: nil, message: nil)
        case .PermissionDenied(let path):
            self.init(kind: .permissionDenied, path: path, reason: nil, message: nil)
        case .Internal(let message):
            self.init(kind: .`internal`, path: nil, reason: nil, message: message)
        }
    }
}

private extension CoreErrorKindSnapshot {
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
        case .`internal`: self = .`internal`
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

struct CoreBridgePlaceholderState: Equatable, Sendable {
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

enum CoreBridgeError: Error, Equatable, LocalizedError, Sendable {
    case generatedBindingsUnavailable(
        boundary: CoreBridgeBoundary,
        state: CoreBridgePlaceholderState
    )

    var errorDescription: String? {
        switch self {
        case .generatedBindingsUnavailable(let boundary, let state):
            return "\(state.statusLabel): \(boundary.rawValue) requires generated UniFFI bindings."
        }
    }
}
