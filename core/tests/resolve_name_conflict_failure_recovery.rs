use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, rename_file, CoreError, DuplicateStrategy, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
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

fn import_options(mode: StorageMode, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn count_file_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, status FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn install_import_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced import change-log failure');
             END;",
        )
        .expect("install import change-log failure trigger");
}

fn install_rename_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_rename_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'renamed'
             BEGIN
               SELECT RAISE(ABORT, 'forced rename change-log failure');
             END;",
        )
        .expect("install rename change-log failure trigger");
}

fn assert_no_staging_residue(repo: &Path) {
    assert_eq!(count_file_rows(repo, "staging"), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn fill_numbered_conflicts(directory: &Path, filename: &str, content_prefix: &str) {
    fs::create_dir_all(directory).expect("create conflict directory");
    fs::write(directory.join(filename), format!("{content_prefix}-base"))
        .expect("write base conflict file");
    for index in 1..1000 {
        fs::write(
            directory.join(format!("same_{index}.pdf")),
            format!("{content_prefix}-{index}"),
        )
        .expect("write numbered conflict file");
    }
}

#[test]
fn resolve_name_conflict_failure_recovery_import_db_failure_removes_numbered_final() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"existing bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"new bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name target");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, "same.pdf"),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing target"),
        b"existing bytes"
    );
    assert!(!repo.path().join("finance/same_1.pdf").exists());
    assert_eq!(
        fs::read(&source_b).expect("read copied source after failed import"),
        b"new bytes"
    );
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_no_staging_residue(repo.path());
}

#[test]
fn resolve_name_conflict_failure_recovery_moved_exhaustion_restores_source_and_retries() {
    let repo = initialized_repo();
    let conflict_dir = repo.path().join("finance");
    fill_numbered_conflicts(&conflict_dir, "same.pdf", "existing");
    let (_source_root, source) = source_file("source.pdf", b"moved bytes");

    let failed = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Moved, "same.pdf"),
    );

    assert_eq!(failed, Err(CoreError::Conflict));
    assert_eq!(
        fs::read(&source).expect("read restored moved source after conflict exhaustion"),
        b"moved bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_no_staging_residue(repo.path());

    fs::remove_file(conflict_dir.join("same_999.pdf")).expect("free one numbered slot");
    let retried = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Moved, "same.pdf"),
    )
    .expect("retry after conflict slot is available");

    assert_eq!(retried.path, "finance/same_999.pdf");
    assert_eq!(retried.current_name, "same_999.pdf");
    assert_eq!(
        fs::read(repo.path().join(&retried.path)).expect("read retried moved import"),
        b"moved bytes"
    );
    assert!(!source.exists());
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_no_staging_residue(repo.path());
}

#[test]
fn resolve_name_conflict_failure_recovery_rename_db_failure_restores_original_name() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("existing.pdf", b"existing bytes");
    let (_source_root_b, source_b) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name target");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import file to rename");
    install_rename_change_log_failure(repo.path());

    let result = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned());

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing target"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read restored draft file"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/same_1.pdf").exists());
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_row(repo.path(), draft.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(change_log_count(repo.path()), 2);
    assert_no_staging_residue(repo.path());
}

#[cfg(unix)]
#[test]
fn resolve_name_conflict_failure_recovery_import_permission_denied_keeps_old_target() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("existing.pdf", b"existing bytes");
    let (_source_root_b, source_b) = source_file("new.pdf", b"new bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name target");
    let finance_dir = repo.path().join("finance");
    let original_permissions = fs::metadata(&finance_dir)
        .expect("read finance directory metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o500);
    fs::set_permissions(&finance_dir, blocked_permissions).expect("make target directory readonly");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, "same.pdf"),
    );

    fs::set_permissions(&finance_dir, original_permissions).expect("restore target permissions");

    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing target"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read copied source after permission failure"),
        b"new bytes"
    );
    assert!(!repo.path().join("finance/same_1.pdf").exists());
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_no_staging_residue(repo.path());
}

#[cfg(unix)]
#[test]
fn resolve_name_conflict_failure_recovery_rename_permission_denied_keeps_both_files() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("existing.pdf", b"existing bytes");
    let (_source_root_b, source_b) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name target");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import file to rename");
    let finance_dir = repo.path().join("finance");
    let original_permissions = fs::metadata(&finance_dir)
        .expect("read finance directory metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o500);
    fs::set_permissions(&finance_dir, blocked_permissions).expect("make target directory readonly");

    let result = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned());

    fs::set_permissions(&finance_dir, original_permissions).expect("restore target permissions");

    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing target"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read original draft"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/same_1.pdf").exists());
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_row(repo.path(), draft.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(change_log_count(repo.path()), 2);
    assert_no_staging_residue(repo.path());
}
