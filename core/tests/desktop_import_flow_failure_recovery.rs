use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, import_file_with_result, init_repo, map_core_error, CoreError, DuplicateStrategy,
    ErrorKind, ErrorMappingInput, ErrorRecoverability, ErrorSeverity, ImportDestination,
    ImportOptions, ImportSourceRemovalStatus, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source fixture");
    (source_root, source_path)
}

fn desktop_options(mode: StorageMode, duplicate_strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("desktop/imports".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_count(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows by status")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_no_committed_import(repo: &Path) {
    assert_eq!(file_count(repo, "active"), 0);
    assert_eq!(file_count(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn install_import_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_desktop_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced desktop import change-log failure');
             END;",
        )
        .expect("install import change-log failure trigger");
}

fn seed_exhausted_name_conflicts(repo: &Path) {
    let directory = repo.join("desktop/imports");
    fs::create_dir_all(&directory).expect("create desktop import target directory");
    fs::write(directory.join("report.pdf"), b"existing").expect("write base conflict");
    for index in 1..1000 {
        fs::write(directory.join(format!("report_{index}.pdf")), b"existing")
            .expect("write numbered conflict");
    }
}

#[test]
fn desktop_import_flow_failure_recovery_empty_invalid_inputs_return_explicit_errors() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"desktop bytes");

    let empty_source = import_file(
        path_string(repo.path()),
        String::new(),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    );
    assert!(matches!(empty_source, Err(CoreError::InvalidPath { .. })));

    let mut bad_name = desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth);
    bad_name.override_filename = Some("bad/name.pdf".to_owned());
    let invalid_name = import_file(path_string(repo.path()), path_string(&source), bad_name);

    assert!(matches!(invalid_name, Err(CoreError::InvalidPath { .. })));
    assert_eq!(
        fs::read(&source).expect("source remains readable"),
        b"desktop bytes"
    );
    assert!(!repo.path().join("desktop").exists());
    assert_no_committed_import(repo.path());
}

#[test]
fn desktop_import_flow_failure_recovery_db_failure_removes_copy_half_product() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"copy rollback");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&source).expect("source is unchanged"),
        b"copy rollback"
    );
    assert!(!repo.path().join("desktop/imports/report.pdf").exists());
    assert!(!repo.path().join("desktop").exists());
    assert_no_committed_import(repo.path());
}

#[test]
fn desktop_import_flow_failure_recovery_db_failure_restores_moved_source() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("move.pdf", b"move rollback");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        desktop_options(StorageMode::Moved, DuplicateStrategy::KeepBoth),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&source).expect("moved source is restored"),
        b"move rollback"
    );
    assert!(!repo.path().join("desktop/imports/move.pdf").exists());
    assert!(!repo.path().join("desktop").exists());
    assert_no_committed_import(repo.path());
}

#[test]
fn desktop_import_flow_failure_recovery_conflict_keeps_source_and_existing_files() {
    let repo = initialized_repo();
    seed_exhausted_name_conflicts(repo.path());
    let (_source_root, source) = source_file("report.pdf", b"new desktop bytes");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(
        fs::read(&source).expect("source survives conflict"),
        b"new desktop bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("desktop/imports/report.pdf"))
            .expect("existing target remains readable"),
        b"existing"
    );
    assert_eq!(file_count(repo.path(), "active"), 0);
    assert_eq!(file_count(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[cfg(unix)]
#[test]
fn desktop_import_flow_failure_recovery_permission_denied_has_no_success_state() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_source_root, source) = source_file("secret.pdf", b"secret desktop bytes");
    let original_permissions = fs::metadata(&source)
        .expect("read source metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&source, blocked_permissions).expect("block source reads");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    );

    fs::set_permissions(&source, original_permissions).expect("restore source permissions");

    assert!(
        matches!(
            result,
            Err(CoreError::PermissionDenied { path }) if path == path_string(&source)
        ),
        "permission failure should be explicit and path based"
    );
    assert_eq!(
        fs::read(&source).expect("source is readable after permission recovery"),
        b"secret desktop bytes"
    );
    assert!(!repo.path().join("desktop").exists());
    assert_no_committed_import(repo.path());
}

#[cfg(unix)]
#[test]
fn desktop_import_flow_failure_recovery_move_source_removal_failure_returns_retained_result() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (source_root, source) = source_file("retained.pdf", b"retained desktop bytes");
    let source_root_path = source_root.path().to_path_buf();
    let original_permissions = fs::metadata(&source_root_path)
        .expect("read source root metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o500);
    fs::set_permissions(&source_root_path, blocked_permissions)
        .expect("block source directory removal");

    let result = import_file_with_result(
        path_string(repo.path()),
        path_string(&source),
        desktop_options(StorageMode::Moved, DuplicateStrategy::KeepBoth),
    )
    .expect("commit move import while retaining source after removal failure");

    fs::set_permissions(&source_root_path, original_permissions)
        .expect("restore source directory permissions");

    assert_eq!(
        result.source_removal_status,
        ImportSourceRemovalStatus::Retained
    );
    assert_eq!(
        result.source_removal_failure.as_deref(),
        Some("permission denied")
    );
    assert_eq!(
        fs::read(&source).expect("source remains after removal failure"),
        b"retained desktop bytes"
    );
    assert_eq!(result.entry.path, "desktop/imports/retained.pdf");
    assert_eq!(
        fs::read(repo.path().join(&result.entry.path)).expect("read retained imported file"),
        b"retained desktop bytes"
    );
    assert_eq!(file_count(repo.path(), "active"), 1);
    assert_eq!(file_count(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn desktop_import_flow_failure_recovery_maps_error_codes_without_string_parsing() {
    for (kind, severity, recoverability) in [
        (
            ErrorKind::DuplicateFile,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::Conflict,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::InvalidPath,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::Db,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorKind::Io,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
    ] {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("desktop/imports/report.pdf".to_owned()),
            reason: None,
            message: Some("database is locked".to_owned()),
        });

        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
    }
}
