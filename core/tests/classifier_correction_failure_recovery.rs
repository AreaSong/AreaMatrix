use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    correct_file_category, import_file, init_repo, CoreError, DuplicateStrategy, ErrorKind,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
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

fn import_options(mode: StorageMode, category: &str, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, storage_mode FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read file row")
}

fn moved_change_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = 'moved'",
            [file_id],
            |row| row.get(0),
        )
        .expect("count moved change rows")
}

fn install_moved_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_classifier_correction_moved_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'moved'
             BEGIN
               SELECT RAISE(ABORT, 'forced classifier correction change_log failure');
             END;",
        )
        .expect("install moved change-log failure trigger");
}

fn assert_error_kind<T: std::fmt::Debug>(result: Result<T, CoreError>, expected_kind: ErrorKind) {
    let error = result.expect_err("operation should fail");
    assert_eq!(error.to_error_mapping().kind, expected_kind);
    assert!(
        !error.to_error_mapping().raw_context.is_empty(),
        "mapped classifier correction errors keep observable context"
    );
}

#[test]
fn classifier_correction_failure_recovery_empty_and_invalid_inputs_do_not_mutate() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("manual.pdf", b"manual bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "manual.pdf"),
    )
    .expect("import copied file before invalid-input checks");
    let before = file_row(repo.path(), entry.id);

    assert_error_kind(
        correct_file_category(String::new(), entry.id, "finance".to_owned(), true, false),
        ErrorKind::Db,
    );
    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            0,
            "finance".to_owned(),
            true,
            false,
        ),
        ErrorKind::Db,
    );
    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            entry.id,
            String::new(),
            true,
            false,
        ),
        ErrorKind::Classify,
    );
    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            entry.id,
            "Bad Category".to_owned(),
            true,
            true,
        ),
        ErrorKind::Classify,
    );

    assert_eq!(file_row(repo.path(), entry.id), before);
    assert_eq!(
        fs::read(repo.path().join("docs/manual.pdf")).expect("read original file"),
        b"manual bytes"
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn classifier_correction_failure_recovery_unknown_category_is_classify_error() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("manual.pdf", b"manual bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "manual.pdf"),
    )
    .expect("import copied file before unknown-category check");
    let before = file_row(repo.path(), entry.id);

    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            entry.id,
            "unknown".to_owned(),
            true,
            true,
        ),
        ErrorKind::Classify,
    );

    assert_eq!(file_row(repo.path(), entry.id), before);
    assert_eq!(
        fs::read(repo.path().join("docs/manual.pdf")).expect("read original file"),
        b"manual bytes"
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn classifier_correction_failure_recovery_missing_file_is_io_error_without_mutation() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("missing.pdf", b"missing bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "missing.pdf"),
    )
    .expect("import copied file before missing-file check");
    fs::remove_file(repo.path().join("docs/missing.pdf")).expect("remove repo-owned file");
    let before = file_row(repo.path(), entry.id);

    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            entry.id,
            "finance".to_owned(),
            true,
            false,
        ),
        ErrorKind::Io,
    );

    assert_eq!(file_row(repo.path(), entry.id), before);
    assert!(!repo.path().join("finance/missing.pdf").exists());
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn classifier_correction_failure_recovery_target_conflict_does_not_overwrite() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("same.pdf", b"source bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "same.pdf"),
    )
    .expect("import copied file before target-conflict check");
    let finance_dir = repo.path().join("finance");
    fs::create_dir(&finance_dir).expect("create target category directory");
    fs::write(finance_dir.join("same.pdf"), b"existing target").expect("write existing target");

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        true,
        false,
    )
    .expect("apply correction with safe numbered target");

    assert_eq!(result.updated_file.path, "finance/same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read pre-existing target"),
        b"existing target"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/same_1.pdf")).expect("read moved numbered file"),
        b"source bytes"
    );
    assert!(!repo.path().join("docs/same.pdf").exists());
}

#[test]
fn classifier_correction_failure_recovery_db_failure_restores_moved_file() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("rollback.pdf", b"rollback bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "rollback.pdf"),
    )
    .expect("import copied file before rollback check");
    let before = file_row(repo.path(), entry.id);
    install_moved_change_log_failure(repo.path());

    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            entry.id,
            "finance".to_owned(),
            true,
            false,
        ),
        ErrorKind::Db,
    );

    assert_eq!(file_row(repo.path(), entry.id), before);
    assert_eq!(
        fs::read(repo.path().join("docs/rollback.pdf")).expect("read restored original file"),
        b"rollback bytes"
    );
    assert!(!repo.path().join("finance/rollback.pdf").exists());
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[cfg(unix)]
#[test]
fn classifier_correction_failure_recovery_permission_denied_keeps_original_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("locked.pdf", b"locked bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "locked.pdf"),
    )
    .expect("import copied file before permission check");
    let finance_dir = repo.path().join("finance");
    fs::create_dir(&finance_dir).expect("create finance directory");
    let _mode_guard = UnixModeGuard::set(&finance_dir, 0o500);
    let before = file_row(repo.path(), entry.id);

    assert_error_kind(
        correct_file_category(
            path_string(repo.path()),
            entry.id,
            "finance".to_owned(),
            true,
            false,
        ),
        ErrorKind::Io,
    );

    assert_eq!(file_row(repo.path(), entry.id), before);
    assert_eq!(
        fs::read(repo.path().join("docs/locked.pdf")).expect("read original file"),
        b"locked bytes"
    );
    assert!(!finance_dir.join("locked.pdf").exists());
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[cfg(unix)]
struct UnixModeGuard {
    path: PathBuf,
    mode: u32,
}

#[cfg(unix)]
impl UnixModeGuard {
    fn set(path: &Path, mode: u32) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let original_mode = fs::metadata(path)
            .expect("read directory permissions")
            .permissions()
            .mode();
        let mut permissions = fs::metadata(path)
            .expect("read directory permissions before update")
            .permissions();
        permissions.set_mode(mode);
        fs::set_permissions(path, permissions).expect("set directory permissions");
        Self {
            path: path.to_path_buf(),
            mode: original_mode,
        }
    }
}

#[cfg(unix)]
impl Drop for UnixModeGuard {
    fn drop(&mut self) {
        use std::os::unix::fs::PermissionsExt;

        if let Ok(metadata) = fs::metadata(&self.path) {
            let mut permissions = metadata.permissions();
            permissions.set_mode(self.mode);
            let _restore_result = fs::set_permissions(&self.path, permissions);
        }
    }
}
