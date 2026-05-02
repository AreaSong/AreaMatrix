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

fn edited_note_details(repo: &Path, file_id: i64) -> Vec<Value> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = 'edited_note'
             ORDER BY id ASC",
        )
        .expect("prepare edited_note query");
    let rows = statement
        .query_map(params![file_id], |row| row.get::<_, String>(0))
        .expect("query edited_note rows");
    rows.map(|row| {
        let detail = row.expect("read edited_note detail");
        serde_json::from_str(&detail).expect("edited_note detail is valid JSON")
    })
    .collect()
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

#[cfg(unix)]
fn set_dir_mode(path: &Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;

    let permissions = fs::Permissions::from_mode(mode);
    fs::set_permissions(path, permissions).expect("set directory permissions");
}

#[test]
fn read_write_note_failure_recovery_repeated_writes_keep_one_note_and_log_successes() {
    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "finance/report.pdf");

    write_note(path_string(repo.path()), file_id, "short".to_owned()).expect("write initial note");
    write_note(path_string(repo.path()), file_id, "longer note".to_owned())
        .expect("write replacement note");

    assert_eq!(notes_row_count(repo.path(), file_id), 1);
    assert_eq!(
        read_note(path_string(repo.path()), file_id),
        Ok(Some("longer note".to_owned()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), "finance/report.pdf"))
            .expect("read sidecar note"),
        "longer note"
    );

    let details = edited_note_details(repo.path(), file_id);
    assert_eq!(details.len(), 2);
    assert_eq!(details[0]["length_before"], 0);
    assert_eq!(details[0]["length_after"], 5);
    assert_eq!(details[1]["length_before"], 5);
    assert_eq!(details[1]["length_after"], 11);
}

#[test]
fn read_write_note_failure_recovery_preserves_untracked_sidecar_on_permission_error() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    let sidecar = sidecar_path(repo.path(), relative_path);
    fs::write(&sidecar, "user-authored sidecar").expect("write untracked sidecar");

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
fn read_write_note_failure_recovery_rejects_db_sidecar_mismatch_without_writes() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    insert_note_row(repo.path(), file_id, "db note");
    fs::write(sidecar_path(repo.path(), relative_path), "sidecar note")
        .expect("write mismatched sidecar note");

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

#[test]
fn read_write_note_failure_recovery_restores_old_sidecar_when_db_log_fails() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    write_note(path_string(repo.path()), file_id, "old note".to_owned())
        .expect("write initial note");
    install_edited_note_change_log_failure(repo.path());

    let result = write_note(path_string(repo.path()), file_id, "new note".to_owned());

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some("old note")
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), relative_path))
            .expect("read restored sidecar"),
        "old note"
    );
    assert_eq!(change_log_count(repo.path()), 1);
}

#[cfg(unix)]
#[test]
fn read_write_note_failure_recovery_write_failure_preserves_old_note() {
    let repo = initialized_repo();
    let relative_path = "finance/report.pdf";
    let file_id = insert_active_file(repo.path(), relative_path);
    write_note(path_string(repo.path()), file_id, "old note".to_owned())
        .expect("write initial note");

    let parent = repo.path().join("finance");
    let original_mode = parent
        .metadata()
        .expect("read parent metadata")
        .permissions();
    set_dir_mode(&parent, 0o500);
    let result = write_note(path_string(repo.path()), file_id, "new note".to_owned());
    fs::set_permissions(&parent, original_mode).expect("restore parent permissions");

    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some("old note")
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), relative_path))
            .expect("read preserved sidecar"),
        "old note"
    );
    assert_eq!(change_log_count(repo.path()), 1);
}
