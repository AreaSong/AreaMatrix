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

fn copied_options(filename: &str) -> ImportOptions {
    copied_options_with_strategy(filename, DuplicateStrategy::Skip)
}

fn copied_options_with_strategy(filename: &str, strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: strategy,
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
        .expect("count change log rows")
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

fn change_log_actions(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action FROM change_log ORDER BY id ASC")
        .expect("prepare change-log action query");
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query change-log actions")
        .map(|row| row.expect("read change-log action"))
        .collect()
}

fn change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = ?2",
            (file_id, action),
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse change detail")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn fill_numbered_conflicts(directory: &Path, filename: &str, content_prefix: &str) {
    fs::create_dir_all(directory).expect("create conflict directory");
    fs::write(directory.join(filename), format!("{content_prefix}-base"))
        .expect("write base conflict file");
    for index in 1..1000 {
        let name = format!("same_{index}.pdf");
        fs::write(directory.join(name), format!("{content_prefix}-{index}"))
            .expect("write numbered conflict file");
    }
}

fn install_deleted_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_deleted_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'deleted'
             BEGIN
                 SELECT RAISE(FAIL, 'forced deleted change-log failure');
             END;",
        )
        .expect("install deleted change-log failure trigger");
}

#[test]
fn resolve_name_conflict_replace_same_name_different_content_replaces_confirmed_target() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root_a, source_a) = source_file("existing.pdf", b"existing content");
        let (_source_root_b, source_b) = source_file("replacement.pdf", b"replacement content");

        let existing = import_file(
            path_string(repo.path()),
            path_string(&source_a),
            copied_options("same.pdf"),
        )
        .expect("import existing same-name target");
        let replacement = import_file(
            path_string(repo.path()),
            path_string(&source_b),
            copied_options_with_strategy("same.pdf", DuplicateStrategy::Overwrite),
        )
        .expect("replace same-name different-content target after S1-24 confirmation");

        assert_eq!(replacement.path, "finance/same.pdf");
        assert_eq!(replacement.current_name, "same.pdf");
        assert_ne!(replacement.id, existing.id);
        assert_ne!(replacement.hash_sha256, existing.hash_sha256);
        assert_eq!(
            fs::read(repo.path().join("finance/same.pdf")).expect("read replacement final file"),
            b"replacement content"
        );
        assert_eq!(
            fs::read(&source_b).expect("read copied replacement source"),
            b"replacement content"
        );

        let (archived_path, archived_name, old_status) = file_row(repo.path(), existing.id);
        assert_eq!(archived_name, "same.pdf");
        assert_eq!(old_status, "deleted");
        assert!(archived_path.starts_with("system-trash://replace-"));
        assert!(!repo.path().join(".areamatrix/trash").exists());
        assert_eq!(
            file_row(repo.path(), replacement.id),
            (
                "finance/same.pdf".to_owned(),
                "same.pdf".to_owned(),
                "active".to_owned(),
            )
        );
        assert_eq!(count_file_rows(repo.path(), "active"), 1);
        assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
        assert_eq!(count_file_rows(repo.path(), "staging"), 0);
        assert_eq!(
            change_log_actions(repo.path()),
            vec!["imported", "deleted", "imported"]
        );
        assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

        let deleted_detail = change_detail(repo.path(), existing.id, "deleted");
        assert_eq!(deleted_detail["reason"], "name_conflict_replace");
        assert_eq!(deleted_detail["from_path"], "finance/same.pdf");
        assert_eq!(deleted_detail["archived_path"], archived_path);
        assert_eq!(deleted_detail["trash_location"], "system");
        assert_eq!(deleted_detail["trashed"], true);
        assert_eq!(
            fs::read(trash_dir.join("same.pdf")).expect("read old file from system Trash"),
            b"existing content"
        );
        let import_detail = change_detail(repo.path(), replacement.id, "imported");
        assert_eq!(import_detail["duplicate_strategy"], "overwrite");
        assert_eq!(import_detail["replace_reason"], "name_conflict_replace");
        assert_eq!(import_detail["replaced_file_id"], existing.id);
        assert_eq!(import_detail["replaced_path"], "finance/same.pdf");
        assert_eq!(import_detail["final_path"], "finance/same.pdf");
    });
}

#[test]
fn resolve_name_conflict_replace_same_name_db_failure_restores_original_target() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let (_source_root_a, source_a) = source_file("existing.pdf", b"existing content");
        let (_source_root_b, source_b) = source_file("replacement.pdf", b"replacement content");
        let existing = import_file(
            path_string(repo.path()),
            path_string(&source_a),
            copied_options("same.pdf"),
        )
        .expect("import existing same-name target");
        install_deleted_change_log_failure(repo.path());

        let result = import_file(
            path_string(repo.path()),
            path_string(&source_b),
            copied_options_with_strategy("same.pdf", DuplicateStrategy::Overwrite),
        );

        assert_eq!(result, Err(CoreError::Db));
        assert_eq!(
            fs::read(repo.path().join("finance/same.pdf")).expect("read restored existing file"),
            b"existing content"
        );
        assert_eq!(
            fs::read(&source_b).expect("read copied replacement source after rollback"),
            b"replacement content"
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
        assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
        assert_eq!(count_file_rows(repo.path(), "staging"), 0);
        assert_eq!(change_log_count(repo.path()), 1);
        assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
    });
}

#[test]
fn resolve_name_conflict_import_exhaustion_returns_conflict_without_side_effects() {
    let repo = initialized_repo();
    let conflict_dir = repo.path().join("finance");
    fill_numbered_conflicts(&conflict_dir, "same.pdf", "existing");
    let (_source_root, source) = source_file("source.pdf", b"new content");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("same.pdf"),
    );

    assert_eq!(result, Err(CoreError::Conflict));
    assert_eq!(
        fs::read(&source).expect("read copied source"),
        b"new content"
    );
    assert_eq!(
        fs::read(conflict_dir.join("same.pdf")).expect("read existing base conflict"),
        b"existing-base"
    );
    assert!(!conflict_dir.join("same_1000.pdf").exists());
    assert_eq!(count_file_rows(repo.path(), "active"), 0);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn resolve_name_conflict_rename_exhaustion_returns_conflict_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("source.pdf", b"rename content");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("draft.pdf"),
    )
    .expect("import file before rename conflict");
    let conflict_dir = repo.path().join("finance");
    fill_numbered_conflicts(&conflict_dir, "same.pdf", "existing");

    let result = rename_file(path_string(repo.path()), entry.id, "same.pdf".to_owned());

    assert_eq!(result, Err(CoreError::Conflict));
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read original file"),
        b"rename content"
    );
    assert_eq!(
        fs::read(conflict_dir.join("same.pdf")).expect("read existing base conflict"),
        b"existing-base"
    );
    assert!(!conflict_dir.join("same_1000.pdf").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
