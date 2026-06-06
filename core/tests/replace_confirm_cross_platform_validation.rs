use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, preview_sync_conflict_resolution,
    resolve_sync_conflict, CoreError, CoreResult, DuplicateStrategy, FileEntry, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
    SyncConflictResolutionPreviewReport, SyncConflictResolutionRequest,
    SyncConflictResolutionStrategy, SyncConflictResolveReport, SyncConflictStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

mod support;

use support::system_trash_home::with_test_system_trash;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-104-c4-21-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-21-replace-confirm-cross-platform.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const IMPORT_RS: &str = include_str!("../src/storage/import.rs");
const SYNC_RESOLVE_RS: &str = include_str!("../src/sync_conflict_resolve.rs");
const SYNC_RESOLVE_PLAN_RS: &str = include_str!("../src/sync_conflict_resolve/plan.rs");
const SYNC_RESOLVE_APPLY_RS: &str = include_str!("../src/sync_conflict_resolve/apply.rs");
const CONTRACT_TEST: &str = include_str!("replace_confirm_cross_platform_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("replace_confirm_cross_platform_implementation.rs");
const FAILURE_TEST: &str = include_str!("replace_confirm_cross_platform_failure_recovery.rs");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn source_file(name: &str, bytes: &[u8]) -> tempfile::TempDir {
    let source = tempfile::tempdir().expect("create source directory");
    fs::write(source.path().join(name), bytes).expect("write source file");
    source
}

fn import_options(filename: &str, strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("docs".to_owned()),
        override_category: None,
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: strategy,
    }
}

fn import_named_file(
    repo: &Path,
    filename: &str,
    bytes: &[u8],
    strategy: DuplicateStrategy,
) -> FileEntry {
    let source = source_file(filename, bytes);
    import_file(
        path_string(repo),
        path_string(&source.path().join(filename)),
        import_options(filename, strategy),
    )
    .expect("import file")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, Option<i64>) {
    open_db(repo)
        .query_row(
            "SELECT path, status, deleted_at FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn change_detail(repo: &Path, file_id: i64, action: &str) -> serde_json::Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse change detail")
}

fn staging_entries(repo: &Path) -> Vec<String> {
    let mut entries = fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| {
            entry
                .expect("read staging entry")
                .path()
                .display()
                .to_string()
        })
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn collect_user_files(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("entry is inside repo")
            .to_string_lossy()
            .replace('\\', "/");
        if relative.starts_with(".areamatrix") {
            continue;
        }
        if path.is_dir() {
            collect_user_files(repo, &path, files);
        } else {
            files.push((relative, fs::read(&path).expect("read user file")));
        }
    }
}

fn change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn sync_conflict_status(repo: &Path) -> SyncConflictStatus {
    let value: String = open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'sync_conflict_state'",
            [],
            |row| row.get(0),
        )
        .expect("read sync conflict state");
    serde_json::from_str::<Vec<area_matrix_core::SyncConflict>>(&value)
        .expect("parse sync conflict state")
        .first()
        .expect("sync conflict state has a row")
        .status
        .clone()
}

fn setup_sync_replace_conflict() -> (tempfile::TempDir, String, i64) {
    let repo = initialized_repo();
    let existing = import_named_file(
        repo.path(),
        "report.pdf",
        b"existing-version",
        DuplicateStrategy::Ask,
    );
    fs::write(
        repo.path()
            .join("docs/report (incoming conflicted copy).pdf"),
        b"incoming-version",
    )
    .expect("write incoming conflict copy");
    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");
    assert_eq!(conflicts.len(), 1);
    (repo, conflicts[0].conflict_id.clone(), existing.id)
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn replace_confirm_validation_import_overwrite_keeps_old_version_recoverable() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let existing = import_named_file(
            repo.path(),
            "report.pdf",
            b"existing-version",
            DuplicateStrategy::Ask,
        );

        let replacement = import_named_file(
            repo.path(),
            "report.pdf",
            b"confirmed-version",
            DuplicateStrategy::Overwrite,
        );

        assert_eq!(replacement.path, "docs/report.pdf");
        assert_eq!(
            fs::read(repo.path().join("docs/report.pdf")).expect("read replacement file"),
            b"confirmed-version"
        );
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read recoverable old version"),
            b"existing-version"
        );
        assert_eq!(file_row(repo.path(), replacement.id).1, "active");
        let existing_row = file_row(repo.path(), existing.id);
        assert!(existing_row.0.starts_with("system-trash://replace-"));
        assert_eq!(existing_row.1, "deleted");
        assert!(existing_row.2.is_some());
        assert_eq!(staging_entries(repo.path()), Vec::<String>::new());

        let deleted_detail = change_detail(repo.path(), existing.id, "deleted");
        assert_eq!(deleted_detail["safe_replace"], true);
        assert_eq!(deleted_detail["trashed"], true);
        assert_eq!(deleted_detail["reason"], "name_conflict_replace");

        let imported_detail = change_detail(repo.path(), replacement.id, "imported");
        assert_eq!(imported_detail["duplicate_strategy"], "overwrite");
        assert_eq!(imported_detail["replaced_file_id"], existing.id);
        assert_eq!(imported_detail["replaced_path"], "docs/report.pdf");
    });
}

fn assert_replace_plan_is_ui_ready(preview: &SyncConflictResolutionPreviewReport, file_id: i64) {
    let plan = preview.replace_plan.as_ref().expect("replace plan");
    assert_eq!(plan.old_path, "docs/report.pdf");
    assert_eq!(plan.new_path, "docs/report (incoming conflicted copy).pdf");
    assert!(plan.old_hash_sha256.is_some());
    assert!(plan.new_hash_sha256.is_some());
    assert_eq!(plan.affected_file_id, Some(file_id));
    assert_eq!(plan.backup_target.as_deref(), Some("Trash"));
    assert_eq!(
        plan.database_update,
        "canonical record will point to incoming file"
    );
    assert_eq!(plan.change_log_action, "conflict_resolved_use_incoming");
    assert_eq!(plan.recovery_note, "existing file must remain recoverable");
}

#[test]
fn replace_confirm_validation_sync_rejects_unconfirmed_replace_without_mutation() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_sync_replace_conflict();
        let files_before = user_files(repo.path());
        let changes_before = change_count(repo.path());
        let preview = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionStrategy::UseIncoming,
        )
        .expect("preview use incoming");
        let row_before = file_row(repo.path(), file_id);
        assert!(preview.destructive);
        assert!(preview.requires_replace_confirmation);
        assert!(preview.trash_required);
        assert!(preview.trash_available);
        assert!(!preview.can_apply);
        assert_eq!(
            preview.blocked_reason.as_deref(),
            Some("replace confirmation is required")
        );
        assert_eq!(preview.planned_trash_paths, vec!["docs/report.pdf"]);
        assert_eq!(preview.affected_file_ids, vec![file_id]);
        assert_replace_plan_is_ui_ready(&preview, file_id);

        let result = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: preview.preview_token.expect("preview token"),
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        );

        assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
        assert_eq!(user_files(repo.path()), files_before);
        assert_eq!(change_count(repo.path()), changes_before);
        assert_eq!(file_row(repo.path(), file_id), row_before);
        assert_eq!(
            sync_conflict_status(repo.path()),
            SyncConflictStatus::NeedsReview
        );
        assert!(
            fs::read_dir(trash_dir)
                .expect("read isolated trash")
                .next()
                .is_none(),
            "unconfirmed replace must not move anything to Trash"
        );
    });
}

#[test]
fn replace_confirm_validation_core_api_udl_rust_and_tests_stay_aligned() {
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}
    fn assert_delete(_: fn(String, i64) -> CoreResult<()>) {}
    fn assert_preview(
        _: fn(
            String,
            String,
            SyncConflictResolutionStrategy,
        ) -> CoreResult<SyncConflictResolutionPreviewReport>,
    ) {
    }
    fn assert_resolve(
        _: fn(
            String,
            String,
            SyncConflictResolutionRequest,
        ) -> CoreResult<SyncConflictResolveReport>,
    ) {
    }

    assert_import(import_file);
    assert_delete(area_matrix_core::delete_file);
    assert_preview(preview_sync_conflict_resolution);
    assert_resolve(resolve_sync_conflict);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-104: C4-21 validation",
        "为 C4-21 replace-confirm-cross-platform 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-104",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-21 replace-confirm-cross-platform",
        "- S4-X-09 replace-confirm",
        "`import_file` with overwrite strategy",
        "`delete_file`",
        "`resolve_sync_conflict`",
        "丢弃版本必须进入平台 Trash 或保留备份。",
        "不直接永久删除。",
        "Replace 必须二次确认。",
        "平台 Trash 不可用时禁用 replace。",
        "失败后旧版本和新版本状态可解释。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-07 | files-import | C4-06, C4-21 | Files import / replace confirm",
        "| S4-WIN-05 | import-flow | C4-13, C4-21 | desktop import / replace",
        "| S4-LNX-05 | import-flow | C4-13, C4-21 | desktop import / replace",
        "| S4-X-01 | sync-conflict | C4-15, C4-16, C4-21 | conflict detect/resolve",
        "| S4-X-09 | replace-confirm | C4-16, C4-21 | replace confirm | Trash/备份，禁止永久删除",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_api_and_udl_entry_points();
    assert_rust_surface_and_implementation();
}

fn assert_api_and_udl_entry_points() {
    for fragment in [
        "FileEntry import_file(",
        "void delete_file(string repo_path, i64 file_id);",
        "SyncConflictResolveReport resolve_sync_conflict(",
        "dictionary ImportOptions",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary SyncConflictReplacePlan",
        "string old_path;",
        "string new_path;",
        "string? backup_target;",
        "string database_update;",
        "string recovery_note;",
        "dictionary SyncConflictResolutionRequest",
        "boolean replace_confirmed;",
        "string? replace_confirmation_id;",
        "dictionary SyncConflictResolveReport",
        "sequence<string> trashed_paths;",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "enum SyncConflictResolutionStrategy { \"KeepBoth\", \"UseExisting\", \"UseIncoming\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_rust_surface_and_implementation() {
    for fragment in [
        "pub fn import_file(",
        "DuplicateStrategy::Overwrite",
        "C4-21 replace-confirm-cross-platform",
        "pub fn delete_file(",
        "no `hard` or permanent-delete flag",
        "pub fn resolve_sync_conflict(",
        "replace_confirmed",
        "Failure must leave",
        "S4-X-09 replace-confirm",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "pub use domain::*",
        "SyncConflictReplacePlan",
        "SyncConflictResolutionRequest",
        "SyncConflictResolveReport",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "pub enum DuplicateStrategy",
        "Overwrite",
        "Replace the existing active entry after the UI has confirmed the danger.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "ensure_replacement_is_recoverable_from_system_trash",
        "ReplacementDbRollback",
        "rollback_replacing_imported_file",
        "DuplicateStrategy::Overwrite",
    ] {
        assert_contains(IMPORT_RS, fragment);
    }

    for fragment in [
        "validate_resolution_request",
        "ensure_use_incoming_enabled",
        "replace confirmation is required",
        "Trash unavailable",
    ] {
        assert_contains(SYNC_RESOLVE_RS, fragment);
        assert_contains(SYNC_RESOLVE_PLAN_RS, "replace_plan");
        assert_contains(SYNC_RESOLVE_APPLY_RS, "rollback_replacement");
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "replace_confirm_contract_exports_existing_core_entry_points",
        "replace_confirm_docs_core_api_udl_and_control_map_stay_aligned",
        "replace_confirm_consumers_have_required_state_without_adjacent_capabilities",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "replace_confirm_cross_platform_implementation_import_overwrite_is_recoverable",
        "replace_confirm_cross_platform_implementation_sync_use_incoming_requires_confirmation",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "replace_confirm_failure_edge_rejects_empty_and_illegal_inputs_without_writes",
        "replace_confirm_failure_edge_import_overwrite_db_failure_restores_original_file",
        "replace_confirm_failure_edge_delete_db_failure_restores_file_and_retryable_state",
        "replace_confirm_failure_edge_import_conflict_replace_requires_fresh_confirmation",
        "replace_confirm_failure_edge_error_mapping_is_actionable_for_replace_failures",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
