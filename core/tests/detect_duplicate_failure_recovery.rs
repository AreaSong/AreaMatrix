use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, CoreError, DuplicateStrategy, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
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
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn import_options(mode: StorageMode, strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: strategy,
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

fn file_status_and_path(repo: &Path, file_id: i64) -> (String, String) {
    open_db(repo)
        .query_row(
            "SELECT status, path FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read file status and path")
}

fn install_deleted_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_deleted_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'deleted'
             BEGIN
                 SELECT RAISE(FAIL, 'forced deleted change log failure');
             END;",
        )
        .expect("install deleted change log failure trigger");
}

fn remove_deleted_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch("DROP TRIGGER fail_deleted_change_log;")
        .expect("remove deleted change log failure trigger");
}

fn assert_clean_duplicate_state(repo: &Path, expected_change_logs: i64) {
    assert_eq!(count_rows(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), expected_change_logs);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

#[test]
fn detect_duplicate_failure_recovery_moved_ask_restores_source_without_final_side_effects() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, DuplicateStrategy::Skip),
    )
    .expect("import first copied file");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Moved, DuplicateStrategy::Ask),
    );

    assert_eq!(
        result,
        Err(CoreError::DuplicateFile {
            existing_path: first.path.clone()
        })
    );
    assert_eq!(
        fs::read(&source_b).expect("read restored moved duplicate source"),
        b"same bytes"
    );
    assert!(repo.path().join(&first.path).exists());
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_clean_duplicate_state(repo.path(), 1);
}

#[test]
fn detect_duplicate_failure_recovery_repeated_ask_is_idempotent() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, DuplicateStrategy::Skip),
    )
    .expect("import first copied file");

    for _attempt in 0..2 {
        let result = import_file(
            path_string(repo.path()),
            path_string(&source_b),
            import_options(StorageMode::Copied, DuplicateStrategy::Ask),
        );
        assert_eq!(
            result,
            Err(CoreError::DuplicateFile {
                existing_path: first.path.clone()
            })
        );
    }

    assert_eq!(
        fs::read(&source_b).expect("read duplicate source after repeated ask"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_clean_duplicate_state(repo.path(), 1);
}

#[test]
fn detect_duplicate_failure_recovery_overwrite_db_failure_can_be_retried() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("replacement.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    install_deleted_change_log_failure(repo.path());

    let failed = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, DuplicateStrategy::Overwrite),
    );

    assert_eq!(failed, Err(CoreError::Db));
    assert_eq!(
        fs::read(repo.path().join(&first.path)).expect("read restored original final file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read replacement source after failed overwrite"),
        b"same bytes"
    );
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "deleted"), 0);
    assert_clean_duplicate_state(repo.path(), 1);

    remove_deleted_change_log_failure(repo.path());
    let replacement = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, DuplicateStrategy::Overwrite),
    )
    .expect("retry overwrite duplicate after DB recovery");

    assert_eq!(replacement.path, first.path);
    assert_ne!(replacement.id, first.id);
    let (old_status, archived_path) = file_status_and_path(repo.path(), first.id);
    assert_eq!(old_status, "deleted");
    assert!(archived_path.starts_with(".areamatrix/trash/replace-"));
    assert_eq!(
        fs::read(repo.path().join(&replacement.path)).expect("read replacement final file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read copied replacement source after retry"),
        b"same bytes"
    );
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "deleted"), 1);
    assert_clean_duplicate_state(repo.path(), 3);
}

#[cfg(unix)]
#[test]
fn detect_duplicate_failure_recovery_permission_denied_preserves_existing_entry() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    let original_permissions = fs::metadata(&source_b)
        .expect("read duplicate source metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&source_b, blocked_permissions)
        .expect("remove duplicate source read permissions");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, DuplicateStrategy::Skip),
    );

    fs::set_permissions(&source_b, original_permissions)
        .expect("restore duplicate source permissions");

    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert_eq!(
        fs::read(repo.path().join(first.path)).expect("read existing final after permission error"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source after permission error"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_clean_duplicate_state(repo.path(), 1);
}
