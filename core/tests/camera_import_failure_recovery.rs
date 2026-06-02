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

fn captured_photo(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let camera_temp = tempfile::tempdir().expect("create platform camera temp directory");
    let source_path = camera_temp.path().join(name);
    fs::write(&source_path, content).expect("write captured photo fixture");
    (camera_temp, source_path)
}

fn camera_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("photos".to_owned()),
        override_filename: Some("Photo 2026-04-29 1130.jpg".to_owned()),
        duplicate_strategy: DuplicateStrategy::KeepBoth,
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

fn assert_clean_camera_failure(repo: &Path) {
    assert_eq!(row_count(repo, "files", Some("active")), 0);
    assert_eq!(row_count(repo, "files", Some("staging")), 0);
    assert_eq!(row_count(repo, "change_log", None), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert!(!repo.join("photos/Photo 2026-04-29 1130.jpg").exists());
}

fn install_camera_metadata_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_camera_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced camera import metadata failure');
             END;",
        )
        .expect("install camera import metadata failure trigger");
}

#[test]
fn camera_import_failure_recovery_capture_cancel_empty_state_has_no_core_side_effects() {
    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("cancelled.jpg", b"captured but cancelled");

    assert_eq!(
        fs::read(&source).expect("platform temp photo remains platform-owned"),
        b"captured but cancelled"
    );
    assert_clean_camera_failure(repo.path());
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
fn camera_import_failure_recovery_invalid_inputs_are_explicit_and_non_mutating() {
    let repo = initialized_repo();

    let empty_repo = import_file(
        String::new(),
        "/tmp/camera.jpg".to_owned(),
        camera_options(),
    );
    assert!(matches!(empty_repo, Err(CoreError::InvalidPath { .. })));

    let empty_source = import_file(path_string(repo.path()), String::new(), camera_options());
    assert!(matches!(empty_source, Err(CoreError::InvalidPath { .. })));

    let internal_source = repo.path().join(".areamatrix/staging/camera-temp.jpg");
    fs::write(&internal_source, b"internal staging file").expect("write internal staging file");
    let internal_result = import_file(
        path_string(repo.path()),
        path_string(&internal_source),
        camera_options(),
    );

    assert!(matches!(
        internal_result,
        Err(CoreError::InvalidPath { .. })
    ));
    assert_eq!(
        fs::read(&internal_source).expect("internal source remains untouched"),
        b"internal staging file"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo
        .path()
        .join("photos/Photo 2026-04-29 1130.jpg")
        .exists());
}

#[cfg(unix)]
#[test]
fn camera_import_failure_recovery_permission_denied_maps_and_leaves_no_half_products() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("capture.jpg", b"permission blocked bytes");
    let original_permissions = fs::metadata(&source)
        .expect("read source permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&source, blocked_permissions).expect("remove source read permission");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        camera_options(),
    );

    fs::set_permissions(&source, original_permissions).expect("restore source permissions");

    assert!(
        matches!(
            result,
            Err(CoreError::PermissionDenied { path }) if path == path_string(&source)
        ),
        "permission error should carry the camera temp source path"
    );
    assert_eq!(
        fs::read(&source).expect("camera temp source remains readable after restore"),
        b"permission blocked bytes"
    );
    assert_clean_camera_failure(repo.path());

    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some(path_string(&source)),
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
fn camera_import_failure_recovery_io_error_from_staging_root_keeps_temp_file() {
    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("capture.jpg", b"io failure bytes");
    let staging_root = repo.path().join(".areamatrix/staging");
    fs::remove_dir(&staging_root).expect("remove staging directory for IO blocker setup");
    fs::write(&staging_root, b"not a staging directory").expect("block staging directory");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        camera_options(),
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));
    assert_eq!(
        fs::read(&source).expect("camera temp source survives staging IO failure"),
        b"io failure bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo
        .path()
        .join("photos/Photo 2026-04-29 1130.jpg")
        .exists());
}

#[test]
fn camera_import_failure_recovery_db_error_rolls_back_final_file_and_can_retry() {
    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("capture.jpg", b"retryable camera bytes");
    install_camera_metadata_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        camera_options(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&source).expect("camera temp source survives DB failure"),
        b"retryable camera bytes"
    );
    assert_clean_camera_failure(repo.path());

    open_db(repo.path())
        .execute_batch("DROP TRIGGER fail_camera_import_change_log;")
        .expect("remove camera import metadata failure trigger");

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        camera_options(),
    )
    .expect("retry camera import after metadata failure");

    assert_eq!(entry.path, "photos/Photo 2026-04-29 1130.jpg");
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read retried camera import"),
        b"retryable camera bytes"
    );
    assert_eq!(
        fs::read(&source).expect("copied camera temp source is platform-owned"),
        b"retryable camera bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 1);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
