use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, reindex_from_filesystem, resume_scan_session,
    CoreError, CoreResult, FileFilter, FileOrigin, OverviewOutput, ReindexReport, RepoInitMode,
    RepoInitOptions, ScanSession, ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-94-c4-19-validation.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-19-manual-rescan.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const RESCAN_CONFIRM_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-07-rescan-confirm.md");
const WIN_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-04-watcher-status.md");
const LNX_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-04-watcher-status.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const REPO_SCAN_RS: &str = include_str!("../src/repo_scan.rs");
const DB_MOD_RS: &str = include_str!("../src/db/mod.rs");
const DB_SCAN_RS: &str = include_str!("../src/db/scan.rs");
const CONTRACT_TEST: &str = include_str!("manual_rescan_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("manual_rescan_implementation.rs");
const FAILURE_TEST: &str = include_str!("manual_rescan_failure_recovery.rs");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) -> PathBuf {
    let path = repo.join(relative_path);
    let parent = path
        .parent()
        .expect("repository fixture path should have a parent");
    fs::create_dir_all(parent).expect("create repository fixture parent");
    fs::write(&path, bytes).expect("write repository fixture file");
    path
}

fn user_file_snapshot(paths: &[&Path]) -> Vec<(String, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.to_string_lossy().into_owned(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

fn indexed_files(repo_path: &Path) -> Vec<area_matrix_core::FileEntry> {
    let mut files = list_files(path_string(repo_path), empty_filter())
        .expect("list files after manual rescan validation");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    files
}

fn indexed_paths(repo_path: &Path) -> Vec<String> {
    indexed_files(repo_path)
        .into_iter()
        .map(|file| file.path)
        .collect()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected text not to contain `{needle}`"
    );
}

#[test]
fn manual_rescan_validation_success_path_is_ui_ready_and_file_safe() {
    let repo = initialized_repo();
    let readme = write_repo_file(repo.path(), "README.md", b"# User project\n");
    let spec = write_repo_file(repo.path(), "docs/spec.txt", b"spec content\n");
    let root_overview = write_repo_file(repo.path(), "AREAMATRIX.md", b"user overview\n");
    write_repo_file(repo.path(), ".DS_Store", b"finder metadata\n");
    write_repo_file(repo.path(), "scratch.tmp", b"temporary\n");
    write_repo_file(repo.path(), "cloud/placeholder.icloud", b"not downloaded\n");
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/manual.md",
        b"generated overview\n",
    );
    let before = user_file_snapshot(&[&readme, &spec, &root_overview]);

    let report =
        reindex_from_filesystem(path_string(repo.path())).expect("run manual rescan validation");

    assert!(report.scan_session_id.is_some());
    assert_eq!(report.inserted, 2);
    assert_eq!(report.updated, 0);
    assert!(report.skipped >= 4);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(user_file_snapshot(&[&readme, &spec, &root_overview]), before);

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("manual rescan should persist a session");
    assert_completed_reindex_session(&session, &report);
    assert_indexed_external_paths(repo.path(), vec!["README.md", "docs/spec.txt"]);
}

#[test]
fn manual_rescan_validation_failure_paths_do_not_touch_user_files() {
    assert_eq!(
        reindex_from_filesystem("   ".to_owned()),
        Err(CoreError::invalid_path("invalid path"))
    );

    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    let readme = write_repo_file(uninitialized.path(), "README.md", b"# User project\n");
    let before_uninitialized = user_file_snapshot(&[&readme]);

    assert_eq!(
        reindex_from_filesystem(path_string(uninitialized.path())),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    assert!(!uninitialized.path().join(".areamatrix").exists());
    assert_eq!(user_file_snapshot(&[&readme]), before_uninitialized);

    let initialized = initialized_repo();
    let spec = write_repo_file(initialized.path(), "docs/spec.txt", b"spec content\n");
    let before_initialized = user_file_snapshot(&[&spec]);
    let metadata_path = initialized.path().join(".areamatrix");

    assert_eq!(
        reindex_from_filesystem(path_string(&metadata_path)),
        Err(CoreError::invalid_path("invalid path"))
    );
    assert_eq!(user_file_snapshot(&[&spec]), before_initialized);
    assert_eq!(indexed_paths(initialized.path()), Vec::<String>::new());
}

#[test]
fn manual_rescan_validation_resume_completed_session_is_metadata_only_noop() {
    let repo = initialized_repo();
    let readme = write_repo_file(repo.path(), "README.md", b"# User project\n");
    reindex_from_filesystem(path_string(repo.path())).expect("seed completed manual rescan");
    let completed = get_latest_scan_session(path_string(repo.path()))
        .expect("read completed session")
        .expect("completed manual rescan session should exist");
    let later = write_repo_file(repo.path(), "later.txt", b"created after completion\n");
    let before = user_file_snapshot(&[&readme, &later]);

    let report = resume_scan_session(path_string(repo.path()), completed.id)
        .expect("resume completed manual rescan session");

    assert_eq!(report.scan_session_id, Some(completed.id));
    assert_eq!(report.inserted, 0);
    assert_eq!(report.updated, 0);
    assert_eq!(report.skipped, 0);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(indexed_paths(repo.path()), vec!["README.md"]);
    assert_eq!(user_file_snapshot(&[&readme, &later]), before);
}

#[test]
fn manual_rescan_validation_locks_api_udl_rust_and_test_evidence() {
    fn assert_reindex(_: fn(String) -> CoreResult<ReindexReport>) {}
    fn assert_latest(_: fn(String) -> CoreResult<Option<ScanSession>>) {}
    fn assert_resume(_: fn(String, i64) -> CoreResult<ReindexReport>) {}

    assert_reindex(reindex_from_filesystem);
    assert_latest(get_latest_scan_session);
    assert_resume(resume_scan_session);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_completed_reindex_session(
    session: &area_matrix_core::ScanSession,
    report: &area_matrix_core::ReindexReport,
) {
    assert_eq!(Some(session.id), report.scan_session_id);
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.inserted, report.inserted);
    assert_eq!(session.updated, report.updated);
    assert_eq!(session.skipped, report.skipped);
    assert_eq!(session.errors, report.errors);
    assert_eq!(session.finished_at, Some(session.updated_at));
}

fn assert_indexed_external_paths(repo_path: &Path, expected_paths: Vec<&str>) {
    let files = indexed_files(repo_path);
    assert_eq!(
        files
            .iter()
            .map(|file| file.path.as_str())
            .collect::<Vec<_>>(),
        expected_paths
    );
    for file in files {
        assert_eq!(file.origin, FileOrigin::External);
        assert_eq!(file.storage_mode, StorageMode::Indexed);
        assert_eq!(file.source_path, None);
    }
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-94: C4-19 validation",
        "为 C4-19 manual-rescan 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-94",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-19 manual-rescan",
        "- S4-X-07 rescan-confirm",
        "- S4-WIN-04 watcher-status",
        "- S4-LNX-04 watcher-status",
        "- `reindex_from_filesystem`",
        "- `get_latest_scan_session`",
        "- `resume_scan_session`",
        "只读扫描 repo。",
        "不移动、不删除、不覆盖用户文件。",
        "扫描失败可恢复或继续。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | Windows watcher 在平台层",
        "| S4-LNX-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | inotify 在平台层",
        "| S4-X-07 | rescan-confirm | C4-19 | manual rescan | 只读扫描，不改用户文件",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    for fragment in [
        "ReindexReport reindex_from_filesystem(string repo_path);",
        "ScanSession? get_latest_scan_session(string repo_path);",
        "ReindexReport resume_scan_session(string repo_path, i64 scan_session_id);",
        "dictionary ReindexReport",
        "i64? scan_session_id;",
        "i64 inserted;",
        "i64 updated;",
        "i64 skipped;",
        "sequence<string> errors;",
        "dictionary ScanSession",
        "ScanSessionKind kind;",
        "ScanSessionStatus status;",
        "enum ScanSessionKind { \"Adopt\", \"Reindex\" };",
        "enum ScanSessionStatus { \"Running\", \"Completed\", \"Paused\", \"Failed\", \"Interrupted\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport>",
        "repair::reindex_from_filesystem(repo_path)",
        "pub fn get_latest_scan_session(repo_path: String) -> CoreResult<Option<ScanSession>>",
        "repo_scan::get_latest_scan_session(repo_path)",
        "pub fn resume_scan_session(repo_path: String, scan_session_id: i64)",
        "repo_scan::resume_scan_session(repo_path, scan_session_id)",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "db::create_scan_session(&repo, ScanSessionKind::Reindex)?",
        "run_filesystem_scan(&repo, scan_session_id, None, ScanMode::Reindex)?",
        "session.status == ScanSessionStatus::Completed",
        "return Ok(empty_report(scan_session_id));",
        "ScanMode::from_kind(&session.kind)",
    ] {
        assert_contains(REPO_SCAN_RS, fragment);
    }

    assert_contains(DB_MOD_RS, "CREATE TABLE IF NOT EXISTS scan_sessions");
    assert_contains(DB_MOD_RS, "kind TEXT NOT NULL CHECK (kind IN ('adopt', 'reindex'))");
    assert_contains(DB_SCAN_RS, "pub(crate) fn upsert_reindexed_file");
    assert_contains(DB_SCAN_RS, "INSERT INTO change_log (file_id, action, detail_json, occurred_at)");
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "Windows/Linux watcher 页的 rescan 必须先进入本确认页。",
        "页面明确说明不移动、不删除、不覆盖用户文件。",
        "成功结果显示新增、更新、缺失、冲突、不可读、跳过数量。",
        "rescan summary 可审计",
    ] {
        assert_contains(RESCAN_CONFIRM_PAGE, fragment);
    }

    for fragment in ["提供 `Run rescan now` 入口，但点击后必须先进入 `S4-X-07 rescan-confirm`。"] {
        assert_contains(WIN_WATCHER_PAGE, fragment);
        assert_contains(LNX_WATCHER_PAGE, fragment);
    }
    assert_contains(WIN_WATCHER_PAGE, "rescan 进行中不会启动第二个 rescan。");
    assert_contains(LNX_WATCHER_PAGE, "rescan 过程中不会启动第二次 rescan。");

    for out_of_scope in [
        "preview_manual_rescan",
        "manual_rescan_dry_run",
        "rescan_subtree",
    ] {
        assert_not_contains(API_RS, out_of_scope);
        assert_not_contains(UDL, out_of_scope);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "manual_rescan_contract_exports_documented_signatures_outputs_and_errors",
        "manual_rescan_docs_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "manual_rescan_indexes_files_without_mutating_user_content",
        "manual_rescan_updates_changed_metadata_in_place_and_skips_stable_files",
        "manual_rescan_resume_completed_session_returns_empty_report_without_rescanning",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "manual_rescan_failure_recovery_empty_repo_returns_completed_empty_report",
        "manual_rescan_failure_recovery_rejects_invalid_and_uninitialized_paths_without_side_effects",
        "manual_rescan_failure_recovery_db_error_preserves_user_files_and_records_failed_session",
        "manual_rescan_failure_recovery_permission_denied_is_resumable_without_user_file_mutation",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
