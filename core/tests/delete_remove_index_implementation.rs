use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    delete_file, get_file, import_file, init_repo, list_changes, list_files, remove_index_entry,
    write_note, ChangeFilter, CoreError, DuplicateStrategy, FileFilter, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};
use serde_json::Value;

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

fn default_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn change_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
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

fn change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse detail json")
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

fn install_deleted_status_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_delete_status
             BEFORE UPDATE OF status ON files
             WHEN NEW.status = 'deleted' AND OLD.status = 'active'
             BEGIN
                 SELECT RAISE(FAIL, 'forced delete status failure');
             END;",
        )
        .expect("install delete status failure trigger");
}

#[test]
fn delete_remove_index_implementation_delete_moves_repo_owned_file_to_trash_and_logs() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("report.pdf", b"report bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "report.pdf"),
        )
        .expect("import copied file");
        write_note(
            path_string(repo.path()),
            entry.id,
            "keep this note".to_owned(),
        )
        .expect("write note before delete");

        delete_file(path_string(repo.path()), entry.id).expect("delete repo-owned file");

        assert!(!repo.path().join(&entry.path).exists());
        assert_eq!(
            fs::read(&source).expect("read copied source"),
            b"report bytes"
        );
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read file from system trash"),
            b"report bytes"
        );
        let (status, deleted_at) = file_status(repo.path(), entry.id);
        assert_eq!(status, "deleted");
        assert!(deleted_at.is_some(), "deleted_at should be populated");
        assert_eq!(
            note_content(repo.path(), entry.id),
            Some("keep this note".to_owned())
        );
        assert!(repo.path().join("finance/report.pdf.md").exists());
        assert!(matches!(
            get_file(path_string(repo.path()), entry.id),
            Err(CoreError::FileNotFound { .. })
        ));
        assert_eq!(
            list_files(path_string(repo.path()), default_file_filter())
                .expect("list visible files")
                .len(),
            0
        );
        assert_eq!(
            list_changes(path_string(repo.path()), change_filter(entry.id))
                .expect("list changes")
                .iter()
                .map(|change| change.action.as_str())
                .collect::<Vec<_>>(),
            vec!["deleted", "edited_note", "imported"]
        );

        let detail = change_detail(repo.path(), entry.id, "deleted");
        assert_eq!(detail["hard"], false);
        assert_eq!(detail["by"], "user");
        assert_eq!(detail["from_path"], "finance/report.pdf");
        assert_eq!(detail["storage_mode"], "copied");
        assert_eq!(detail["trash_location"], "system");
        assert_eq!(detail["trashed"], true);
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());
    });
}

#[test]
fn delete_remove_index_implementation_remove_index_hides_entry_without_touching_source() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("external.pdf", b"external bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Indexed, "external.pdf"),
        )
        .expect("import indexed file");

        remove_index_entry(path_string(repo.path()), entry.id).expect("remove index entry");

        assert_eq!(
            fs::read(&source).expect("read external source"),
            b"external bytes"
        );
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        let (status, deleted_at) = file_status(repo.path(), entry.id);
        assert_eq!(status, "deleted");
        assert!(deleted_at.is_some(), "deleted_at should be populated");
        assert!(matches!(
            get_file(path_string(repo.path()), entry.id),
            Err(CoreError::FileNotFound { .. })
        ));
        assert_eq!(
            list_files(path_string(repo.path()), default_file_filter())
                .expect("list visible files")
                .len(),
            0
        );
        assert_eq!(
            list_changes(path_string(repo.path()), change_filter(entry.id))
                .expect("list changes")
                .iter()
                .map(|change| change.action.as_str())
                .collect::<Vec<_>>(),
            vec!["removed_from_index", "imported"]
        );

        let detail = change_detail(repo.path(), entry.id, "removed_from_index");
        assert_eq!(detail["by"], "user");
        assert_eq!(detail["index_only"], true);
        assert_eq!(detail["path"], path_string(&source));
        assert_eq!(detail["storage_mode"], "indexed");
        assert_eq!(detail["origin"], "imported");
    });
}

#[test]
fn delete_remove_index_implementation_rejects_wrong_operation_without_side_effects() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_indexed_root, indexed_source) = source_file("external.pdf", b"external bytes");
        let indexed = import_file(
            path_string(repo.path()),
            path_string(&indexed_source),
            import_options(StorageMode::Indexed, "external.pdf"),
        )
        .expect("import indexed file");
        let (_copied_root, copied_source) = source_file("owned.pdf", b"owned bytes");
        let copied = import_file(
            path_string(repo.path()),
            path_string(&copied_source),
            import_options(StorageMode::Copied, "owned.pdf"),
        )
        .expect("import copied file");

        assert!(matches!(
            delete_file(path_string(repo.path()), indexed.id),
            Err(CoreError::PermissionDenied { .. })
        ));
        assert!(matches!(
            remove_index_entry(path_string(repo.path()), copied.id),
            Err(CoreError::PermissionDenied { .. })
        ));

        assert_eq!(
            fs::read(&indexed_source).expect("read indexed source"),
            b"external bytes"
        );
        assert_eq!(
            fs::read(repo.path().join(&copied.path)).expect("read copied repo file"),
            b"owned bytes"
        );
        assert_eq!(file_status(repo.path(), indexed.id).0, "active");
        assert_eq!(file_status(repo.path(), copied.id).0, "active");
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
    });
}

#[test]
fn delete_remove_index_implementation_db_failure_restores_repo_owned_file() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("report.pdf", b"report bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "report.pdf"),
        )
        .expect("import copied file");
        install_deleted_status_failure(repo.path());

        let result = delete_file(path_string(repo.path()), entry.id);

        assert!(matches!(result, Err(CoreError::Db { .. })));
        assert_eq!(
            fs::read(repo.path().join(&entry.path)).expect("read restored repo file"),
            b"report bytes"
        );
        assert_eq!(file_status(repo.path(), entry.id).0, "active");
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());
    });
}
