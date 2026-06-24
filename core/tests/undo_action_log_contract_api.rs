use area_matrix_core::{
    list_undo_actions, undo_action, CoreError, CoreResult, UndoActionRecord, UndoActionResult,
    UndoActionStatus,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UNDO_RS: &str = include_str!("../src/undo.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn undo_action_log_contract_exposes_signatures_outputs_and_errors() {
    fn assert_list(_: fn(String) -> CoreResult<Vec<UndoActionRecord>>) {}
    fn assert_undo(_: fn(String, String) -> CoreResult<UndoActionResult>) {}

    assert_list(list_undo_actions);
    assert_undo(undo_action);

    let action = UndoActionRecord {
        action_id: "undo:batch-tags:42".to_owned(),
        kind: "batch_add_tags".to_owned(),
        summary: "Added tag \"finance\" to 24 files.".to_owned(),
        affected_count: 24,
        affected_file_names: vec!["contract.pdf".to_owned()],
        status: UndoActionStatus::Pending,
        can_undo: true,
        disabled_reason: None,
        created_at: 1_000,
        updated_at: 1_000,
    };
    assert_eq!(action.action_id, "undo:batch-tags:42");
    assert_eq!(action.kind, "batch_add_tags");
    assert_eq!(action.affected_count, 24);
    assert_eq!(action.affected_file_names, vec!["contract.pdf"]);
    assert_eq!(action.status, UndoActionStatus::Pending);
    assert!(action.can_undo);

    let result = UndoActionResult {
        action_id: action.action_id.clone(),
        status: UndoActionStatus::Executed,
        summary: "Undone: added tag \"finance\" to 24 files.".to_owned(),
        affected_count: 24,
        refresh_targets: vec![
            "files".to_owned(),
            "tags".to_owned(),
            "undo_actions".to_owned(),
            "change_log".to_owned(),
        ],
        completed_at: 1_100,
    };
    assert_eq!(result.status, UndoActionStatus::Executed);
    assert_eq!(result.refresh_targets[2], "undo_actions");

    let documented_errors = [
        CoreError::conflict("undo action blocked"),
        CoreError::file_not_found("missing undo action"),
        CoreError::permission_denied("permission denied"),
        CoreError::db("undo metadata failed"),
        CoreError::io("undo filesystem failed"),
    ];
    assert_eq!(documented_errors.len(), 5);
}

#[test]
fn undo_action_log_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        list_undo_actions(String::new()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        list_undo_actions("/tmp/repo".to_owned()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        undo_action("/tmp/repo".to_owned(), String::new()),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        undo_action(String::new(), "undo:batch-tags:42".to_owned()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        undo_action("/tmp/repo".to_owned(), "undo:batch-tags:42".to_owned()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn undo_action_log_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "sequence<UndoActionRecord> list_undo_actions(string repo_path);",
        "UndoActionResult undo_action(string repo_path, string action_id);",
        "dictionary UndoActionRecord",
        "string action_id;",
        "string kind;",
        "string summary;",
        "i64 affected_count;",
        "sequence<string> affected_file_names;",
        "UndoActionStatus status;",
        "boolean can_undo;",
        "string? disabled_reason;",
        "dictionary UndoActionResult",
        "sequence<string> refresh_targets;",
        "enum UndoActionStatus { \"Pending\", \"Executed\", \"Expired\", \"Blocked\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_undo_actions(repo)` | undo | √ | Db / Io |",
        "| `undo_action(repo, action_id)` | undo | √ | Conflict / FileNotFound / PermissionDenied / Db / Io |",
        "### `list_undo_actions(repoPath) throws -> [UndoActionRecord]`",
        "### `undo_action(repoPath, actionId) throws -> UndoActionResult`",
        "`undo toast`",
        "`undo history surface`",
        "`Pending`、`Executed`、`Expired`、`Blocked`",
        "`refresh_targets`",
        "外部 FSEvents 造成的变化不得伪装成可撤销操作",
        "Redo stack 和 `Shift+Cmd+Z` 属于",
        "redo action log",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn undo_action_log_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "undo action log contract",
        "UndoActionRecord",
        "UndoActionResult",
        "list_undo_actions",
        "undo_action",
        "Listing is metadata-only",
        "stack execution stays with redo action log",
        "Failed undo must not corrupt",
        "partially mark an action as executed",
    ] {
        assert_contains(UNDO_RS, fragment);
    }

    for error_name in ["Conflict", "FileNotFound", "PermissionDenied", "Db", "Io"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
