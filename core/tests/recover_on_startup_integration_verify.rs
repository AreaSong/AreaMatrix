use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_files, recover_on_startup, CoreError, FileFilter, FileOrigin, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const RECOVERY_RS: &str = include_str!("../src/recovery.rs");
const S1_05_INITIALIZING: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md");
const S1_10_MAIN_LOADING: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md");
const S1_32_ERROR_RECOVERY: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

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
    .expect("initialize repository for recover-on-startup integration");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file_row(repo: &Path, relative_path: &str, status: &str) -> i64 {
    insert_file_row_with_storage(repo, relative_path, status, StorageMode::Copied, None)
}

fn insert_file_row_with_storage(
    repo: &Path,
    relative_path: &str,
    status: &str,
    storage_mode: StorageMode,
    source_path: Option<&str>,
) -> i64 {
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4, ?5, ?6, ?7, ?8,
                1, 1, ?9
             )",
            params![
                relative_path,
                file_name(relative_path),
                "finance",
                12_i64,
                format!("hash-{relative_path}"),
                storage_mode_value(&storage_mode),
                origin_value(&FileOrigin::Imported),
                source_path,
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn file_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .expect("test path should have a UTF-8 file name")
        .to_owned()
}

fn storage_mode_value(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn origin_value(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

fn count_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows by status")
}

fn staging_path(repo: &Path, name: &str) -> PathBuf {
    repo.join(".areamatrix/staging").join(name)
}

fn list_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn remove_if_exists(path: PathBuf) {
    if path.exists() {
        fs::remove_file(path).expect("remove sqlite sidecar fixture");
    }
}

#[test]
fn recover_on_startup_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_16_capability_spec();
    assert_core_api_and_udl_contract();
    assert_stage_one_consumers();
    assert_rust_entry_points_are_real_recovery_wiring();
}

fn assert_c1_16_capability_spec() {
    for fragment in [
        "C1-16 recover-on-startup",
        "- S1-05 initializing",
        "- S1-10 main-loading",
        "- S1-32 error-recovery",
        "- `recover_on_startup(repo_path) -> RecoveryReport`",
        "- `cleaned_staging_files`",
        "- `reverted_staging_db_rows`",
        "- `warnings`",
        "- 将未完成 staging rows 回滚或标记为可恢复状态。",
        "- 清理 `.areamatrix/staging/` 中可判定安全的临时文件。",
        "- 不删除任何最终目录用户文件。",
        "- `RepoNotInitialized`",
        "- `Db`",
        "- `Io`",
        "- `PermissionDenied`",
        "- 崩溃残留 staging 文件能清理。",
        "- active 文件和用户文件不得被误删。",
        "- recovery report 可直接驱动 S1-32 展示。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "RecoveryReport recover_on_startup(string repo_path);",
        "dictionary RecoveryReport",
        "i64 cleaned_staging_files;",
        "i64 reverted_staging_db_rows;",
        "sequence<string> warnings;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `recover_on_startup(repoPath: String) throws -> RecoveryReport`",
        "应用启动必调",
        "耗时与残留 staging 文件数成正比",
        "| `recover_on_startup(repo)` | repo | √ | Db |",
        "RecoveryReport recover_on_startup(string repo_path);",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_stage_one_consumers() {
    for fragment in [
        "| S1-05 | initializing | C1-02, C1-03, C1-16 | `init_repo`, `recover_on_startup`, `get_latest_scan_session`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json`",
        "| S1-32 | error-recovery | C1-16, C1-21 | `recover_on_startup`, error mapping",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "staging recovery 状态。",
        "取消不影响用户已有文件，并有下次恢复路径。",
        "强退后重启能看到 Resume 或 Clean up and retry，不静默重跑危险操作。",
    ] {
        assert_contains(S1_05_INITIALIZING, fragment);
    }
    for fragment in [
        "迁移/恢复时 Tree locked，只允许查看。",
        "repo opening 不显示半成品主界面。",
        "critical 失败进入 `S1-11 main-repo-error`",
    ] {
        assert_contains(S1_10_MAIN_LOADING, fragment);
    }
    for fragment in [
        "CoreError 映射表。",
        "Retry 执行中禁用重复点击",
        "高风险修复不自动执行。",
        "Collect Diagnostics 不包含用户文件内容",
    ] {
        assert_contains(S1_32_ERROR_RECOVERY, fragment);
    }
}

fn assert_rust_entry_points_are_real_recovery_wiring() {
    for fragment in [
        "Recovers AreaMatrix-owned startup residue",
        "The only allowed filesystem side effect",
        "`.areamatrix/staging/` directory",
        "must not delete",
        "active repository file",
        "does not repair corrupted",
        "reindex the repository",
        "process FSEvents",
        "generate overviews",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "db::ensure_initialized_readable(&repo)?",
        "db::list_staging_file_rows(&repo)?",
        "db::list_protected_staging_paths(repo)?",
        "safe_staging_relative_path",
        "clean_orphan_staging_files",
        "restore_moved_staging_file",
        "remove_staging_file",
    ] {
        assert_contains(RECOVERY_RS, fragment);
    }
}

#[test]
fn recover_on_startup_integration_verify_real_report_drives_consumers_without_user_file_loss() {
    let repo = initialized_repo();
    let active_path = repo.path().join("finance/active.pdf");
    fs::create_dir_all(active_path.parent().expect("active file has parent"))
        .expect("create active category directory");
    fs::write(&active_path, b"active user bytes").expect("write active user file");
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), b"user overview").expect("write user overview");
    let active_id = insert_file_row(repo.path(), "finance/active.pdf", "active");

    let staged = staging_path(repo.path(), "interrupted-import");
    let orphan = staging_path(repo.path(), "copy-import-orphan-staging-file");
    fs::write(&staged, b"staged bytes").expect("write interrupted staging file");
    fs::write(&orphan, b"orphan bytes").expect("write orphan staging file");
    insert_file_row(
        repo.path(),
        ".areamatrix/staging/interrupted-import",
        "staging",
    );

    let report = recover_on_startup(path_string(repo.path())).expect("recover startup residue");

    assert_eq!(report.cleaned_staging_files, 2);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert!(!staged.exists());
    assert!(!orphan.exists());
    assert_user_files_are_unchanged(repo.path(), active_path.as_path());
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "staging"), 0);

    let files = list_files(path_string(repo.path()), list_filter()).expect("list active files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, active_id);
    assert_eq!(files[0].path, "finance/active.pdf");
}

#[test]
fn recover_on_startup_integration_verify_moved_crash_residue_is_not_deleted() {
    let repo = initialized_repo();
    let source_root = tempfile::tempdir().expect("create original source parent");
    let source = source_root.path().join("moved.pdf");
    let staged = staging_path(repo.path(), "move-import-crash-after-row");
    fs::write(&staged, b"moved source bytes").expect("write moved staging residue");
    insert_file_row_with_storage(
        repo.path(),
        ".areamatrix/staging/move-import-crash-after-row",
        "staging",
        StorageMode::Moved,
        Some(path_string(&source).as_str()),
    );

    let report = recover_on_startup(path_string(repo.path()))
        .expect("recover moved startup residue without deleting user bytes");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert!(!staged.exists());
    assert_eq!(
        fs::read(&source).expect("moved source should be restored to original path"),
        b"moved source bytes"
    );
    assert_eq!(count_rows(repo.path(), "staging"), 0);

    let before_db_row = staging_path(repo.path(), "move-import-crash-before-row");
    fs::write(&before_db_row, b"recoverable moved source").expect("write pre-db-row moved residue");
    let report =
        recover_on_startup(path_string(repo.path())).expect("preserve unclassified moved residue");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 0);
    assert_eq!(
        report.warnings,
        vec!["Kept unclassified staging file .areamatrix/staging/move-import-crash-before-row"]
    );
    assert_eq!(
        fs::read(&before_db_row).expect("pre-row moved residue must remain recoverable"),
        b"recoverable moved source"
    );
}

fn assert_user_files_are_unchanged(repo: &Path, active_path: &Path) {
    assert_eq!(
        fs::read(active_path).expect("active user file must remain readable"),
        b"active user bytes"
    );
    assert_eq!(
        fs::read(repo.join("README.md")).expect("README must remain untouched"),
        b"user readme"
    );
    assert_eq!(
        fs::read(repo.join("AREAMATRIX.md")).expect("overview file must remain untouched"),
        b"user overview"
    );
}

#[test]
fn recover_on_startup_integration_verify_warning_and_error_scope_stays_c1_16_only() {
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        recover_on_startup(path_string(uninitialized.path())),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    assert!(!uninitialized.path().join(".areamatrix").exists());

    let repo = initialized_repo();
    let protected = staging_path(repo.path(), "active-owned");
    fs::write(&protected, b"active bytes").expect("write protected staging-like file");
    insert_file_row(repo.path(), ".areamatrix/staging/active-owned", "active");

    let report =
        recover_on_startup(path_string(repo.path())).expect("recover protected staging path");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 0);
    assert_eq!(
        report.warnings,
        vec!["Kept protected staging path .areamatrix/staging/active-owned".to_owned()]
    );
    assert_eq!(
        fs::read(&protected).expect("protected active path should remain readable"),
        b"active bytes"
    );

    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("corrupt repository database fixture");
    remove_if_exists(repo.path().join(".areamatrix/index.db-wal"));
    remove_if_exists(repo.path().join(".areamatrix/index.db-shm"));
    assert!(matches!(
        recover_on_startup(path_string(repo.path())),
        Err(CoreError::Db { .. })
    ));
}
