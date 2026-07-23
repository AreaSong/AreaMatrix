use area_matrix_core::{
    sync_external_changes, CoreError, CoreResult, ExternalEvent, ExternalEventKind, SyncResult,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
#[path = "support/domain_contract_source.rs"]
mod domain_contract_source;

use domain_contract_source::DOMAIN_RS;
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn sync_external_renamed_contract_api_exposes_documented_signature_input_and_output() {
    fn assert_sync(_: fn(String, Vec<ExternalEvent>, String) -> CoreResult<SyncResult>) {}
    assert_sync(sync_external_changes);

    let event = ExternalEvent {
        path: "docs/renamed.pdf".to_owned(),
        kind: ExternalEventKind::Renamed,
        fs_event_id: 184,
    };
    assert_eq!(event.path, "docs/renamed.pdf");
    assert_eq!(event.kind, ExternalEventKind::Renamed);
    assert_eq!(event.fs_event_id, 184);

    let result = SyncResult {
        detected_creates: 0,
        detected_renames: 1,
        detected_deletes: 0,
        detected_modifies: 0,
        errors: Vec::new(),
    };
    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::conflict("path conflict"),
        CoreError::db("database error"),
        CoreError::io("io error"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn sync_external_renamed_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "SyncResult sync_external_changes(\n        string repo_path, sequence<ExternalEvent> events, string content_locale\n    );",
        "dictionary ExternalEvent",
        "string path;",
        "ExternalEventKind kind;",
        "i64 fs_event_id;",
        "dictionary SyncResult",
        "i64 detected_renames;",
        "sequence<string> errors;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn sync_external_renamed_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in [
        "`FileNotFound { path }`",
        "`Conflict { path }`",
        "`Db { message }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "Core owns rename pairing for the `ExternalEventKind::Renamed` contract",
        "`path` is only the repository-relative or absolute new path",
        "Core reads a stable target hash",
        "requires exactly one active metadata row with that hash whose recorded old",
        "path no longer exists. A target path already represented by any active",
        "fails closed with `CoreError::Conflict { path }`",
        "A successful rename updates `files.path`, `files.current_name`, category",
        "size/hash, and `updated_at`, writes `change_log.action = renamed` with",
        "old/new path detail",
        "`SyncResult::detected_renames`",
        "must not",
        "rename, move, delete, overwrite, copy, or",
        "download a user file",
        "Callers replay the same event after a recoverable",
        "failure instead of synthesizing replacement events",
        "Returns `CoreError::FileNotFound { path }`",
        "`CoreError::Conflict { path }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Filesystem event kind sent from the platform layer.",
        "A path was renamed.",
        "External filesystem event from the platform layer.",
        "Repository-relative or absolute path supplied by the platform layer.",
        "Platform filesystem event identifier.",
        "Summary of external-change synchronization.",
        "Number of renames detected.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
