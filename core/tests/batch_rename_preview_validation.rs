use std::{fs, path::Path};

use area_matrix_core::{
    batch_rename, list_changes, list_files, list_undo_actions, preview_batch_rename,
    BatchRenamePreviewStatus, BatchRenameResultStatus, ChangeFilter, CoreError, CoreResult,
    FileFilter, StorageMode, UndoActionStatus,
};
use pretty_assertions::assert_eq;

#[allow(dead_code)]
#[path = "support/batch_rename_preview.rs"]
mod batch_rename_preview_support;

#[allow(dead_code)]
#[path = "support/batch_rename_failure.rs"]
mod batch_rename_failure_support;

use batch_rename_failure_support::snapshot;
use batch_rename_preview_support::{
    file_row, import_fixture, indexed_file, initialized_repo, path_string, prefix_rule,
};

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-10-batch-rename-preview.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const BATCH_RENAME_RS: &str = include_str!("../src/batch_rename.rs");
const BATCH_RENAME_APPLY_RS: &str = include_str!("../src/batch_rename/apply.rs");
const BATCH_RENAME_PLAN_RS: &str = include_str!("../src/batch_rename/plan.rs");
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

fn renamed_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: Some("renamed".to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn current_names(repo: &Path) -> Vec<String> {
    let mut names: Vec<String> = list_files(path_string(repo), finance_filter())
        .expect("list renamed files through Core API")
        .into_iter()
        .map(|entry| entry.current_name)
        .collect();
    names.sort();
    names
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn batch_rename_validation_success_is_visible_to_ui_consumers() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let repo_owned = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "report-source.pdf",
        b"report bytes",
    );
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("external.pdf");
    fs::write(&external, b"external bytes").expect("write external source");
    let indexed_id = indexed_file(repo.path(), &external, "finance");
    let before_preview = snapshot(repo.path());

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![repo_owned.id, indexed_id, repo_owned.id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview C2-10 batch rename");

    assert_eq!(snapshot(repo.path()), before_preview);
    assert!(preview.can_apply);
    assert_eq!(preview.requested_file_count, 2);
    assert_eq!(preview.will_rename_count, 1);
    assert_eq!(preview.display_only_count, 1);
    assert_eq!(preview.blocked_count, 0);
    assert_eq!(preview.items.len(), 2);
    assert_eq!(preview.items[0].status, BatchRenamePreviewStatus::Ok);
    assert_eq!(
        preview.items[1].status,
        BatchRenamePreviewStatus::DisplayOnly
    );
    assert!(preview.items[1].index_only);
    assert!(!preview.items[1].will_rename_file);
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());

    let report = batch_rename(
        path_string(repo.path()),
        vec![repo_owned.id, indexed_id],
        prefix_rule("ProjectA_"),
        preview.preview_token,
    )
    .expect("apply C2-10 batch rename");

    assert_eq!(report.requested_file_count, 2);
    assert_eq!(report.renamed_count, 1);
    assert_eq!(report.display_name_updated_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.updated_files.len(), 2);
    assert_eq!(
        report.item_results[0].status,
        BatchRenameResultStatus::Renamed
    );
    assert_eq!(
        report.item_results[1].status,
        BatchRenameResultStatus::DisplayNameUpdated
    );
    let undo_token = report.undo_token.expect("batch rename creates undo token");

    assert!(!repo.path().join("finance/report.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/ProjectA_report.pdf")).expect("read renamed file"),
        b"report bytes"
    );
    assert_eq!(
        fs::read(&external).expect("read indexed external source"),
        b"external bytes"
    );
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
        "user readme\n"
    );
    assert_eq!(
        file_row(repo.path(), repo_owned.id),
        (
            "finance/ProjectA_report.pdf".to_owned(),
            "ProjectA_report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert_eq!(
        file_row(repo.path(), indexed_id),
        (
            path_string(&external),
            "ProjectA_external.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert_eq!(
        current_names(repo.path()),
        vec!["ProjectA_external.pdf", "ProjectA_report.pdf"]
    );

    let changes = list_changes(path_string(repo.path()), renamed_filter())
        .expect("list C2-10 rename changes through Core API");
    assert_eq!(changes.len(), 2);
    let undo_actions =
        list_undo_actions(path_string(repo.path())).expect("list C2-07 undo action state");
    let undo_action = undo_actions
        .iter()
        .find(|action| action.action_id == undo_token)
        .expect("find C2-10 undo token");
    assert_eq!(undo_action.kind, "rename_files");
    assert_eq!(undo_action.affected_count, 2);
    assert_eq!(undo_action.status, UndoActionStatus::Pending);
}

#[test]
fn batch_rename_validation_failure_paths_are_explicit_and_side_effect_free() {
    let repo = initialized_repo();
    let existing = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "ProjectA_report.pdf",
        "existing-source.pdf",
        b"existing bytes",
    );
    let repo_owned = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "report-source.pdf",
        b"report bytes",
    );
    let missing_id = repo_owned.id + 1000;
    let before_failures = snapshot(repo.path());

    assert!(matches!(
        preview_batch_rename(path_string(repo.path()), Vec::new(), prefix_rule("ProjectA_")),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_rename(
            path_string(repo.path()),
            vec![repo_owned.id],
            prefix_rule("bad/name")
        ),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        batch_rename(
            path_string(repo.path()),
            vec![repo_owned.id],
            prefix_rule("ProjectA_"),
            String::new()
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert_eq!(snapshot(repo.path()), before_failures);

    let blocked_preview = preview_batch_rename(
        path_string(repo.path()),
        vec![repo_owned.id, existing.id, missing_id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview conflict and missing rows");

    assert_eq!(snapshot(repo.path()), before_failures);
    assert!(!blocked_preview.can_apply);
    assert_eq!(blocked_preview.blocked_count, 2);
    assert_eq!(
        blocked_preview
            .items
            .iter()
            .find(|item| item.file_id == repo_owned.id)
            .expect("repo-owned conflict row")
            .status,
        BatchRenamePreviewStatus::NameConflict
    );
    assert_eq!(
        blocked_preview
            .items
            .iter()
            .find(|item| item.file_id == missing_id)
            .expect("missing row")
            .status,
        BatchRenamePreviewStatus::Missing
    );

    let error = batch_rename(
        path_string(repo.path()),
        vec![repo_owned.id, existing.id, missing_id],
        prefix_rule("ProjectA_"),
        blocked_preview.preview_token,
    )
    .expect_err("blocked preview cannot be applied");

    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(snapshot(repo.path()), before_failures);
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("finance/ProjectA_report_1.pdf").exists());
}

#[test]
fn batch_rename_validation_locks_core_api_udl_and_rust_alignment() {
    fn assert_preview(
        _: fn(
            String,
            Vec<i64>,
            area_matrix_core::BatchRenameRule,
        ) -> CoreResult<area_matrix_core::BatchRenamePreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(
            String,
            Vec<i64>,
            area_matrix_core::BatchRenameRule,
            String,
        ) -> CoreResult<area_matrix_core::BatchRenameReport>,
    ) {
    }
    assert_preview(preview_batch_rename);
    assert_apply(batch_rename);

    for fragment in [
        "# C2-10 batch-rename-preview",
        "- S2-14 batch-rename",
        "- S2-10 undo-toast",
        "计划新增：`preview_batch_rename`、`batch_rename`",
        "old/new name 预览、冲突列表、执行报告。",
        "冲突或非法名称不能静默跳过。",
        "成功后可 undo。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    for fragment in [
        "| S2-14 | batch-rename | C2-10, C2-07 | preview + rename",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
    for fragment in [
        "`core/tests/`",
        "重命名（合法名 / 非法名）",
        "集成测试",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }

    for fragment in [
        "BatchRenamePreviewReport preview_batch_rename(",
        "sequence<i64> file_ids",
        "BatchRenameRule rule",
        "BatchRenameReport batch_rename(",
        "string preview_token",
        "dictionary BatchRenameRule",
        "dictionary BatchRenamePreviewReport",
        "sequence<BatchRenamePreviewItem> items;",
        "sequence<BatchRenameConflict> conflicts;",
        "dictionary BatchRenameReport",
        "sequence<BatchRenameItemResult> item_results;",
        "sequence<FileEntry> updated_files;",
        "enum BatchRenameMode { \"Prefix\", \"DatePrefix\", \"KeepBaseSequence\", \"ReplaceText\" };",
        "enum BatchRenameResultStatus { \"Renamed\", \"DisplayNameUpdated\", \"Unchanged\", \"Skipped\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `preview_batch_rename(repoPath, fileIds, rule) throws -> BatchRenamePreviewReport`",
        "### `batch_rename(repoPath, fileIds, rule, previewToken) throws -> BatchRenameReport`",
        "C2-10 的只读批量重命名预览入口",
        "`preview_batch_rename` 返回的 `preview_token`",
        "不实现 AI 自动命名",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn preview_batch_rename(",
        "batch_rename_mod::preview_batch_rename",
        "pub fn batch_rename(",
        "batch_rename_mod::batch_rename",
        "S2-14",
        "C2-10",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "pub use batch_rename::{",
        "preview_batch_rename",
        "BatchRenamePreviewReport",
        "BatchRenameReport",
    ] {
        assert_contains(LIB_RS, fragment);
    }
    for fragment in [
        "Previews C2-10 batch rename without mutating files or metadata.",
        "Applies a C2-10 batch rename that was previously previewed.",
        "validate_batch_rename_rule",
        "normalize_batch_rename_file_ids",
    ] {
        assert_contains(BATCH_RENAME_RS, fragment);
    }
    for fragment in [
        "build_batch_rename_plan",
        "mark_batch_target_conflicts",
        "ensure_target_available",
    ] {
        assert_contains(BATCH_RENAME_PLAN_RS, fragment);
    }
    for fragment in [
        "apply_batch_rename_plan",
        "insert_batch_rename_undo_action_in_tx",
        "move_checked_file",
        "rollback_filesystem_rename",
    ] {
        assert_contains(BATCH_RENAME_APPLY_RS, fragment);
    }
}
