use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, recover_on_startup, CoreError, FileOrigin, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file_row(repo: &Path, relative_path: &str, status: &str) -> i64 {
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4, ?5, ?6, ?7, NULL,
                1, 1, ?8
             )",
            params![
                relative_path,
                file_name(relative_path),
                "finance",
                12_i64,
                format!("hash-{relative_path}"),
                storage_mode_value(&StorageMode::Copied),
                origin_value(&FileOrigin::Imported),
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
        .expect("path should have a UTF-8 file name")
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
        .expect("count rows by status")
}

fn staging_path(repo: &Path, name: &str) -> PathBuf {
    repo.join(".areamatrix/staging").join(name)
}

fn install_staging_delete_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_staging_delete
             BEFORE DELETE ON files
             WHEN OLD.status = 'staging'
             BEGIN
               SELECT RAISE(ABORT, 'forced staging delete failure');
             END;",
        )
        .expect("install staging delete failure trigger");
}

fn remove_staging_delete_failure(repo: &Path) {
    open_db(repo)
        .execute_batch("DROP TRIGGER fail_staging_delete;")
        .expect("remove staging delete failure trigger");
}

#[test]
fn recover_on_startup_failure_recovery_keeps_protected_active_staging_path() {
    let repo = initialized_repo();
    let protected = staging_path(repo.path(), "protected-active");
    fs::write(&protected, b"active bytes").expect("write protected staging-like active file");
    insert_file_row(
        repo.path(),
        ".areamatrix/staging/protected-active",
        "active",
    );

    let report =
        recover_on_startup(path_string(repo.path())).expect("recover protected staging path");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 0);
    assert_eq!(
        report.warnings,
        vec!["Kept protected staging path .areamatrix/staging/protected-active".to_owned()]
    );
    assert_eq!(
        fs::read(&protected).expect("protected active path should remain readable"),
        b"active bytes"
    );
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_failure_recovery_rejects_parent_traversal_row() {
    let repo = initialized_repo();
    let final_file = repo.path().join("user-owned.txt");
    fs::write(&final_file, b"user final bytes").expect("write final user file");
    let row_id = insert_file_row(
        repo.path(),
        ".areamatrix/staging/../user-owned.txt",
        "staging",
    );

    let report =
        recover_on_startup(path_string(repo.path())).expect("recover traversal staging row");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert_eq!(
        report.warnings,
        vec![format!(
            "Skipped filesystem cleanup for non-staging row {row_id} at \
             .areamatrix/staging/../user-owned.txt"
        )]
    );
    assert_eq!(
        fs::read(&final_file).expect("final user file must not be touched"),
        b"user final bytes"
    );
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_failure_recovery_retries_after_db_delete_failure() {
    let repo = initialized_repo();
    let staged = staging_path(repo.path(), "db-delete-failure");
    fs::write(&staged, b"staged bytes").expect("write staged residue");
    insert_file_row(
        repo.path(),
        ".areamatrix/staging/db-delete-failure",
        "staging",
    );
    install_staging_delete_failure(repo.path());

    let failed = recover_on_startup(path_string(repo.path()));

    assert_eq!(failed, Err(CoreError::Db));
    assert!(!staged.exists());
    assert_eq!(count_rows(repo.path(), "staging"), 1);

    remove_staging_delete_failure(repo.path());
    let report = recover_on_startup(path_string(repo.path()))
        .expect("retry recovery after DB delete is available");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[cfg(unix)]
#[test]
fn recover_on_startup_failure_recovery_permission_denied_keeps_retryable_state() {
    let repo = initialized_repo();
    let staging_dir = repo.path().join(".areamatrix/staging");
    let staged = staging_path(repo.path(), "permission-blocked");
    fs::write(&staged, b"staged bytes").expect("write staged residue");
    insert_file_row(
        repo.path(),
        ".areamatrix/staging/permission-blocked",
        "staging",
    );

    let original_permissions = fs::metadata(&staging_dir)
        .expect("read staging directory metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o500);
    fs::set_permissions(&staging_dir, blocked_permissions)
        .expect("remove staging directory write permissions");

    let failed = recover_on_startup(path_string(repo.path()));

    fs::set_permissions(&staging_dir, original_permissions).expect("restore staging permissions");

    assert_eq!(failed, Err(CoreError::PermissionDenied));
    assert_eq!(
        fs::read(&staged).expect("staging file should remain retryable"),
        b"staged bytes"
    );
    assert_eq!(count_rows(repo.path(), "staging"), 1);

    let report = recover_on_startup(path_string(repo.path()))
        .expect("retry recovery after permissions are restored");

    assert_eq!(report.cleaned_staging_files, 1);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert!(!staged.exists());
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}
