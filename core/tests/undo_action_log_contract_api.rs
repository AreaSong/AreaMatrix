use area_matrix_core::{
    list_undo_actions, undo_action, CoreError, CoreResult, UndoActionRecord, UndoActionResult,
    UndoActionStatus,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-07-undo-action-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const UNDO_TOAST_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-10-undo-toast.md");
const UNDO_HISTORY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-11-undo-history.md");
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
        "# C2-07 undo-action-log",
        "- S2-10 undo-toast",
        "- S2-11 undo-history",
        "`list_undo_actions`",
        "`undo_action(repo_path, action_id)`",
        "Undo 执行结果和刷新建议。",
        "- `Conflict`",
        "- `FileNotFound`",
        "- `PermissionDenied`",
        "- `Db`",
        "- `Io`",
        "外部变化不可撤销时必须明确显示。",
        "Undo 失败不破坏当前状态。",
        "多端协同 undo 属于 Stage 4。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-10 | undo-toast | C2-07 | undo action | undo_actions",
        "| S2-11 | undo-history | C2-07 | list/execute undo | undo_actions",
        "| S2-09 | batch-add-tags | C2-06, C2-07 | batch tag mutation | tags, undo_actions",
        "| S2-12 | batch-change-category | C2-08, C2-07 | preview + batch move",
        "| S2-13 | batch-delete-confirm | C2-09, C2-07 | preview + Trash delete",
        "| S2-14 | batch-rename | C2-10, C2-07 | preview + rename",
        "| S2-22 | redo | C2-18, C2-07 | redo action | undo_actions / redo stack",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "`S2-10 undo-toast`",
        "`S2-11 undo-history`",
        "`Pending`、`Executed`、`Expired`、`Blocked`",
        "`refresh_targets`",
        "外部 FSEvents 造成的变化不得伪装成可撤销操作",
        "Redo stack 和 `Shift+Cmd+Z` 属于",
        "C2-18",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn undo_action_log_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "只有可撤销操作显示 `Undo`。",
        "Undo action 已过期、被后续写操作阻塞",
        "toast 自动隐藏不等于 Undo 过期",
        "Undo 执行中禁用按钮并显示 `Undoing...`。",
        "Undo 失败时显示错误 toast，提供 `View details`。",
        "Cmd+Z 与 toast Undo 指向同一个操作。",
        "View history",
    ] {
        assert_contains(UNDO_TOAST_PAGE, fragment);
    }

    for fragment in [
        "列出最近可撤销操作。",
        "显示每个操作的类型、影响数量、时间、是否仍可撤销。",
        "显示不可撤销原因：过期、文件已外部变更、应用重启后不可用等。",
        "只能撤销最上方最新操作",
        "Undo stack snapshot",
        "Trash restore 失败时不删除历史行",
    ] {
        assert_contains(UNDO_HISTORY_PAGE, fragment);
    }

    for fragment in [
        "C2-07 undo action log contract",
        "UndoActionRecord",
        "UndoActionResult",
        "list_undo_actions",
        "undo_action",
        "Listing is metadata-only",
        "stack execution stays with C2-18",
        "Failed undo must not corrupt",
        "partially mark an action as executed",
    ] {
        assert_contains(UNDO_RS, fragment);
    }

    for error_name in ["Conflict", "FileNotFound", "PermissionDenied", "Db", "Io"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
