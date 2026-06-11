use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileFilter,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn indexed_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
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
        .expect("count change log rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_no_index_side_effects(repo: &Path) {
    assert!(!repo.join("finance").exists());
    assert_eq!(file_count(repo, "active"), 0);
    assert_eq!(file_count(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn install_import_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced import change log failure');
             END;",
        )
        .expect("install import change-log failure trigger");
}

fn remove_import_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch("DROP TRIGGER fail_import_change_log;")
        .expect("remove import change-log failure trigger");
}

#[test]
fn import_index_file_failure_recovery_db_error_rolls_back_index_metadata_only() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"index rollback");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(
        fs::read(&source).expect("read source after indexed DB failure"),
        b"index rollback"
    );
    assert_no_index_side_effects(repo.path());
}

#[test]
fn import_index_file_failure_recovery_failed_attempt_can_be_retried() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"retry indexed import");
    install_import_change_log_failure(repo.path());

    let failed = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    assert!(matches!(failed, Err(CoreError::Db { .. })));

    assert_eq!(
        fs::read(&source).expect("read source after failed indexed attempt"),
        b"retry indexed import"
    );
    assert_no_index_side_effects(repo.path());
    remove_import_change_log_failure(repo.path());

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    )
    .expect("retry indexed import after rollback");

    let source_path = path_string(&source);
    assert_eq!(
        fs::read(&source).expect("read indexed source"),
        b"retry indexed import"
    );
    assert_eq!(entry.path, source_path);
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert!(!repo.path().join("finance").exists());
    assert_eq!(file_count(repo.path(), "active"), 1);
    assert_eq!(file_count(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list indexed file");
    assert_eq!(files, vec![entry]);
}

#[test]
fn import_index_file_failure_recovery_repeated_same_source_is_duplicate_only() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"repeat indexed source");

    import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    )
    .expect("index source once");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    let existing_path = path_string(&source);
    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path: reported }) if reported == existing_path
        ),
        "duplicate error should report the indexed source path"
    );
    assert_eq!(
        fs::read(&source).expect("read source after duplicate indexed attempt"),
        b"repeat indexed source"
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(file_count(repo.path(), "active"), 1);
    assert_eq!(file_count(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_index_file_failure_recovery_rejects_icloud_marker_without_db_write() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file(".invoice.pdf.icloud", b"placeholder marker");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::ICloudPlaceholder { path }) if path == path_string(&source)
        ),
        "iCloud placeholder error should carry the indexed source path"
    );
    assert_eq!(
        fs::read(&source).expect("read iCloud marker source after rejection"),
        b"placeholder marker"
    );
    assert_no_index_side_effects(repo.path());
}

#[test]
fn import_index_file_failure_recovery_rejects_metadata_internal_source() {
    let repo = initialized_repo();
    let source = repo.path().join(".areamatrix/generated/internal.pdf");
    fs::write(&source, b"internal bytes").expect("write internal metadata file");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));

    assert_eq!(
        fs::read(&source).expect("read internal source after rejected import"),
        b"internal bytes"
    );
    assert_no_index_side_effects(repo.path());
}

#[cfg(unix)]
#[test]
fn import_index_file_failure_recovery_permission_denied_leaves_source_and_db_unchanged() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_source_root, source) = source_file("secret.pdf", b"secret indexed bytes");
    let original_permissions = fs::metadata(&source)
        .expect("read source metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&source, blocked_permissions).expect("remove source read permissions");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    fs::set_permissions(&source, original_permissions).expect("restore source permissions");

    assert!(
        matches!(
            result,
            Err(CoreError::PermissionDenied { path }) if path == path_string(&source)
        ),
        "permission error should carry the indexed source path"
    );
    assert_eq!(
        fs::read(&source).expect("read source after permission failure"),
        b"secret indexed bytes"
    );
    assert_no_index_side_effects(repo.path());
}
