use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    apply_import_conflict_batch, preview_import_conflict_batch, CoreError,
    ImportConflictBatchApplyRequest, ImportConflictBatchConflictType,
    ImportConflictBatchPreviewRequest, ImportConflictBatchPreviewStatus,
    ImportConflictBatchResultStatus, ImportConflictBatchStrategy,
};
use pretty_assertions::assert_eq;

#[path = "support/import_conflict_batch.rs"]
mod import_conflict_batch_support;

use import_conflict_batch_support::{
    create_conflict_schema, file_status, initialized_repo, insert_active_file, insert_conflict,
    insert_import_session, insert_staging_file, open_db, path_string,
};

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-17-import-conflict-batch.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_RS: &str = include_str!("../src/import_conflict_batch.rs");
const UDL: &str = include_str!("../area_matrix.udl");

#[test]
fn import_conflict_batch_validation_default_preview_then_apply_success() {
    let repo = initialized_conflict_repo();
    let session_id = "validation-defaults";
    insert_import_session(repo.path(), session_id);
    let duplicate_one = duplicate_fixture(repo.path(), session_id, "dup-1", "staged-dup-1");
    let duplicate_two = duplicate_fixture(repo.path(), session_id, "dup-2", "staged-dup-2");
    let named = same_name_fixture(repo.path(), session_id, "name-1", "staged-report");
    let request = safe_default_request(session_id, &["dup-1", "name-1"], true);

    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview safe default import conflict batch");

    assert!(preview.can_apply);
    assert_eq!(preview.included_count, 3);
    assert_eq!(preview.duplicate_conflict_count, 2);
    assert_eq!(preview.same_name_conflict_count, 1);
    assert_eq!(preview.skip_count, 2);
    assert_eq!(preview.keep_both_count, 1);
    assert_eq!(preview.blocked_count, 0);
    assert_selected_preview(&preview.items, "dup-1", ImportConflictBatchStrategy::Skip);
    assert_selected_preview(&preview.items, "dup-2", ImportConflictBatchStrategy::Skip);
    assert_selected_preview(
        &preview.items,
        "name-1",
        ImportConflictBatchStrategy::KeepBoth,
    );
    assert_pre_apply_state(repo.path(), &[duplicate_one, duplicate_two], named);

    let report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, false),
        preview.preview_token,
    )
    .expect("apply safe default import conflict batch");

    assert_eq!(report.requested_conflict_count, 3);
    assert_eq!(report.resolved_count, 3);
    assert_eq!(report.skipped_count, 2);
    assert_eq!(report.kept_both_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(
        result_status(&report.item_results, "name-1"),
        ImportConflictBatchResultStatus::KeptBoth
    );
    assert_post_apply_state(repo.path(), &[duplicate_one, duplicate_two], named);
}

#[test]
fn import_conflict_batch_validation_blocks_index_only_replace_without_mutation() {
    let repo = initialized_conflict_repo();
    let session_id = "validation-index-only";
    insert_import_session(repo.path(), session_id);
    let named = same_name_fixture(repo.path(), session_id, "name-indexed", "staged-indexed");
    mark_indexed(repo.path(), named.existing);
    let request = replace_request(session_id, "name-indexed");

    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview index-only replace block");

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(preview.replace_count, 0);
    let item = preview
        .items
        .iter()
        .find(|item| item.conflict_id == "name-indexed")
        .expect("blocked index-only preview row");
    assert_eq!(
        item.conflict_type,
        ImportConflictBatchConflictType::SameNameDifferentContent
    );
    assert_eq!(item.selected_strategy, ImportConflictBatchStrategy::Replace);
    assert_eq!(item.status, ImportConflictBatchPreviewStatus::Blocked);
    assert!(item.index_only);
    assert_eq!(
        item.reason.as_deref(),
        Some("Index-only target cannot be replaced")
    );

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, true),
        preview.preview_token,
    )
    .expect_err("blocked index-only replace must not apply");

    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_same_name_unchanged(repo.path(), named, ".areamatrix/staging/staged-indexed");
    assert_eq!(
        conflict_status(repo.path(), "name-indexed"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_validation_blocks_replace_when_trash_unavailable() {
    let repo = initialized_conflict_repo();
    let session_id = "validation-trash-block";
    insert_import_session(repo.path(), session_id);
    let named = same_name_fixture(repo.path(), session_id, "name-trash-block", "staged-trash");
    let request = replace_request(session_id, "name-trash-block");
    let _guard = make_trash_pending_readonly(repo.path());

    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview replace with unavailable Trash");

    assert!(!preview.trash_available);
    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(preview.replace_count, 0);
    let item = preview
        .items
        .iter()
        .find(|item| item.conflict_id == "name-trash-block")
        .expect("blocked Trash preview row");
    assert_eq!(item.selected_strategy, ImportConflictBatchStrategy::Replace);
    assert_eq!(item.status, ImportConflictBatchPreviewStatus::Blocked);
    assert_eq!(item.reason.as_deref(), Some("Trash unavailable"));

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, true),
        preview.preview_token,
    )
    .expect_err("Trash-unavailable replace must not apply");

    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_same_name_unchanged(repo.path(), named, ".areamatrix/staging/staged-trash");
    assert_eq!(
        conflict_status(repo.path(), "name-trash-block"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_validation_binds_preview_token_to_trash_availability() {
    let repo = initialized_conflict_repo();
    let session_id = "validation-trash-token";
    insert_import_session(repo.path(), session_id);
    let named = same_name_fixture(repo.path(), session_id, "name-trash-token", "staged-token");
    let request = safe_default_request(session_id, &["name-trash-token"], false);

    let available_preview =
        preview_import_conflict_batch(path_string(repo.path()), request.clone())
            .expect("preview with available Trash");
    assert!(available_preview.trash_available);

    let _guard = make_trash_pending_readonly(repo.path());
    let unavailable_preview =
        preview_import_conflict_batch(path_string(repo.path()), request.clone())
            .expect("preview with unavailable Trash");
    assert!(!unavailable_preview.trash_available);
    assert_ne!(
        available_preview.preview_token,
        unavailable_preview.preview_token
    );

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, false),
        available_preview.preview_token,
    )
    .expect_err("Trash availability change makes old preview token stale");

    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_same_name_unchanged(repo.path(), named, ".areamatrix/staging/staged-token");
    assert_eq!(
        conflict_status(repo.path(), "name-trash-token"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_validation_keeps_docs_api_udl_and_rust_aligned() {
    for fragment in [
        "计划新增：`preview_import_conflict_batch`、`apply_import_conflict_batch`",
        "Hash duplicate 默认 Skip，同名不同内容默认 Keep both。",
        "批量策略执行前必须预览每一项影响。",
        "失败时保留 staged 文件和冲突状态，不覆盖用户文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    assert_contains(
        CONTROL_MAP,
        "| S2-21 | import-conflict-batch | C2-17, C2-07 | import conflict batch decision | import session, staging, change_log",
    );

    for fragment in [
        "ImportConflictBatchPreviewReport preview_import_conflict_batch(",
        "ImportConflictBatchApplyReport apply_import_conflict_batch(",
        "dictionary ImportConflictBatchPreviewRequest",
        "ImportConflictBatchStrategy duplicate_strategy;",
        "ImportConflictBatchStrategy same_name_strategy;",
        "dictionary ImportConflictBatchPreviewReport",
        "boolean can_apply;",
        "boolean replace_confirmation_required;",
        "dictionary ImportConflictBatchApplyRequest",
        "boolean replace_confirmed;",
        "dictionary ImportConflictBatchApplyReport",
        "sequence<ImportConflictBatchItemResult> item_results;",
        "enum ImportConflictBatchStrategy { \"Skip\", \"KeepBoth\", \"Replace\", \"AskPerItem\" };",
        "enum ImportConflictBatchResultStatus",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn preview_import_conflict_batch(",
        "pub fn apply_import_conflict_batch(",
        "import_conflict_batch::preview_import_conflict_batch",
        "import_conflict_batch::apply_import_conflict_batch",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "pub struct ImportConflictBatchPreviewRequest",
        "pub struct ImportConflictBatchPreviewReport",
        "pub struct ImportConflictBatchApplyRequest",
        "pub struct ImportConflictBatchApplyReport",
        "side-effect free",
        "missing replace confirmation",
        "stale import conflict batch preview",
    ] {
        assert_contains(CONTRACT_RS, fragment);
    }
}

#[derive(Clone, Copy)]
struct ConflictFixture {
    existing: i64,
    staging: i64,
}

fn initialized_conflict_repo() -> tempfile::TempDir {
    let repo = initialized_repo();
    create_conflict_schema(repo.path());
    repo
}

fn duplicate_fixture(
    repo: &Path,
    session_id: &str,
    conflict_id: &str,
    staging_name: &str,
) -> ConflictFixture {
    let existing = insert_active_file(repo, &format!("docs/{conflict_id}.pdf"), "hash-dup");
    let staging = insert_staging_file(
        repo,
        staging_name,
        &format!("{conflict_id}.pdf"),
        "hash-dup",
    );
    insert_conflict(
        repo,
        session_id,
        conflict_id,
        "duplicate_hash",
        staging,
        existing,
        &format!("docs/{conflict_id}.pdf"),
    );
    ConflictFixture { existing, staging }
}

fn same_name_fixture(
    repo: &Path,
    session_id: &str,
    conflict_id: &str,
    staging_name: &str,
) -> ConflictFixture {
    let existing = insert_active_file(repo, "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo, staging_name, "report.pdf", "hash-new");
    insert_conflict(
        repo,
        session_id,
        conflict_id,
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    ConflictFixture { existing, staging }
}

fn safe_default_request(
    session_id: &str,
    conflict_ids: &[&str],
    apply_to_all_similar_conflicts: bool,
) -> ImportConflictBatchPreviewRequest {
    ImportConflictBatchPreviewRequest {
        import_session_id: session_id.to_owned(),
        conflict_ids: conflict_ids.iter().map(|id| (*id).to_owned()).collect(),
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts,
    }
}

fn replace_request(session_id: &str, conflict_id: &str) -> ImportConflictBatchPreviewRequest {
    ImportConflictBatchPreviewRequest {
        import_session_id: session_id.to_owned(),
        conflict_ids: vec![conflict_id.to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::Replace,
        apply_to_all_similar_conflicts: false,
    }
}

fn apply_request_from_preview(
    preview_request: ImportConflictBatchPreviewRequest,
    replace_confirmed: bool,
) -> ImportConflictBatchApplyRequest {
    ImportConflictBatchApplyRequest {
        import_session_id: preview_request.import_session_id,
        conflict_ids: preview_request.conflict_ids,
        duplicate_strategy: preview_request.duplicate_strategy,
        same_name_strategy: preview_request.same_name_strategy,
        apply_to_all_similar_conflicts: preview_request.apply_to_all_similar_conflicts,
        replace_confirmed,
    }
}

fn assert_selected_preview(
    items: &[area_matrix_core::ImportConflictBatchPreviewItem],
    conflict_id: &str,
    strategy: ImportConflictBatchStrategy,
) {
    let item = items
        .iter()
        .find(|item| item.conflict_id == conflict_id)
        .expect("preview row exists");
    assert_eq!(item.selected_strategy, strategy);
    assert_eq!(item.status, ImportConflictBatchPreviewStatus::Ready);
}

fn assert_pre_apply_state(repo: &Path, duplicates: &[ConflictFixture], named: ConflictFixture) {
    for duplicate in duplicates {
        assert_eq!(file_status(repo, duplicate.existing).2, "active");
        assert_eq!(file_status(repo, duplicate.staging).2, "staging");
    }
    assert_same_name_unchanged(repo, named, ".areamatrix/staging/staged-report");
    assert!(!repo.join("docs/report_1.pdf").exists());
}

fn assert_post_apply_state(repo: &Path, duplicates: &[ConflictFixture], named: ConflictFixture) {
    for duplicate in duplicates {
        assert_eq!(file_status(repo, duplicate.existing).2, "active");
        assert_eq!(file_status(repo, duplicate.staging).2, "staging");
    }
    assert_eq!(
        file_status(repo, named.staging),
        (
            "docs/report_1.pdf".to_owned(),
            "report_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert!(repo.join("docs/report_1.pdf").exists());
}

fn assert_same_name_unchanged(repo: &Path, fixture: ConflictFixture, staging_path: &str) {
    assert_eq!(
        file_status(repo, fixture.existing),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_status(repo, fixture.staging),
        (
            staging_path.to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert!(repo.join("docs/report.pdf").exists());
    assert!(repo.join(staging_path).exists());
}

fn result_status(
    results: &[area_matrix_core::ImportConflictBatchItemResult],
    conflict_id: &str,
) -> ImportConflictBatchResultStatus {
    results
        .iter()
        .find(|item| item.conflict_id == conflict_id)
        .expect("apply result row")
        .status
        .clone()
}

fn mark_indexed(repo: &Path, file_id: i64) {
    open_db(repo)
        .execute(
            "UPDATE files SET storage_mode = 'indexed' WHERE id = ?1",
            [file_id],
        )
        .expect("mark fixture file as indexed");
}

struct TrashPendingPermissionsGuard {
    path: PathBuf,
    original: fs::Permissions,
}

impl Drop for TrashPendingPermissionsGuard {
    fn drop(&mut self) {
        if let Err(_error) = fs::set_permissions(&self.path, self.original.clone()) {
            // Best-effort test cleanup; the assertion path has already completed.
        }
    }
}

fn make_trash_pending_readonly(repo: &Path) -> TrashPendingPermissionsGuard {
    let path = repo.join(".areamatrix/trash-pending");
    fs::create_dir_all(&path).expect("create trash-pending fixture directory");
    let original = fs::metadata(&path)
        .expect("read trash-pending permissions")
        .permissions();
    let mut readonly = original.clone();
    readonly.set_readonly(true);
    fs::set_permissions(&path, readonly).expect("make trash-pending read-only");
    TrashPendingPermissionsGuard { path, original }
}

fn conflict_status(repo: &Path, conflict_id: &str) -> (String, Option<String>, Option<String>) {
    open_db(repo)
        .query_row(
            "SELECT status, decision, failure_reason
               FROM import_conflicts
              WHERE conflict_id = ?1",
            [conflict_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read conflict status")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}
