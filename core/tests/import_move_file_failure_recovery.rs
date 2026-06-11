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

fn moved_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Moved,
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

fn assert_no_import_side_effects(repo: &Path) {
    assert_eq!(file_count(repo, "active"), 0);
    assert_eq!(file_count(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn install_file_insert_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_import_file_insert
             BEFORE INSERT ON files
             WHEN NEW.status = 'staging'
             BEGIN
               SELECT RAISE(ABORT, 'forced import file insert failure');
             END;",
        )
        .expect("install import file insert failure trigger");
}

fn remove_file_insert_failure(repo: &Path) {
    open_db(repo)
        .execute_batch("DROP TRIGGER fail_import_file_insert;")
        .expect("remove import file insert failure trigger");
}

#[test]
fn import_move_file_failure_recovery_db_staging_insert_restores_source() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"staging insert failure");
    install_file_insert_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_options(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(
        fs::read(&source).expect("read restored moved source"),
        b"staging insert failure"
    );
    assert!(!repo.path().join("finance").exists());
    assert_no_import_side_effects(repo.path());
}

#[test]
fn import_move_file_failure_recovery_failed_attempt_can_be_retried() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"retry after recovery");
    install_file_insert_failure(repo.path());

    let failed = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_options(),
    );

    assert!(matches!(failed, Err(CoreError::Db { .. })));

    assert_eq!(
        fs::read(&source).expect("read source restored after failed attempt"),
        b"retry after recovery"
    );
    remove_file_insert_failure(repo.path());

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_options(),
    )
    .expect("retry moved import after rollback");

    assert!(
        !source.exists(),
        "successful retry should consume moved source"
    );
    assert_eq!(entry.path, "finance/invoice.pdf");
    assert_eq!(entry.storage_mode, StorageMode::Moved);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read retried final file"),
        b"retry after recovery"
    );
    assert_eq!(file_count(repo.path(), "active"), 1);
    assert_eq!(file_count(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let files =
        list_files(path_string(repo.path()), empty_filter()).expect("list files after retry");
    assert_eq!(files, vec![entry]);
}

#[cfg(unix)]
#[test]
fn import_move_file_failure_recovery_permission_denied_restores_source() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let finance_dir = repo.path().join("finance");
    fs::create_dir(&finance_dir).expect("create target category directory");
    let original_permissions = fs::metadata(&finance_dir)
        .expect("read target directory metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o500);
    fs::set_permissions(&finance_dir, blocked_permissions).expect("make target directory readonly");

    let (_source_root, source) = source_file("invoice.pdf", b"permission denied recovery");
    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_options(),
    );

    fs::set_permissions(&finance_dir, original_permissions).expect("restore target permissions");

    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert_eq!(
        fs::read(&source).expect("read source restored after permission failure"),
        b"permission denied recovery"
    );
    assert!(!finance_dir.join("invoice.pdf").exists());
    assert_no_import_side_effects(repo.path());
}
