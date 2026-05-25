use area_matrix_core::{
    list_redo_actions, redo_action, CoreError, CoreResult, RedoActionRecord, RedoActionResult,
    RedoActionStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-1-stage2-experience/task-86-c2-18-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-18-redo-action-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const REDO_RS: &str = include_str!("../src/redo.rs");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn redo_action_log_contract_exposes_signatures_outputs_and_errors() {
    fn assert_list(_: fn(String) -> CoreResult<Vec<RedoActionRecord>>) {}
    fn assert_redo(_: fn(String, String) -> CoreResult<RedoActionResult>) {}

    assert_list(list_redo_actions);
    assert_redo(redo_action);

    let action = RedoActionRecord {
        action_id: "redo:batch-tags:42".to_owned(),
        kind: "batch_add_tags".to_owned(),
        summary: "Redo: add tag \"finance\" to 24 files.".to_owned(),
        affected_count: 24,
        affected_file_names: vec!["contract.pdf".to_owned()],
        status: RedoActionStatus::Available,
        can_redo: true,
        disabled_reason: None,
        source_undo_action_id: "undo:batch-tags:42".to_owned(),
        created_at: 1_000,
        updated_at: 1_000,
    };
    assert_eq!(action.action_id, "redo:batch-tags:42");
    assert_eq!(action.source_undo_action_id, "undo:batch-tags:42");
    assert_eq!(action.status, RedoActionStatus::Available);
    assert!(action.can_redo);

    let result = RedoActionResult {
        action_id: action.action_id.clone(),
        status: RedoActionStatus::Executed,
        summary: "Redone: added tag \"finance\" to 24 files.".to_owned(),
        affected_count: 24,
        refresh_targets: vec![
            "files".to_owned(),
            "tags".to_owned(),
            "undo_actions".to_owned(),
            "redo_actions".to_owned(),
            "change_log".to_owned(),
        ],
        undo_token: Some("undo:redo:batch-tags:42".to_owned()),
        completed_at: 1_100,
    };
    assert_eq!(result.status, RedoActionStatus::Executed);
    assert_eq!(result.refresh_targets[3], "redo_actions");
    assert_eq!(
        result.undo_token.as_deref(),
        Some("undo:redo:batch-tags:42")
    );

    let documented_errors = [
        CoreError::conflict("redo action blocked"),
        CoreError::file_not_found("missing redo action"),
        CoreError::expired_action("redo action expired"),
        CoreError::permission_denied("permission denied"),
        CoreError::db("redo metadata failed"),
        CoreError::io("redo filesystem failed"),
    ];
    assert_eq!(documented_errors.len(), 6);
}

#[test]
fn redo_action_log_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        list_redo_actions(String::new()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        list_redo_actions("/tmp/repo".to_owned()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        redo_action("/tmp/repo".to_owned(), String::new()),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        redo_action(String::new(), "redo:batch-tags:42".to_owned()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        redo_action("/tmp/repo".to_owned(), "redo:batch-tags:42".to_owned()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn redo_action_log_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-1/task-86: C2-18 contract-api",
        "为 C2-18 redo-action-log 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C2-18 redo-action-log",
        "- S2-22 redo",
        "计划新增：`list_redo_actions`、`redo_action(repo_path, action_id)`",
        "Redo 可用性、执行结果、刷新建议和失败原因。",
        "更新 undo/redo action 状态。",
        "写入 redo 对应 change log。",
        "必须使用原 action 的安全执行路径。",
        "- `Conflict`",
        "- `FileNotFound`",
        "- `PermissionDenied`",
        "- `ExpiredAction`",
        "- `Db`",
        "- `Io`",
        "只有 AreaMatrix 成功 Undo 的动作可以 Redo。",
        "新写操作会清空 redo stack。",
        "Redo 失败不破坏当前文件系统和 DB 状态。",
        "多设备协同 redo 属于 Stage 4+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-22 | redo | C2-18, C2-07 | redo action | undo_actions / redo stack",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "sequence<RedoActionRecord> list_redo_actions(string repo_path);",
        "RedoActionResult redo_action(string repo_path, string action_id);",
        "dictionary RedoActionRecord",
        "RedoActionStatus status;",
        "boolean can_redo;",
        "string source_undo_action_id;",
        "dictionary RedoActionResult",
        "sequence<string> refresh_targets;",
        "string? undo_token;",
        "enum RedoActionStatus { \"Available\", \"Cleared\", \"Blocked\", \"Expired\", \"Executed\" };",
        "ExpiredAction(string action_id);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_redo_actions(repo)` | redo | √ | Db / Io |",
        "| `redo_action(repo, action_id)` | redo | √ | Conflict / FileNotFound / ExpiredAction / PermissionDenied / Db / Io |",
        "### `list_redo_actions(repoPath) throws -> [RedoActionRecord]`",
        "### `redo_action(repoPath, actionId) throws -> RedoActionResult`",
        "`Available`、`Cleared`、`Blocked`、`Expired`、`Executed`",
        "`source_undo_action_id`",
        "`undo_token`",
        "`redo_actions`",
        "多设备协同 redo 不属于 Stage 2",
        "本合同不新增 control map 之外",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn redo_action_log_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "S2-22 可以从列表合同得到 redo 可用性",
        "S2-22 可以从执行结果得到成功/失败摘要",
        "`Shift+Cmd+Z`",
        "独立 Redo 页面、独立 panel 或其他页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "C2-18 redo action log contract types and entry points.",
        "RedoActionRecord",
        "RedoActionResult",
        "list_redo_actions",
        "redo_action",
        "Listing is metadata-only",
        "must not execute redo",
        "Failed redo must preserve",
        "must not mark unfinished redo as executed",
    ] {
        assert_contains(REDO_RS, fragment);
    }

    for fragment in [
        "pub fn list_redo_actions(",
        "redo::list_redo_actions",
        "pub fn redo_action(",
        "redo::redo_action",
        "S2-22",
        "C2-18",
        "standalone Redo page",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in [
        "Conflict",
        "FileNotFound",
        "PermissionDenied",
        "ExpiredAction",
        "Db",
        "Io",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
