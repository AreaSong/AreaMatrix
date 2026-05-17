use std::{fs, path::Path};

use area_matrix_core::{
    batch_move_to_category, get_file, list_changes, list_files, list_tree_json, list_undo_actions,
    preview_batch_move_to_category, BatchCategoryChangeReport, BatchCategoryPreviewReport,
    BatchCategoryPreviewStatus, BatchCategoryResultStatus, ChangeFilter, CoreResult, FileFilter,
    StorageMode, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::params;
use serde_json::Value;

#[path = "support/batch_category_failure.rs"]
mod batch_category_support;

use batch_category_support::{
    assert_classify_error, assert_conflict_error, assert_file_not_found, change_log_rows, file_row,
    initialized_repo, insert_indexed_file, insert_repo_owned_file,
    install_batch_category_change_log_failure, open_db, path_string, snapshot, undo_action_rows,
    user_visible_paths,
};

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-08-batch-change-category.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const BATCH_CATEGORY_RS: &str = include_str!("../src/batch_category.rs");
const BATCH_CATEGORY_APPLY_RS: &str = include_str!("../src/batch_category/apply.rs");
const BATCH_CATEGORY_PLAN_RS: &str = include_str!("../src/batch_category/plan.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

fn category_filter(category: &str) -> FileFilter {
    FileFilter {
        category: Some(category.to_owned()),
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn moved_change_filter(category: &str) -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: Some(category.to_owned()),
        action: Some("moved".to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn list_paths(repo: &Path, category: &str) -> Vec<String> {
    let mut paths: Vec<String> = list_files(path_string(repo), category_filter(category))
        .expect("list files by category through Core API")
        .into_iter()
        .map(|entry| entry.path)
        .collect();
    paths.sort();
    paths
}

fn moved_change_details(repo: &Path, category: &str) -> Vec<Value> {
    list_changes(path_string(repo), moved_change_filter(category))
        .expect("list moved changes through Core API")
        .into_iter()
        .map(|entry| serde_json::from_str(&entry.detail_json).expect("change detail is JSON"))
        .collect()
}

fn parse_tree(repo: &Path) -> Value {
    let tree_json =
        list_tree_json(path_string(repo), "en".to_owned()).expect("list repository tree JSON");
    serde_json::from_str(&tree_json).expect("tree JSON is parseable")
}

fn child_by_slug<'a>(node: &'a Value, slug: &str) -> &'a Value {
    node["children"]
        .as_array()
        .expect("tree children array")
        .iter()
        .find(|child| child["slug"] == slug)
        .unwrap_or_else(|| panic!("expected tree child `{slug}`"))
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn batch_change_category_validation_success_is_visible_to_ui_consumers() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let existing_id = insert_repo_owned_file(
        repo.path(),
        "docs/same.pdf",
        "docs",
        StorageMode::Copied,
        "active",
    );
    let moving_id = insert_repo_owned_file(
        repo.path(),
        "finance/same.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("indexed.pdf");
    fs::write(&external, b"indexed source").expect("write indexed source");
    let indexed_id = insert_indexed_file(repo.path(), &external, "finance");
    let before_preview = snapshot(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![moving_id, indexed_id, existing_id, moving_id],
        "docs".to_owned(),
        true,
    )
    .expect("preview batch category change");

    assert_eq!(snapshot(repo.path()), before_preview);
    assert!(preview.can_apply);
    assert_eq!(preview.requested_file_count, 3);
    assert_eq!(preview.will_move_count, 1);
    assert_eq!(preview.metadata_only_count, 1);
    assert_eq!(preview.unchanged_count, 1);
    assert_eq!(preview.blocked_count, 0);
    assert_eq!(
        preview.items[0].status,
        BatchCategoryPreviewStatus::WillMove
    );
    assert_eq!(
        preview.items[0].target_path.as_deref(),
        Some("docs/same_1.pdf")
    );
    assert_eq!(
        preview.items[1].status,
        BatchCategoryPreviewStatus::MetadataOnly
    );
    assert!(!repo.path().join("docs/same_1.pdf").exists());

    let report = apply_preview(
        repo.path(),
        vec![moving_id, indexed_id, existing_id],
        preview,
    );

    assert_eq!(report.moved_count, 1);
    assert_eq!(report.metadata_only_count, 1);
    assert_eq!(report.unchanged_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.updated_files.len(), 2);
    assert_eq!(
        report.item_results[0].status,
        BatchCategoryResultStatus::Moved
    );
    assert_eq!(
        report.item_results[1].status,
        BatchCategoryResultStatus::MetadataUpdated
    );
    assert_ui_visible_success_state(repo.path(), moving_id, indexed_id, &external);
    assert_pending_undo_action(repo.path(), report.undo_token.as_deref());
}

#[test]
fn batch_change_category_validation_partial_failure_and_skips_are_explicit() {
    let repo = initialized_repo();
    let first_id = insert_repo_owned_file(
        repo.path(),
        "finance/first.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let second_id = insert_repo_owned_file(
        repo.path(),
        "finance/second.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let deleted_id = insert_repo_owned_file(
        repo.path(),
        "finance/deleted.pdf",
        "finance",
        StorageMode::Copied,
        "deleted",
    );
    install_batch_category_change_log_failure(repo.path(), Some(second_id));
    let before_paths = user_visible_paths(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![first_id, second_id, deleted_id, 404],
        "docs".to_owned(),
        false,
    )
    .expect("preview partial batch category change");
    assert!(preview.can_apply);
    assert_eq!(preview.metadata_only_count, 2);
    assert_eq!(preview.skipped_count, 2);
    assert_eq!(
        preview
            .items
            .iter()
            .map(|item| (item.file_id, item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            (first_id, BatchCategoryPreviewStatus::MetadataOnly),
            (second_id, BatchCategoryPreviewStatus::MetadataOnly),
            (deleted_id, BatchCategoryPreviewStatus::Skipped),
            (404, BatchCategoryPreviewStatus::Skipped),
        ]
    );

    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![first_id, second_id, deleted_id, 404],
        "docs".to_owned(),
        false,
        preview.preview_token,
    )
    .expect("partial failure returns an execution report");

    assert_eq!(report.metadata_only_count, 1);
    assert_eq!(report.skipped_count, 2);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[1].status,
        BatchCategoryResultStatus::Failed
    );
    assert!(report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has error")
        .contains("Db"));
    assert_eq!(file_row(repo.path(), first_id).2, "docs");
    assert_eq!(file_row(repo.path(), second_id).2, "finance");
    assert_eq!(file_row(repo.path(), deleted_id).3, "deleted");
    assert_eq!(change_log_rows(repo.path()).len(), 1);
    assert_eq!(undo_action_rows(repo.path()).len(), 1);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_change_category_validation_failure_paths_do_not_mutate_state() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let before = snapshot(repo.path());

    assert_file_not_found(preview_batch_move_to_category(
        path_string(repo.path()),
        Vec::new(),
        "docs".to_owned(),
        true,
    ));
    assert_classify_error(preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "bad/category".to_owned(),
        true,
    ));
    assert_conflict_error(batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
        String::new(),
    ));
    assert_eq!(snapshot(repo.path()), before);

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    )
    .expect("preview before stale-state mutation");
    open_db(repo.path())
        .execute(
            "UPDATE files SET updated_at = updated_at + 1 WHERE id = ?1",
            params![file_id],
        )
        .expect("simulate external metadata change");
    let after_external_change = snapshot(repo.path());

    assert_conflict_error(batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    ));
    assert_eq!(snapshot(repo.path()), after_external_change);
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
}

#[test]
fn batch_change_category_validation_locks_core_api_udl_and_rust_alignment() {
    fn assert_preview(
        _: fn(String, Vec<i64>, String, bool) -> CoreResult<BatchCategoryPreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(String, Vec<i64>, String, bool, String) -> CoreResult<BatchCategoryChangeReport>,
    ) {
    }
    assert_preview(preview_batch_move_to_category);
    assert_apply(batch_move_to_category);

    for fragment in [
        "# C2-08 batch-change-category",
        "`preview_batch_move_to_category(repo_path, file_ids, target_category, move_repo_owned_files) -> BatchCategoryPreviewReport`",
        "`batch_move_to_category(repo_path, file_ids, target_category, move_repo_owned_files, preview_token) -> BatchCategoryChangeReport`",
        "预览报告、执行报告、undo token。",
        "批量更新 `files.category/path`。",
        "Index-only 不移动源文件。",
        "部分失败有摘要，不静默跳过。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-12 | batch-change-category | C2-08, C2-07 | preview + batch move",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "BatchCategoryPreviewReport preview_batch_move_to_category(",
        "sequence<i64> file_ids",
        "string target_category",
        "boolean move_repo_owned_files",
        "BatchCategoryChangeReport batch_move_to_category(",
        "string preview_token",
        "dictionary BatchCategoryPreviewReport",
        "sequence<CategoryDistributionItem> category_distribution;",
        "dictionary BatchCategoryChangeReport",
        "sequence<FileEntry> updated_files;",
        "string? undo_token;",
        "enum BatchCategoryPreviewStatus { \"WillMove\", \"MetadataOnly\", \"Unchanged\", \"Skipped\", \"Blocked\" };",
        "enum BatchCategoryResultStatus { \"Moved\", \"MetadataUpdated\", \"Unchanged\", \"Skipped\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn preview_batch_move_to_category(",
        "batch_category::preview_batch_move_to_category",
        "pub fn batch_move_to_category(",
        "batch_category::batch_move_to_category",
        "not create new categories",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "preview_token",
        "stale batch category preview",
        "build_batch_category_plan",
        "apply_batch_category_plan",
    ] {
        assert_contains(BATCH_CATEGORY_RS, fragment);
    }

    for fragment in [
        "with_batch_category_transaction",
        "savepoint",
        "insert_batch_category_undo_action_in_tx",
        "BatchCategoryResultStatus::Failed",
    ] {
        assert_contains(BATCH_CATEGORY_APPLY_RS, fragment);
    }

    for fragment in [
        "BatchCategoryPreviewStatus::Skipped",
        "BatchCategoryPreviewStatus::Blocked",
        "category_distribution",
        "apply_blocked_reason",
    ] {
        assert_contains(BATCH_CATEGORY_PLAN_RS, fragment);
    }

    for fragment in [
        "pub use batch_category::{",
        "preview_batch_move_to_category",
        "batch_move_to_category",
        "BatchCategoryChangeReport",
        "BatchCategoryPreviewStatus",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "集成测试目录",
        "`core/tests/`",
        "关键测试场景",
        "跨分类移动",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn apply_preview(
    repo: &Path,
    file_ids: Vec<i64>,
    preview: BatchCategoryPreviewReport,
) -> BatchCategoryChangeReport {
    batch_move_to_category(
        path_string(repo),
        file_ids,
        preview.target_category,
        preview.move_repo_owned_files,
        preview.preview_token,
    )
    .expect("apply batch category preview")
}

fn assert_ui_visible_success_state(repo: &Path, moving_id: i64, indexed_id: i64, external: &Path) {
    assert_eq!(
        get_file(path_string(repo), moving_id)
            .expect("get moved file")
            .path,
        "docs/same_1.pdf"
    );
    assert_eq!(
        get_file(path_string(repo), indexed_id)
            .expect("get indexed file")
            .category,
        "docs"
    );
    assert_eq!(
        list_paths(repo, "docs"),
        vec![
            path_string(external),
            "docs/same.pdf".to_owned(),
            "docs/same_1.pdf".to_owned(),
        ]
    );
    let tree = parse_tree(repo);
    assert_eq!(child_by_slug(&tree, "docs")["file_count"], 2);
    assert_eq!(
        fs::read(repo.join("docs/same_1.pdf")).expect("read moved file"),
        b"fixture bytes for finance/same.pdf"
    );
    assert_eq!(
        fs::read(external).expect("read indexed external source"),
        b"indexed source"
    );
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read user README"),
        "user readme\n"
    );

    let details = moved_change_details(repo, "docs");
    assert_eq!(details.len(), 2);
    assert!(details
        .iter()
        .all(|detail| detail["kind"] == "batch_change_category"));
    assert!(details
        .iter()
        .any(|detail| detail["index_only"] == Value::Bool(false)));
    assert!(details
        .iter()
        .any(|detail| detail["index_only"] == Value::Bool(true)));
}

fn assert_pending_undo_action(repo: &Path, undo_token: Option<&str>) {
    let token = undo_token.expect("successful writes return undo token");
    assert!(token.starts_with("undo:batch-category:"));
    let actions = list_undo_actions(path_string(repo)).expect("list undo actions");
    let action = actions
        .iter()
        .find(|action| action.action_id == token)
        .expect("batch category undo action is listed");
    assert_eq!(action.kind, "batch_change_category");
    assert_eq!(action.status, UndoActionStatus::Pending);
    assert!(action.can_undo);
    assert_eq!(action.affected_count, 2);
}
