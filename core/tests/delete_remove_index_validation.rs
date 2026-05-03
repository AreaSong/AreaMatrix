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

fn include_deleted_filter() -> FileFilter {
    FileFilter {
        include_deleted: Some(true),
        ..default_file_filter()
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

fn action_count(repo: &Path, file_id: i64, action: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = ?2",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("count change action")
}

fn latest_change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse change detail json")
}

fn trash_entries(trash_dir: &Path) -> Vec<PathBuf> {
    fs::read_dir(trash_dir)
        .expect("read trash directory")
        .map(|entry| entry.expect("read trash entry").path())
        .collect()
}

fn archive_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/archives"))
        .expect("read archives directory")
        .map(|entry| entry.expect("read archive entry").path())
        .collect()
}

fn sqlite_integrity_check(repo: &Path) -> String {
    open_db(repo)
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("run SQLite integrity_check")
}

fn foreign_key_violations(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("PRAGMA foreign_key_check")
        .expect("prepare foreign_key_check");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("run foreign_key_check");

    rows.map(|row| row.expect("read foreign_key_check row"))
        .collect()
}

fn assert_metadata_consistent(repo: &Path) {
    assert_eq!(sqlite_integrity_check(repo), "ok");
    assert!(foreign_key_violations(repo).is_empty());
}

#[test]
fn delete_remove_index_validation_delete_proves_trash_soft_delete_and_metadata_retention() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
        fs::create_dir_all(repo.path().join("finance")).expect("create finance directory");
        fs::write(repo.path().join("finance/keeper.txt"), b"keeper")
            .expect("write unrelated repo file");
        let (_source_root, source) = source_file("report.pdf", b"report bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "report.pdf"),
        )
        .expect("import copied file before validation delete");
        write_note(
            path_string(repo.path()),
            entry.id,
            "preserve this note".to_owned(),
        )
        .expect("write note before validation delete");

        delete_file(path_string(repo.path()), entry.id).expect("delete repo-owned file");

        assert!(!repo.path().join(&entry.path).exists());
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read deleted file from system Trash"),
            b"report bytes"
        );
        assert_eq!(
            fs::read(&source).expect("copied source remains untouched"),
            b"report bytes"
        );
        assert_eq!(
            fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
            "user readme\n"
        );
        assert_eq!(
            fs::read(repo.path().join("finance/keeper.txt")).expect("read unrelated repo file"),
            b"keeper"
        );
        assert_eq!(
            note_content(repo.path(), entry.id),
            Some("preserve this note".to_owned())
        );
        assert!(repo.path().join("finance/report.pdf.md").exists());

        let (status, deleted_at) = file_status(repo.path(), entry.id);
        assert_eq!(status, "deleted");
        assert!(deleted_at.is_some(), "deleted_at should be populated");
        assert!(matches!(
            get_file(path_string(repo.path()), entry.id),
            Err(CoreError::FileNotFound { .. })
        ));
        assert_eq!(
            list_files(path_string(repo.path()), default_file_filter()).expect("list active files"),
            Vec::new()
        );
        assert_eq!(
            list_files(path_string(repo.path()), include_deleted_filter())
                .expect("list deleted files")
                .len(),
            1
        );
        assert_eq!(
            list_changes(path_string(repo.path()), change_filter(entry.id))
                .expect("list change history")
                .iter()
                .map(|change| change.action.as_str())
                .collect::<Vec<_>>(),
            vec!["deleted", "edited_note", "imported"]
        );

        let detail = latest_change_detail(repo.path(), entry.id, "deleted");
        assert_eq!(detail["hard"], false);
        assert_eq!(detail["by"], "user");
        assert_eq!(detail["from_path"], "finance/report.pdf");
        assert_eq!(detail["trash_location"], "system");
        assert_eq!(detail["trashed"], true);
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());
        assert_metadata_consistent(repo.path());
    });
}

#[test]
fn delete_remove_index_validation_remove_index_preserves_present_and_missing_sources() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_present_root, present_source) = source_file("present.pdf", b"present bytes");
        let present = import_file(
            path_string(repo.path()),
            path_string(&present_source),
            import_options(StorageMode::Indexed, "present.pdf"),
        )
        .expect("import present indexed source");
        let (_missing_root, missing_source) = source_file("missing.pdf", b"missing bytes");
        let missing = import_file(
            path_string(repo.path()),
            path_string(&missing_source),
            import_options(StorageMode::Indexed, "missing.pdf"),
        )
        .expect("import soon-missing indexed source");
        fs::remove_file(&missing_source).expect("simulate missing indexed source");

        remove_index_entry(path_string(repo.path()), present.id)
            .expect("remove present indexed entry");
        remove_index_entry(path_string(repo.path()), missing.id)
            .expect("remove missing indexed entry");

        assert_eq!(
            fs::read(&present_source).expect("read present indexed source after remove"),
            b"present bytes"
        );
        assert!(!missing_source.exists());
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        assert_eq!(file_status(repo.path(), present.id).0, "deleted");
        assert_eq!(file_status(repo.path(), missing.id).0, "deleted");
        assert_eq!(
            action_count(repo.path(), present.id, "removed_from_index"),
            1
        );
        assert_eq!(
            action_count(repo.path(), missing.id, "removed_from_index"),
            1
        );
        assert_eq!(
            list_files(path_string(repo.path()), default_file_filter()).expect("list active files"),
            Vec::new()
        );

        let detail = latest_change_detail(repo.path(), present.id, "removed_from_index");
        assert_eq!(detail["index_only"], true);
        assert_eq!(detail["storage_mode"], "indexed");
        assert_eq!(detail["origin"], "imported");
        assert_eq!(detail["path"], path_string(&present_source));
        assert_metadata_consistent(repo.path());
    });
}

#[test]
fn delete_remove_index_validation_error_paths_do_not_mutate_files_or_metadata() {
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
        assert!(matches!(
            delete_file(path_string(repo.path()), 9_999_999),
            Err(CoreError::FileNotFound { .. })
        ));
        assert!(matches!(
            remove_index_entry(path_string(repo.path()), 9_999_999),
            Err(CoreError::FileNotFound { .. })
        ));

        assert_eq!(
            fs::read(&indexed_source).expect("indexed source remains after rejected delete"),
            b"external bytes"
        );
        assert_eq!(
            fs::read(repo.path().join(&copied.path))
                .expect("copied repo file remains after rejected remove"),
            b"owned bytes"
        );
        assert_eq!(
            file_status(repo.path(), indexed.id),
            ("active".to_owned(), None)
        );
        assert_eq!(
            file_status(repo.path(), copied.id),
            ("active".to_owned(), None)
        );
        assert_eq!(action_count(repo.path(), indexed.id, "deleted"), 0);
        assert_eq!(
            action_count(repo.path(), copied.id, "removed_from_index"),
            0
        );
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        assert_metadata_consistent(repo.path());
    });
}
