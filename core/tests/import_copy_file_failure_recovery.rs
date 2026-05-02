use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, CoreError, DuplicateStrategy, FileFilter, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
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

fn copied_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn count_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count rows by file status")
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
fn import_copy_file_failure_recovery_rolls_back_final_file_when_db_promotion_fails() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(fs::read(&source).expect("read source"), b"invoice bytes");
    assert!(!repo.path().join("finance/invoice.pdf").exists());
    assert!(!repo.path().join("finance").exists());
    assert_eq!(count_rows(repo.path(), "active"), 0);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_copy_file_failure_recovery_failed_attempt_can_be_retried() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"retry bytes");
    install_import_change_log_failure(repo.path());

    let failed = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    );

    assert_eq!(failed, Err(CoreError::Db));
    remove_import_change_log_failure(repo.path());

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("retry import after recovered DB failure");

    assert_eq!(entry.path, "finance/invoice.pdf");
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read retried import"),
        b"retry bytes"
    );
    assert_eq!(fs::read(&source).expect("read source"), b"retry bytes");
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let files =
        area_matrix_core::list_files(path_string(repo.path()), empty_filter()).expect("list files");
    assert_eq!(files, vec![entry]);
}

#[test]
fn import_copy_file_failure_recovery_duplicate_ask_leaves_no_side_effects() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(),
    )
    .expect("import first file");

    let mut options = copied_options();
    options.duplicate_strategy = DuplicateStrategy::Ask;
    let result = import_file(path_string(repo.path()), path_string(&source_b), options);

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == "finance/first.pdf"
        ),
        "duplicate error should report the existing imported path"
    );
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source"),
        b"same bytes"
    );
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[cfg(unix)]
#[test]
fn import_copy_file_failure_recovery_permission_denied_leaves_no_side_effects() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_source_root, source) = source_file("secret.pdf", b"secret bytes");
    let original_permissions = fs::metadata(&source)
        .expect("read source metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&source, blocked_permissions).expect("remove source read permissions");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    );

    fs::set_permissions(&source, original_permissions).expect("restore source permissions");

    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert!(!repo.path().join("finance").exists());
    assert_eq!(count_rows(repo.path(), "active"), 0);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
