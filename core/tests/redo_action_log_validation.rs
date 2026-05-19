use std::{fs, path::Path};

use area_matrix_core::{
    batch_add_tags, delete_file, list_redo_actions, redo_action, rename_file, undo_action,
    CoreResult, ErrorKind, ErrorRecoverability, RedoActionRecord, RedoActionResult,
    RedoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

mod support;

use support::{
    redo_failure::{
        assert_error_mapping, change_rows, drop_trigger, initialized_repo, insert_file,
        install_redo_tag_change_failure, open_db, path_string, snapshot, tag_rows, undo_status,
    },
    system_trash_home::with_test_system_trash,
};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-18-redo-action-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const REDO_RS: &str = include_str!("../src/redo.rs");
const DB_REDO_RS: &str = include_str!("../src/db/redo.rs");
const REDO_RECORDS_RS: &str = include_str!("../src/db/redo/records.rs");
const REDO_TAGS_RS: &str = include_str!("../src/db/redo/tags.rs");
const REDO_FILE_ACTIONS_RS: &str = include_str!("../src/db/redo/file_actions.rs");
const REDO_BATCH_FILE_ACTIONS_RS: &str = include_str!("../src/db/redo/batch_file_actions.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_all_contains(haystack: &str, needles: &[&str]) {
    for needle in needles {
        assert_contains(haystack, needle);
    }
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, status FROM files WHERE id = ?1",
            params![file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read file row")
}

fn change_detail_kinds(repo: &Path) -> Vec<String> {
    change_rows(repo)
        .into_iter()
        .map(|(_, _, detail)| {
            let value: serde_json::Value =
                serde_json::from_str(&detail).expect("change detail json is valid");
            value["kind"].as_str().unwrap_or_default().to_owned()
        })
        .collect()
}

fn latest_undo_action_id(repo: &Path, kind: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT token
               FROM undo_actions
              WHERE kind = ?1
              ORDER BY created_at DESC, token DESC
              LIMIT 1",
            params![kind],
            |row| row.get(0),
        )
        .expect("read latest undo action id by kind")
}

fn assert_redo_signatures() {
    fn assert_list(_: fn(String) -> CoreResult<Vec<RedoActionRecord>>) {}
    fn assert_redo(_: fn(String, String) -> CoreResult<RedoActionResult>) {}
    assert_list(list_redo_actions);
    assert_redo(redo_action);
}

fn assert_capability_and_control_map_alignment() {
    assert_all_contains(
        CAPABILITY_SPEC,
        &[
            "# C2-18 redo-action-log",
            "- S2-22 redo",
            "`list_redo_actions`",
            "`redo_action(repo_path, action_id)`",
            "Redo 可用性、执行结果、刷新建议和失败原因。",
            "只有 AreaMatrix 成功 Undo 的动作可以 Redo。",
            "新写操作会清空 redo stack。",
            "Redo 失败不破坏当前文件系统和 DB 状态。",
        ],
    );

    assert_all_contains(
        CONTROL_MAP,
        &[
            "| S2-22 | redo | C2-18, C2-07 | redo action | undo_actions / redo stack",
            "批量操作必须有 preview、确认、执行报告和 undo/action log。",
        ],
    );
}

fn assert_api_udl_and_rust_surface_alignment() {
    for fragment in [
        "sequence<RedoActionRecord> list_redo_actions(string repo_path);",
        "RedoActionResult redo_action(string repo_path, string action_id);",
        "dictionary RedoActionRecord",
        "RedoActionStatus status;",
        "boolean can_redo;",
        "string? disabled_reason;",
        "string source_undo_action_id;",
        "dictionary RedoActionResult",
        "sequence<string> refresh_targets;",
        "string? undo_token;",
        "enum RedoActionStatus { \"Available\", \"Cleared\", \"Blocked\", \"Expired\", \"Executed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_all_contains(
        LIB_RS,
        &[
            "pub use redo::{",
            "list_redo_actions",
            "redo_action",
            "RedoActionRecord",
            "RedoActionResult",
            "RedoActionStatus",
        ],
    );
    assert_all_contains(
        API_RS,
        &[
            "pub fn list_redo_actions(",
            "redo::list_redo_actions",
            "pub fn redo_action(",
            "redo::redo_action",
            "S2-22",
            "C2-18",
            "standalone Redo page",
        ],
    );
    assert_all_contains(
        REDO_RS,
        &[
            "pub fn list_redo_actions(",
            "pub fn redo_action(",
            "Listing is metadata-only",
            "Failed redo must preserve",
            "must not mark unfinished redo as executed",
        ],
    );
}

fn create_batch_tag_redo(repo: &Path) -> (String, i64, i64) {
    let first_id = insert_file(repo, "docs/spec.pdf", "docs");
    let second_id = insert_file(repo, "docs/plan.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo),
        vec![first_id, second_id],
        vec!["Urgent".to_owned()],
    )
    .expect("create undoable batch tag action");
    let token = report.undo_token.expect("batch tags create undo token");
    undo_action(path_string(repo), token.clone()).expect("undo batch tags to create redo stack");
    (token, first_id, second_id)
}

fn assert_available_batch_tag_redo(repo: &Path, token: &str) {
    let actions = list_redo_actions(path_string(repo)).expect("list C2-18 redo actions");
    assert_eq!(actions.len(), 1);
    assert_eq!(actions[0].action_id, token);
    assert_eq!(actions[0].source_undo_action_id, token);
    assert_eq!(actions[0].kind, "batch_add_tags");
    assert_eq!(actions[0].summary, "Redo: add 2 tag relation(s).");
    assert_eq!(actions[0].affected_count, 2);
    assert_eq!(actions[0].status, RedoActionStatus::Available);
    assert!(actions[0].can_redo);
    assert_eq!(actions[0].disabled_reason, None);
}

#[test]
fn redo_action_log_validation_locks_core_api_udl_and_rust_alignment() {
    assert_redo_signatures();
    assert_capability_and_control_map_alignment();
    assert_api_udl_and_rust_surface_alignment();
}

#[test]
fn redo_action_log_validation_success_paths_are_ui_ready() {
    let repo = initialized_repo();
    let (tag_token, first_id, second_id) = create_batch_tag_redo(repo.path());

    assert_available_batch_tag_redo(repo.path(), &tag_token);
    assert_eq!(tag_rows(repo.path()), Vec::<(i64, String)>::new());

    let tag_result =
        redo_action(path_string(repo.path()), tag_token.clone()).expect("redo batch tags");

    assert_eq!(tag_result.action_id, tag_token);
    assert_eq!(tag_result.status, RedoActionStatus::Executed);
    assert_eq!(tag_result.affected_count, 2);
    assert_eq!(
        tag_result.refresh_targets,
        vec![
            "files",
            "tags",
            "undo_actions",
            "redo_actions",
            "change_log"
        ]
    );
    assert_eq!(
        tag_result.undo_token.as_deref(),
        Some(tag_result.action_id.as_str())
    );
    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (first_id, "urgent".to_owned()),
            (second_id, "urgent".to_owned())
        ]
    );
    assert_eq!(undo_status(repo.path(), tag_result.action_id.as_str()), "pending");
    assert!(list_redo_actions(path_string(repo.path()))
        .expect("list redo after execution")
        .is_empty());
    assert!(change_detail_kinds(repo.path())
        .iter()
        .any(|kind| kind == "redo_batch_tag_added"));

    let renamed_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), renamed_id, "final.pdf".to_owned())
        .expect("create rename action");
    let rename_token = latest_undo_action_id(repo.path(), "rename_files");
    undo_action(path_string(repo.path()), rename_token.clone()).expect("undo rename");
    let rename_result =
        redo_action(path_string(repo.path()), rename_token.clone()).expect("redo rename");

    assert_eq!(rename_result.status, RedoActionStatus::Executed);
    assert_eq!(
        file_row(repo.path(), renamed_id),
        (
            "docs/final.pdf".to_owned(),
            "final.pdf".to_owned(),
            "docs".to_owned(),
            "active".to_owned(),
        )
    );
    assert!(rename_result
        .refresh_targets
        .iter()
        .any(|target| target == "selection"));
    assert_eq!(undo_status(repo.path(), &rename_token), "pending");
}

#[test]
fn redo_action_log_validation_cleared_and_blocked_paths_do_not_mutate_state() {
    let repo = initialized_repo();
    let (cleared_token, _, _) = create_batch_tag_redo(repo.path());
    let new_write_id = insert_file(repo.path(), "docs/new-write.pdf", "docs");
    batch_add_tags(
        path_string(repo.path()),
        vec![new_write_id],
        vec!["Later".to_owned()],
    )
    .expect("new write clears redo stack");
    let cleared_before = snapshot(repo.path());

    let cleared_actions = list_redo_actions(path_string(repo.path())).expect("list cleared redo");
    let cleared = cleared_actions
        .iter()
        .find(|action| action.action_id == cleared_token)
        .expect("cleared redo action remains visible");
    assert_eq!(cleared.status, RedoActionStatus::Cleared);
    assert!(!cleared.can_redo);
    assert_eq!(
        cleared.disabled_reason.as_deref(),
        Some("Redo action was cleared by a new write")
    );
    let cleared_error = redo_action(path_string(repo.path()), cleared_token)
        .expect_err("cleared redo cannot execute");
    assert_error_mapping(
        &cleared_error,
        ErrorKind::ExpiredAction,
        ErrorRecoverability::RefreshRequired,
    );
    assert_eq!(snapshot(repo.path()), cleared_before);

    let blocked_id = insert_file(repo.path(), "docs/source.pdf", "docs");
    rename_file(path_string(repo.path()), blocked_id, "target.pdf".to_owned())
        .expect("create rename action");
    let blocked_token = latest_undo_action_id(repo.path(), "rename_files");
    undo_action(path_string(repo.path()), blocked_token.clone()).expect("undo rename");
    fs::write(repo.path().join("docs/target.pdf"), b"external conflict")
        .expect("create external redo destination conflict");
    let blocked_before = snapshot(repo.path());

    let blocked_actions = list_redo_actions(path_string(repo.path())).expect("list blocked redo");
    let blocked = blocked_actions
        .iter()
        .find(|action| action.action_id == blocked_token)
        .expect("blocked redo action is listed");
    assert_eq!(blocked.status, RedoActionStatus::Blocked);
    assert!(!blocked.can_redo);
    assert_eq!(
        blocked.disabled_reason.as_deref(),
        Some("Redo destination is occupied")
    );
    let blocked_error = redo_action(path_string(repo.path()), blocked_token.clone())
        .expect_err("external destination conflict blocks redo");
    assert_error_mapping(
        &blocked_error,
        ErrorKind::Conflict,
        ErrorRecoverability::UserActionRequired,
    );
    assert_eq!(undo_status(repo.path(), &blocked_token), "executed");
    assert_eq!(snapshot(repo.path()), blocked_before);
}

#[test]
fn redo_action_log_validation_rollback_and_trash_paths_are_safe() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let tag_id = insert_file(repo.path(), "docs/tagged.pdf", "docs");
        let report = batch_add_tags(
            path_string(repo.path()),
            vec![tag_id],
            vec!["urgent".to_owned()],
        )
        .expect("create tag action");
        let tag_token = report.undo_token.expect("tag undo token");
        undo_action(path_string(repo.path()), tag_token.clone()).expect("undo tag action");
        let before_failed_redo = snapshot(repo.path());
        install_redo_tag_change_failure(repo.path());

        let error = redo_action(path_string(repo.path()), tag_token.clone())
            .expect_err("redo change-log failure rolls back tag writes");

        assert_error_mapping(
            &error,
            ErrorKind::Db,
            ErrorRecoverability::UserActionRequired,
        );
        assert_eq!(snapshot(repo.path()), before_failed_redo);
        assert_eq!(undo_status(repo.path(), &tag_token), "executed");
        drop_trigger(repo.path(), "fail_redo_tag_change");

        let file_id = insert_file(repo.path(), "docs/trash-me.pdf", "docs");
        delete_file(path_string(repo.path()), file_id).expect("delete file to trash");
        let trash_token = latest_undo_action_id(repo.path(), "trash_delete");
        undo_action(path_string(repo.path()), trash_token.clone()).expect("undo trash delete");

        let result =
            redo_action(path_string(repo.path()), trash_token.clone()).expect("redo trash delete");

        assert_eq!(result.status, RedoActionStatus::Executed);
        assert_eq!(
            file_row(repo.path(), file_id),
            (
                "docs/trash-me.pdf".to_owned(),
                "trash-me.pdf".to_owned(),
                "docs".to_owned(),
                "deleted".to_owned(),
            )
        );
        assert!(!repo.path().join("docs/trash-me.pdf").exists());
        assert!(trash_dir.join("trash-me.pdf").exists());
        assert_eq!(undo_status(repo.path(), &trash_token), "pending");
    });
}

#[test]
fn redo_action_log_validation_locks_persistence_and_testing_evidence() {
    assert_all_contains(
        DB_REDO_RS,
        &[
            "list_redo_action_rows",
            "execute_redo_action_row",
            "clear_redo_stack_in_tx",
            "restore_pending_undo_action",
            "RedoActionStatus::Executed",
        ],
    );
    assert_all_contains(
        REDO_RECORDS_RS,
        &[
            "ensure_redo_metadata_ready",
            "load_redo_actions",
            "load_executed_action",
            "RedoActionStatus::Cleared",
            "disabled_reason",
            "REDO_CLEARED_REASON",
        ],
    );
    assert_all_contains(
        REDO_TAGS_RS,
        &[
            "execute_batch_tag_redo",
            "batch_tag_redo_block_reason",
            "ensure_relations_redoable",
            "redo_batch_tag_added",
        ],
    );
    assert_all_contains(
        REDO_FILE_ACTIONS_RS,
        &[
            "execute_file_redo",
            "file_redo_block_reason",
            "move_redo_active_path",
            "filesystem_redo_block_reason",
            "redo_file_action",
        ],
    );
    assert_all_contains(
        REDO_BATCH_FILE_ACTIONS_RS,
        &[
            "execute_restore_batch_file_state_redo",
            "execute_restore_batch_deleted_files_redo",
            "batch_file_state_redo_block_reason",
            "batch_deleted_files_redo_block_reason",
        ],
    );
    assert_all_contains(
        TESTING_DOC,
        &[
            "集成测试目录",
            "`core/tests/`",
            "关键测试场景",
            "DB / Migration",
            "崩溃测试",
        ],
    );
}
