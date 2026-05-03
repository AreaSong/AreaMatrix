use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    delete_file, import_file, init_repo, remove_index_entry, write_note, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

mod support;

use support::system_trash_home::with_test_system_trash;

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

fn file_status(repo: &Path, file_id: i64) -> (String, Option<i64>) {
    open_db(repo)
        .query_row(
            "SELECT status, deleted_at FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read file status")
}

fn note_content(repo: &Path, file_id: i64) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .optional()
        .expect("read note content")
}

fn action_count(repo: &Path, file_id: i64, action: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = ?2",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("count change action")
}

fn archive_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/archives"))
        .expect("read archives directory")
        .map(|entry| entry.expect("read archive entry").path())
        .collect()
}

fn trash_entries(trash_dir: &Path) -> Vec<PathBuf> {
    fs::read_dir(trash_dir)
        .expect("read trash directory")
        .map(|entry| entry.expect("read trash entry").path())
        .collect()
}

fn install_change_log_failure(repo: &Path, action: &str) {
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER fail_{action}_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = '{action}'
             BEGIN
                 SELECT RAISE(FAIL, 'forced {action} change log failure');
             END;"
        ))
        .expect("install change-log failure trigger");
}

fn remove_change_log_failure(repo: &Path, action: &str) {
    open_db(repo)
        .execute_batch(&format!("DROP TRIGGER fail_{action}_change_log;"))
        .expect("remove change-log failure trigger");
}

#[test]
fn delete_remove_index_failure_recovery_delete_db_failure_restores_file_note_and_retry() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("report.pdf", b"report bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "report.pdf"),
        )
        .expect("import copied file");
        write_note(path_string(repo.path()), entry.id, "keep note".to_owned())
            .expect("write note before failed delete");
        install_change_log_failure(repo.path(), "deleted");

        let failed = delete_file(path_string(repo.path()), entry.id);

        assert!(matches!(failed, Err(CoreError::Db { .. })));
        assert_eq!(
            fs::read(repo.path().join(&entry.path)).expect("read restored repo file"),
            b"report bytes"
        );
        assert_eq!(
            file_status(repo.path(), entry.id),
            ("active".to_owned(), None)
        );
        assert_eq!(
            note_content(repo.path(), entry.id),
            Some("keep note".to_owned())
        );
        assert_eq!(action_count(repo.path(), entry.id, "deleted"), 0);
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());

        remove_change_log_failure(repo.path(), "deleted");
        delete_file(path_string(repo.path()), entry.id).expect("retry delete after DB recovery");
        assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
        assert_eq!(action_count(repo.path(), entry.id, "deleted"), 1);
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read retried delete from system trash"),
            b"report bytes"
        );
    });
}

#[test]
fn delete_remove_index_failure_recovery_remove_index_db_failure_keeps_source_and_retry() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("external.pdf", b"external bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Indexed, "external.pdf"),
        )
        .expect("import indexed file");
        install_change_log_failure(repo.path(), "removed_from_index");

        let failed = remove_index_entry(path_string(repo.path()), entry.id);

        assert!(matches!(failed, Err(CoreError::Db { .. })));
        assert_eq!(
            fs::read(&source).expect("read indexed source after failed remove"),
            b"external bytes"
        );
        assert_eq!(
            file_status(repo.path(), entry.id),
            ("active".to_owned(), None)
        );
        assert_eq!(action_count(repo.path(), entry.id, "removed_from_index"), 0);
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());

        remove_change_log_failure(repo.path(), "removed_from_index");
        remove_index_entry(path_string(repo.path()), entry.id)
            .expect("retry remove index after DB recovery");
        assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
        assert_eq!(action_count(repo.path(), entry.id, "removed_from_index"), 1);
        assert_eq!(
            fs::read(&source).expect("read indexed source after retried remove"),
            b"external bytes"
        );
    });
}

#[test]
fn delete_remove_index_failure_recovery_delete_missing_repo_file_preserves_metadata() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("missing.pdf", b"missing bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "missing.pdf"),
        )
        .expect("import copied file");
        write_note(path_string(repo.path()), entry.id, "still here".to_owned())
            .expect("write note before external removal");
        fs::remove_file(repo.path().join(&entry.path))
            .expect("simulate externally missing repo file");

        let result = delete_file(path_string(repo.path()), entry.id);

        assert!(matches!(result, Err(CoreError::FileNotFound { .. })));
        assert_eq!(
            file_status(repo.path(), entry.id),
            ("active".to_owned(), None)
        );
        assert_eq!(
            note_content(repo.path(), entry.id),
            Some("still here".to_owned())
        );
        assert_eq!(action_count(repo.path(), entry.id, "deleted"), 0);
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());
    });
}

#[test]
fn delete_remove_index_failure_recovery_remove_missing_external_source_only_drops_index() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("external.pdf", b"external bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Indexed, "external.pdf"),
        )
        .expect("import indexed file");
        fs::remove_file(&source).expect("simulate missing external source");

        remove_index_entry(path_string(repo.path()), entry.id)
            .expect("remove missing external source metadata");

        assert!(!source.exists());
        assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
        assert_eq!(action_count(repo.path(), entry.id, "removed_from_index"), 1);
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
    });
}

#[test]
fn delete_remove_index_failure_recovery_repeated_operations_are_not_destructive() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_owned_source_root, owned_source) = source_file("owned.pdf", b"owned bytes");
        let owned = import_file(
            path_string(repo.path()),
            path_string(&owned_source),
            import_options(StorageMode::Copied, "owned.pdf"),
        )
        .expect("import copied file");
        delete_file(path_string(repo.path()), owned.id).expect("delete copied file once");

        let (_indexed_source_root, indexed_source) = source_file("indexed.pdf", b"indexed bytes");
        let indexed = import_file(
            path_string(repo.path()),
            path_string(&indexed_source),
            import_options(StorageMode::Indexed, "indexed.pdf"),
        )
        .expect("import indexed file");
        remove_index_entry(path_string(repo.path()), indexed.id).expect("remove indexed file once");

        assert!(matches!(
            delete_file(path_string(repo.path()), owned.id),
            Err(CoreError::FileNotFound { .. })
        ));
        assert!(matches!(
            remove_index_entry(path_string(repo.path()), indexed.id),
            Err(CoreError::FileNotFound { .. })
        ));
        assert_eq!(action_count(repo.path(), owned.id, "deleted"), 1);
        assert_eq!(
            action_count(repo.path(), indexed.id, "removed_from_index"),
            1
        );
        assert_eq!(
            fs::read(&indexed_source).expect("indexed source remains after repeated remove"),
            b"indexed bytes"
        );
        assert_eq!(trash_entries(trash_dir).len(), 1);
    });
}
