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
