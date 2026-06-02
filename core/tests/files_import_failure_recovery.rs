use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, map_core_error, CoreError, DuplicateStrategy, ErrorKind,
    ErrorMappingInput, ErrorRecoverability, ErrorSeverity, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-28-c4-06-failure-edge.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-06-files-import.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const TRANSACTIONAL_IMPORT: &str = include_str!("../../docs/architecture/transactional-import.md");

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

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn provider_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let provider_scope = tempfile::tempdir().expect("create Files provider scope");
    let source = provider_scope.path().join(name);
    fs::write(&source, content).expect("write selected provider file");
    (provider_scope, source)
}

fn files_options(filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn row_count(repo: &Path, table: &str, status: Option<&str>) -> i64 {
    let connection = open_db(repo);
    match status {
        Some(status) => connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE status = ?1"),
                [status],
                |row| row.get(0),
            )
            .expect("count rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count rows"),
    }
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .expect("read repo config value")
}

fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [table],
            |_| Ok(true),
        )
        .optional()
        .expect("check table existence")
        .unwrap_or(false)
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_clean_files_import_failure(repo: &Path, final_name: &str) {
    assert_eq!(row_count(repo, "files", Some("active")), 0);
    assert_eq!(row_count(repo, "files", Some("staging")), 0);
    assert_eq!(row_count(repo, "change_log", None), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert!(!repo.join("inbox").join(final_name).exists());
}

fn install_import_metadata_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_files_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced files import metadata failure');
             END;",
        )
        .expect("install import metadata failure trigger");
}

#[test]
fn files_import_failure_edge_docs_require_explicit_failure_semantics() {
    for fragment in [
        "覆盖空态、非法输入、权限、IO/DB 错误和错误码映射。",
        "必须证明失败不留下半成品。",
        "不得用吞错或静默降级掩盖失败。",
    ] {
        assert!(TASK.contains(fragment), "missing task fragment: {fragment}");
    }

    for fragment in [
        "文件未下载/无权限时给出结构化状态。",
        "Replace 必须进入 S4-X-09。",
        "Cancel 不写 DB。",
        "Provider 后台下载管理不在 Core。",
    ] {
        assert!(
            CAPABILITY_SPEC.contains(fragment),
            "missing capability fragment: {fragment}"
        );
    }

    for fragment in [
        "`ICloudPlaceholder { path }`",
        "`PermissionDenied { path }`",
        "`DuplicateFile { existing_path }`",
        "`Conflict { path }`",
    ] {
        assert!(
            ERROR_CODES.contains(fragment),
            "missing error fragment: {fragment}"
        );
    }

    for fragment in [
        "失败的 import 不留下 DB 记录或最终目录中的半文件",
        "ROLLBACK",
        "StagingGuard",
        "最终目录无变化",
    ] {
        assert!(
            TRANSACTIONAL_IMPORT.contains(fragment),
            "missing transaction fragment: {fragment}"
        );
    }
}

#[test]
fn files_import_failure_recovery_cancel_empty_state_has_no_core_side_effects() {
    let repo = initialized_repo();
    let (_provider_scope, selected) = provider_file("cancelled.pdf", b"cancelled selection");

    assert_eq!(
        fs::read(&selected).expect("read cancelled provider file"),
        b"cancelled selection"
    );
    assert_clean_files_import_failure(repo.path(), "Cancelled.pdf");
    assert_eq!(
        repo_config_value(repo.path(), "ai_enabled"),
        Some("false".to_owned())
    );
    assert_eq!(
        repo_config_value(repo.path(), "remote_provider_config"),
        None
    );
    assert!(!table_exists(repo.path(), "ai_call_log"));
}

#[test]
fn files_import_failure_recovery_invalid_inputs_are_explicit_and_non_mutating() {
    let repo = initialized_repo();
    let (_provider_scope, selected) = provider_file("invalid.pdf", b"invalid input bytes");

    let empty_repo = import_file(
        String::new(),
        path_string(&selected),
        files_options("Valid.pdf"),
    );
    assert!(matches!(empty_repo, Err(CoreError::InvalidPath { .. })));

    let empty_source = import_file(
        path_string(repo.path()),
        String::new(),
        files_options("Valid.pdf"),
    );
    assert!(matches!(empty_source, Err(CoreError::InvalidPath { .. })));

    let bad_filename = import_file(
        path_string(repo.path()),
        path_string(&selected),
        files_options("bad/name.pdf"),
    );
    assert!(matches!(bad_filename, Err(CoreError::InvalidPath { .. })));
    assert_eq!(
        fs::read(&selected).expect("provider source remains untouched"),
        b"invalid input bytes"
    );
    assert_clean_files_import_failure(repo.path(), "Valid.pdf");
}

#[test]
fn files_import_failure_recovery_icloud_placeholder_maps_and_writes_no_state() {
    let repo = initialized_repo();
    let (_provider_scope, placeholder) = provider_file("remote.pdf.icloud", b"placeholder");

    let result = import_file(
        path_string(repo.path()),
        path_string(&placeholder),
        files_options("Remote.pdf"),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::ICloudPlaceholder { path }) if path == path_string(&placeholder)
        ),
        "placeholder error should carry the provider source path"
    );
    assert_eq!(
        fs::read(&placeholder).expect("provider placeholder remains untouched"),
        b"placeholder"
    );
    assert_clean_files_import_failure(repo.path(), "Remote.pdf");

    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::ICloudPlaceholder,
        path: Some(path_string(&placeholder)),
        reason: None,
        message: None,
    });
    assert_eq!(mapping.severity, ErrorSeverity::Medium);
    assert_eq!(mapping.recoverability, ErrorRecoverability::Retryable);
}

#[cfg(unix)]
#[test]
fn files_import_failure_recovery_permission_denied_keeps_provider_file_and_repo_clean() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_provider_scope, selected) = provider_file("blocked.pdf", b"blocked provider bytes");
    let original_permissions = fs::metadata(&selected)
        .expect("read source permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&selected, blocked_permissions).expect("remove source read permission");

    let result = import_file(
        path_string(repo.path()),
        path_string(&selected),
        files_options("Blocked.pdf"),
    );

    fs::set_permissions(&selected, original_permissions).expect("restore source permissions");
    assert!(
        matches!(
            result,
            Err(CoreError::PermissionDenied { path }) if path == path_string(&selected)
        ),
        "permission error should carry the provider source path"
    );
    assert_eq!(
        fs::read(&selected).expect("provider source remains readable after restore"),
        b"blocked provider bytes"
    );
    assert_clean_files_import_failure(repo.path(), "Blocked.pdf");

    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some(path_string(&selected)),
        reason: None,
        message: None,
    });
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

#[test]
fn files_import_failure_recovery_staging_io_error_keeps_provider_file_and_no_final() {
    let repo = initialized_repo();
    let (_provider_scope, selected) = provider_file("io.pdf", b"io failure bytes");
    let staging_root = repo.path().join(".areamatrix/staging");
    fs::remove_dir(&staging_root).expect("remove staging directory for IO blocker");
    fs::write(&staging_root, b"not a directory").expect("block staging directory recreation");

    let result = import_file(
        path_string(repo.path()),
        path_string(&selected),
        files_options("Io.pdf"),
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));
    assert_eq!(
        fs::read(&selected).expect("provider source survives staging IO failure"),
        b"io failure bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo.path().join("inbox/Io.pdf").exists());
}

#[test]
fn files_import_failure_recovery_db_error_removes_final_file_and_can_retry() {
    let repo = initialized_repo();
    let (_provider_scope, selected) = provider_file("retry.pdf", b"retry files bytes");
    install_import_metadata_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&selected),
        files_options("Retry.pdf"),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&selected).expect("provider source survives metadata failure"),
        b"retry files bytes"
    );
    assert_clean_files_import_failure(repo.path(), "Retry.pdf");

    open_db(repo.path())
        .execute_batch("DROP TRIGGER fail_files_import_change_log;")
        .expect("remove import metadata failure trigger");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&selected),
        files_options("Retry.pdf"),
    )
    .expect("retry import after metadata failure");

    assert_eq!(entry.path, "inbox/Retry.pdf");
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read retried import"),
        b"retry files bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 1);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn files_import_failure_recovery_duplicate_ask_returns_error_without_swallowing() {
    let repo = initialized_repo();
    let (_first_scope, first) = provider_file("first.pdf", b"same provider bytes");
    let (_second_scope, second) = provider_file("second.pdf", b"same provider bytes");

    let first_entry = import_file(
        path_string(repo.path()),
        path_string(&first),
        files_options("First.pdf"),
    )
    .expect("import first provider file");
    let mut options = files_options("Second.pdf");
    options.duplicate_strategy = DuplicateStrategy::Ask;
    let result = import_file(path_string(repo.path()), path_string(&second), options);

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first_entry.path
        ),
        "Duplicate Ask should return structured DuplicateFile for UI decision"
    );
    assert_eq!(
        fs::read(&second).expect("duplicate provider source remains untouched"),
        b"same provider bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 1);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
