use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, read_note, write_note, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_active_file(repo: &Path, relative_path: &str) -> i64 {
    let file_path = repo.join(relative_path);
    let parent = file_path.parent().expect("test file has parent directory");
    fs::create_dir_all(parent).expect("create file parent directory");
    fs::write(&file_path, b"document bytes").expect("write target file");

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("test path has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'finance', 14,
                ?3, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                format!("{:064x}", relative_path.len())
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_note_row(repo: &Path, file_id: i64, content: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at)
             VALUES (?1, ?2, 100)",
            params![file_id, content],
        )
        .expect("insert note row");
}

fn note_content(repo: &Path, file_id: i64) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .ok()
}

fn notes_row_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM notes WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("count notes rows")
}

fn sidecar_path(repo: &Path, relative_path: &str) -> std::path::PathBuf {
    repo.join(format!("{relative_path}.md"))
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change_log rows")
}

fn latest_edited_note_detail(repo: &Path, file_id: i64) -> Value {
    let detail: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = 'edited_note'
             ORDER BY id DESC LIMIT 1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read latest edited_note detail");
    serde_json::from_str(&detail).expect("edited_note detail is valid JSON")
}

fn install_edited_note_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_edited_note_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'edited_note'
             BEGIN
               SELECT RAISE(ABORT, 'edited note change log failure');
             END;",
        )
        .expect("install change_log failure trigger");
}

#[test]
fn read_write_note_validation_proves_empty_read_successful_write_and_consistency() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    let content = "# Note\n\n- café\n- 中文".to_owned();

    assert_eq!(read_note(path_string(repo.path()), file_id), Ok(None));

    write_note(path_string(repo.path()), file_id, content.clone()).expect("write note");

    assert_eq!(
        read_note(path_string(repo.path()), file_id),
        Ok(Some(content.clone()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), relative_path)).expect("read sidecar note"),
        content
    );
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some(content.as_str())
    );
    assert_eq!(notes_row_count(repo.path(), file_id), 1);

    let detail = latest_edited_note_detail(repo.path(), file_id);
    assert_eq!(detail["length_before"], 0);
    assert_eq!(detail["length_after"], content.chars().count() as i64);
    assert_eq!(detail["by"], "user");
}

#[test]
fn read_write_note_validation_returns_file_not_found_for_unknown_active_file() {
    let repo = initialized_repo();
    let missing_file_id = 9_999;

    assert_eq!(
        read_note(path_string(repo.path()), missing_file_id),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(
        write_note(
            path_string(repo.path()),
            missing_file_id,
            "new note".to_owned()
        ),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(notes_row_count(repo.path(), missing_file_id), 0);
}

#[test]
fn read_write_note_validation_does_not_overwrite_unconfirmed_sidecar() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    let sidecar = sidecar_path(repo.path(), relative_path);
    fs::write(&sidecar, "user-authored sidecar").expect("write user-authored sidecar");

    let result = write_note(path_string(repo.path()), file_id, "new note".to_owned());

    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert_eq!(
        fs::read_to_string(&sidecar).expect("read preserved sidecar"),
        "user-authored sidecar"
    );
    assert_eq!(note_content(repo.path(), file_id), None);
    assert_eq!(change_log_count(repo.path()), 0);
}

#[test]
fn read_write_note_validation_restores_old_note_when_change_log_insert_fails() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    let old_content = "old note";

    write_note(path_string(repo.path()), file_id, old_content.to_owned())
        .expect("write initial note");
    install_edited_note_change_log_failure(repo.path());

    let result = write_note(path_string(repo.path()), file_id, "new note".to_owned());

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        read_note(path_string(repo.path()), file_id),
        Ok(Some(old_content.to_owned()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), relative_path))
            .expect("read restored sidecar"),
        old_content
    );
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some(old_content)
    );
    assert_eq!(change_log_count(repo.path()), 1);
}

#[test]
fn read_write_note_validation_rejects_db_sidecar_mismatch_without_mutation() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    insert_note_row(repo.path(), file_id, "db note");
    fs::write(sidecar_path(repo.path(), relative_path), "sidecar note")
        .expect("write mismatched sidecar note");

    assert_eq!(
        read_note(path_string(repo.path()), file_id),
        Err(CoreError::Db)
    );
    assert_eq!(
        write_note(path_string(repo.path()), file_id, "new note".to_owned()),
        Err(CoreError::Db)
    );
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some("db note")
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), relative_path))
            .expect("read preserved sidecar"),
        "sidecar note"
    );
    assert_eq!(change_log_count(repo.path()), 0);
}
