use std::{fs, path::Path};

use area_matrix_core::{
    batch_delete_to_trash, list_changes, list_files, list_undo_actions, preview_batch_delete,
    BatchDeleteMode, BatchDeletePreviewReport, BatchDeletePreviewStatus, BatchDeleteReport,
    BatchDeleteResultStatus, ChangeFilter, CoreError, CoreResult, FileFilter, StorageMode,
    UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

mod support;

use support::{
    batch_delete_validation::{
        file_status, import_fixture, initialized_repo, insert_indexed_file,
        install_removed_from_index_log_failure, open_db, path_string, snapshot, source_file,
    },
    system_trash_home::with_test_system_trash,
};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-09-batch-delete-trash.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const BATCH_DELETE_RS: &str = include_str!("../src/batch_delete.rs");
const BATCH_DELETE_APPLY_RS: &str = include_str!("../src/batch_delete/apply.rs");
const BATCH_DELETE_INSPECT_RS: &str = include_str!("../src/batch_delete/inspect.rs");
const BATCH_DELETE_PLAN_RS: &str = include_str!("../src/batch_delete/plan.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

fn finance_filter() -> FileFilter {
    FileFilter {
        category: Some("finance".to_owned()),
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn change_filter(action: &str) -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: Some(action.to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

#[test]
fn batch_delete_trash_validation_success_is_visible_to_ui_consumers() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
        let first = import_fixture(
            repo.path(),
            "first.pdf",
            b"first bytes",
            StorageMode::Copied,
        );
        let second = import_fixture(
            repo.path(),
            "second.pdf",
            b"second bytes",
            StorageMode::Moved,
        );
        let before_preview = snapshot(repo.path());

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![first.id, second.id, first.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview batch delete");

        assert_eq!(snapshot(repo.path()), before_preview);
        assert_valid_trash_preview(&preview);
        let report = apply_preview(repo.path(), vec![first.id, second.id], preview);
        assert_success_report(&report, &[first.id, second.id]);
        assert_files_moved_to_test_trash(repo.path(), trash_dir, &first.path, &second.path);
        assert_ui_consumers_see_delete_and_undo(repo.path(), report.undo_token.as_deref());
    });
}

#[test]
fn batch_delete_trash_validation_partial_failure_and_skips_are_explicit() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_first_root, first_source) = source_file("first-indexed.pdf", b"first indexed");
        let (_second_root, second_source) = source_file("second-indexed.pdf", b"second indexed");
        let first_id = insert_indexed_file(repo.path(), &first_source, "finance");
        let second_id = insert_indexed_file(repo.path(), &second_source, "finance");
        let repo_owned = import_fixture(
            repo.path(),
            "repo-owned.pdf",
            b"repo-owned",
            StorageMode::Copied,
        );
        install_removed_from_index_log_failure(repo.path(), second_id);

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![first_id, second_id, repo_owned.id],
            BatchDeleteMode::RemoveFromIndex,
        )
        .expect("preview mixed index removal");
        assert_eq!(preview.index_only_count, 2);
        assert_eq!(preview.skipped_count, 1);

        let report = batch_delete_to_trash(
            path_string(repo.path()),
            vec![first_id, second_id, repo_owned.id],
            BatchDeleteMode::RemoveFromIndex,
            preview.preview_token,
        )
        .expect("partial failure returns report");

        assert_partial_index_report(&report);
        assert_eq!(file_status(repo.path(), first_id), "deleted");
        assert_eq!(file_status(repo.path(), second_id), "active");
        assert_eq!(file_status(repo.path(), repo_owned.id), "active");
        assert_eq!(
            fs::read(&first_source).expect("read first source"),
            b"first indexed"
        );
        assert_eq!(
            fs::read(&second_source).expect("read second source"),
            b"second indexed"
        );
        assert_eq!(fs::read_dir(trash_dir).expect("read trash").count(), 0);
    });
}

#[test]
fn batch_delete_trash_validation_failure_paths_do_not_mutate_state() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let entry = import_fixture(
            repo.path(),
            "stale.pdf",
            b"stale bytes",
            StorageMode::Copied,
        );
        let before_invalid = snapshot(repo.path());
        assert!(matches!(
            preview_batch_delete(
                path_string(repo.path()),
                Vec::new(),
                BatchDeleteMode::MoveToTrash
            ),
            Err(CoreError::FileNotFound { .. })
        ));
        assert!(matches!(
            batch_delete_to_trash(
                path_string(repo.path()),
                vec![entry.id],
                BatchDeleteMode::MoveToTrash,
                String::new()
            ),
            Err(CoreError::Conflict { .. })
        ));
        assert_eq!(snapshot(repo.path()), before_invalid);

        let preview = preview_single(repo.path(), entry.id);
        open_db(repo.path())
            .execute(
                "UPDATE files SET updated_at = updated_at + 1 WHERE id = ?1",
                params![entry.id],
            )
            .expect("simulate metadata drift after preview");
        let after_external_change = snapshot(repo.path());
        assert!(matches!(
            apply_preview_expect_error(repo.path(), entry.id, preview),
            CoreError::Conflict { .. }
        ));
        assert_eq!(snapshot(repo.path()), after_external_change);
        assert!(repo.path().join(&entry.path).exists());
        assert_eq!(fs::read_dir(trash_dir).expect("read trash").count(), 0);
    });
}

#[test]
fn batch_delete_trash_validation_locks_core_api_udl_and_rust_alignment() {
    fn assert_preview(
        _: fn(String, Vec<i64>, BatchDeleteMode) -> CoreResult<BatchDeletePreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(String, Vec<i64>, BatchDeleteMode, String) -> CoreResult<BatchDeleteReport>,
    ) {
    }
    assert_preview(preview_batch_delete);
    assert_apply(batch_delete_to_trash);

    for fragment in [
        "# C2-09 batch-delete-trash",
        "计划新增：`preview_batch_delete`、`batch_delete_to_trash`",
        "预览报告、执行报告、undo token。",
        "Copy / Move 文件进入 Trash。",
        "Indexed / Missing 条目只移除索引。",
        "失败项不被当作成功删除。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    for fragment in [
        "| S2-13 | batch-delete-confirm | C2-09, C2-07 | preview + Trash delete",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
    for fragment in [
        "BatchDeletePreviewReport preview_batch_delete(",
        "BatchDeleteReport batch_delete_to_trash(",
        "dictionary BatchDeletePreviewReport",
        "dictionary BatchDeleteReport",
        "enum BatchDeleteMode { \"MoveToTrash\", \"RemoveFromIndex\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    assert_rust_surface_fragments();
}

fn apply_preview(
    repo: &Path,
    file_ids: Vec<i64>,
    preview: BatchDeletePreviewReport,
) -> BatchDeleteReport {
    batch_delete_to_trash(
        path_string(repo),
        file_ids,
        preview.delete_mode,
        preview.preview_token,
    )
    .expect("apply batch delete preview")
}

fn preview_single(repo: &Path, file_id: i64) -> BatchDeletePreviewReport {
    preview_batch_delete(
        path_string(repo),
        vec![file_id],
        BatchDeleteMode::MoveToTrash,
    )
    .expect("preview single batch delete")
}

fn apply_preview_expect_error(
    repo: &Path,
    file_id: i64,
    preview: BatchDeletePreviewReport,
) -> CoreError {
    batch_delete_to_trash(
        path_string(repo),
        vec![file_id],
        preview.delete_mode,
        preview.preview_token,
    )
    .expect_err("apply should fail")
}

fn assert_valid_trash_preview(preview: &BatchDeletePreviewReport) {
    assert!(preview.can_apply);
    assert!(preview.trash_available);
    assert!(preview.undo_available);
    assert_eq!(preview.requested_file_count, 2);
    assert_eq!(preview.will_trash_count, 2);
    assert_eq!(preview.index_only_count, 0);
    assert_eq!(preview.blocked_count, 0);
    assert!(preview.preview_token.starts_with("preview:batch-delete:"));
    assert!(preview
        .items
        .iter()
        .all(|item| item.status == BatchDeletePreviewStatus::WillMoveToTrash));
}

fn assert_success_report(report: &BatchDeleteReport, expected_ids: &[i64]) {
    assert_eq!(report.requested_file_count, expected_ids.len() as i64);
    assert_eq!(report.moved_to_trash_count, expected_ids.len() as i64);
    assert_eq!(report.removed_from_index_count, 0);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.affected_file_ids, expected_ids);
    assert!(report.undo_token.is_some());
    assert!(report
        .item_results
        .iter()
        .all(|item| item.status == BatchDeleteResultStatus::MovedToTrash));
}

fn assert_files_moved_to_test_trash(repo: &Path, trash_dir: &Path, first: &str, second: &str) {
    assert!(!repo.join(first).exists());
    assert!(!repo.join(second).exists());
    assert_eq!(
        fs::read(trash_dir.join("first.pdf")).expect("read first trash file"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(trash_dir.join("second.pdf")).expect("read second trash file"),
        b"second bytes"
    );
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read user README"),
        "user readme\n"
    );
}

fn assert_ui_consumers_see_delete_and_undo(repo: &Path, undo_token: Option<&str>) {
    let active_files = list_files(path_string(repo), finance_filter()).expect("list active files");
    assert_eq!(active_files.len(), 0);
    let deleted_changes =
        list_changes(path_string(repo), change_filter("deleted")).expect("list deleted changes");
    assert_eq!(deleted_changes.len(), 2);
    let undo_token = undo_token.expect("successful trash delete returns undo token");
    let actions = list_undo_actions(path_string(repo)).expect("list undo actions");
    let action = actions
        .iter()
        .find(|action| action.action_id == undo_token)
        .expect("undo action is visible to C2-07 consumers");
    assert_eq!(action.kind, "trash_delete");
    assert_eq!(action.summary, "Moved 2 files to Trash.");
    assert_eq!(action.status, UndoActionStatus::Pending);
    assert!(action.can_undo);
}

fn assert_partial_index_report(report: &BatchDeleteReport) {
    assert_eq!(report.moved_to_trash_count, 0);
    assert_eq!(report.removed_from_index_count, 1);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 1);
    assert_eq!(report.undo_token, None);
    assert!(report
        .item_results
        .iter()
        .any(|item| item.status == BatchDeleteResultStatus::RemovedFromIndex));
    assert!(report
        .item_results
        .iter()
        .any(|item| item.status == BatchDeleteResultStatus::Skipped));
    assert!(report
        .item_results
        .iter()
        .any(|item| item.status == BatchDeleteResultStatus::Failed));
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_rust_surface_fragments() {
    for fragment in [
        "pub use batch_delete::{",
        "preview_batch_delete",
        "batch_delete_to_trash",
        "BatchDeletePreviewReport",
        "BatchDeleteResultStatus",
    ] {
        assert_contains(LIB_RS, fragment);
    }
    for fragment in [
        "side-effect free",
        "not touch external source files",
        "stale batch delete preview",
        "normalize_batch_delete_file_ids",
    ] {
        assert_contains(BATCH_DELETE_RS, fragment);
    }
    for fragment in [
        "pub fn preview_batch_delete(",
        "batch_delete::preview_batch_delete",
        "pub fn batch_delete_to_trash(",
        "batch_delete::batch_delete_to_trash",
        "S2-13",
        "C2-09",
        "permanent deletion",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "insert_batch_undo",
        "rollback_after_undo_failure",
        "BatchDeleteResultStatus::Failed",
        "move_to_user_trash",
    ] {
        assert_contains(BATCH_DELETE_APPLY_RS, fragment);
    }
    for fragment in [
        "preview_trash_available",
        "BatchDeletePreviewStatus::Blocked",
        "apply_blocked_reason",
    ] {
        assert_contains(BATCH_DELETE_PLAN_RS, fragment);
    }
    assert_contains(BATCH_DELETE_INSPECT_RS, "content_sha256");
    for fragment in ["集成测试目录", "`core/tests/`", "删除（软 / 硬）+ 废纸篓"] {
        assert_contains(TESTING_DOC, fragment);
    }
}
