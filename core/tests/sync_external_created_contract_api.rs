use area_matrix_core::{
    get_fs_event_cursor, set_fs_event_cursor, sync_external_changes, CoreError, CoreResult,
    ExternalEvent, ExternalEventKind, SyncResult,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn sync_external_created_contract_api_exposes_documented_signatures_inputs_and_outputs() {
    fn assert_sync(_: fn(String, Vec<ExternalEvent>) -> CoreResult<SyncResult>) {}
    fn assert_get_cursor(_: fn(String) -> CoreResult<Option<i64>>) {}
    fn assert_set_cursor(_: fn(String, i64) -> CoreResult<()>) {}

    assert_sync(sync_external_changes);
    assert_get_cursor(get_fs_event_cursor);
    assert_set_cursor(set_fs_event_cursor);

    let event = ExternalEvent {
        path: "docs/new.pdf".to_owned(),
        kind: ExternalEventKind::Created,
        fs_event_id: 42,
    };
    assert_eq!(event.path, "docs/new.pdf");
    assert_eq!(event.kind, ExternalEventKind::Created);
    assert_eq!(event.fs_event_id, 42);

    let result = SyncResult {
        detected_creates: 1,
        detected_renames: 0,
        detected_deletes: 0,
        detected_modifies: 0,
        errors: Vec::new(),
    };
    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());

    let documented_errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::db("database error"),
        CoreError::io("io error"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn sync_external_created_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);",
        "i64? get_fs_event_cursor(string repo_path);",
        "void set_fs_event_cursor(string repo_path, i64 last_event_id);",
        "dictionary ExternalEvent",
        "string path;",
        "ExternalEventKind kind;",
        "i64 fs_event_id;",
        "dictionary SyncResult",
        "i64 detected_creates;",
        "sequence<string> errors;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn sync_external_created_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in [
        "`InvalidPath { path }`",
        "`ICloudPlaceholder { path }`",
        "`Db { message }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "Synchronizes external filesystem changes after app-layer filtering.",
        "external created sync owns the `ExternalEventKind::Created` contract",
        "platform layer is responsible for FSEvents startup, debounce",
        "in-flight filtering, and iCloud placeholder download coordination",
        "inserts an active",
        "`FileEntry`",
        "`storage_mode = StorageMode::Indexed`",
        "`origin = FileOrigin::External`",
        "queryable change-log entry",
        "`change_log.action =",
        "external_modified`",
        "`kind = create`",
        "`SyncResult::detected_creates`",
        "skip `.areamatrix/`",
        "generated overview output",
        "delete, rename, overwrite, copy, or download",
        "Cursor persistence is part of the batch success contract",
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::ICloudPlaceholder { path }`",
        "`CoreError::Io { message }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "External filesystem event from the platform layer.",
        "Repository-relative or absolute path supplied by the platform layer.",
        "Platform filesystem event identifier.",
        "Summary of external-change synchronization.",
        "Number of created paths detected.",
        "Human-readable errors.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
