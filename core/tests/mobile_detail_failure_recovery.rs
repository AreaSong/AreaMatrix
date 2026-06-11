use std::{
    fs,
    path::{Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use area_matrix_core::{
    get_file, init_repo, list_changes, read_note, ChangeFilter, CoreError, ErrorKind,
    ErrorRecoverability, ErrorSeverity, FileAvailabilityStatus, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

fn mobile_filter(file_id: Option<i64>) -> ChangeFilter {
    ChangeFilter {
        file_id,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 25,
        offset: 0,
    }
}

fn insert_active_file(repo: &Path, relative_path: &str, write_backing_file: bool) -> i64 {
    if write_backing_file {
        write_user_file(repo, relative_path, b"mobile detail fixture bytes");
    }

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
                ?1, ?2, ?2, 'docs', 27,
                ?3, 'copied', 'imported', NULL,
                4070, 4071, 'active'
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

fn write_user_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    let parent = path.parent().expect("test path has parent");
    fs::create_dir_all(parent).expect("create user file parent");
    fs::write(path, bytes).expect("write user file fixture");
}

fn insert_note_row(repo: &Path, file_id: i64, content: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at)
             VALUES (?1, ?2, 4072)",
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

fn metadata_counts(repo: &Path) -> (i64, i64, i64) {
    let connection = open_db(repo);
    let files = connection
        .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
        .expect("count file rows");
    let changes = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows");
    let notes = connection
        .query_row("SELECT COUNT(*) FROM notes", [], |row| row.get(0))
        .expect("count note rows");
    (files, changes, notes)
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn sidecar_path(repo: &Path, relative_path: &str) -> PathBuf {
    repo.join(format!("{relative_path}.md"))
}

#[test]
fn mobile_detail_failure_edge_returns_empty_segments_without_mutation() {
    let repo = initialized_repo();
    let relative_path = "docs/empty.pdf";
    let file_id = insert_active_file(repo.path(), relative_path, true);
    let before_counts = metadata_counts(repo.path());
    let before_file = fs::read(repo.path().join(relative_path)).expect("read user file before");

    let entry = get_file(path_string(repo.path()), file_id).expect("load empty-state metadata");
    let changes =
        list_changes(path_string(repo.path()), mobile_filter(Some(file_id))).expect("list changes");
    let note = read_note(path_string(repo.path()), file_id).expect("read empty note");

    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
    assert_eq!(changes, Vec::new());
    assert_eq!(note, None);
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(
        fs::read(repo.path().join(relative_path)).expect("read user file after"),
        before_file
    );
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
    assert!(!sidecar_path(repo.path(), relative_path).exists());
}

#[test]
fn mobile_detail_failure_edge_rejects_invalid_inputs_without_silent_fallback() {
    let repo = initialized_repo();
    let before_counts = metadata_counts(repo.path());

    assert!(matches!(
        get_file(path_string(repo.path()), 0),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        read_note(path_string(repo.path()), -1),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        list_changes(path_string(repo.path()), mobile_filter(Some(0))),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_range = mobile_filter(None);
    invalid_range.since = Some(20);
    invalid_range.until = Some(10);
    assert!(matches!(
        list_changes(path_string(repo.path()), invalid_range),
        Err(CoreError::Db { .. })
    ));
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn mobile_detail_failure_edge_keeps_missing_metadata_row_for_recovery_route() {
    let repo = initialized_repo();
    let relative_path = "docs/missing.pdf";
    let file_id = insert_active_file(repo.path(), relative_path, false);
    let before_counts = metadata_counts(repo.path());

    let entry = get_file(path_string(repo.path()), file_id).expect("load missing metadata row");
    let changes =
        list_changes(path_string(repo.path()), mobile_filter(Some(file_id))).expect("list changes");
    let note = read_note(path_string(repo.path()), file_id).expect("read empty note");

    assert_eq!(entry.availability_status, FileAvailabilityStatus::Missing);
    assert_eq!(changes, Vec::new());
    assert_eq!(note, None);
    assert!(!repo.path().join(relative_path).exists());
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn mobile_detail_failure_edge_maps_metadata_db_failures() {
    let repo = initialized_repo();
    open_db(repo.path())
        .execute_batch("DROP TABLE files;")
        .expect("drop files table to simulate metadata corruption");
    assert!(matches!(
        get_file(path_string(repo.path()), 1),
        Err(CoreError::Db { .. })
    ));

    let repo = initialized_repo();
    open_db(repo.path())
        .execute_batch("DROP TABLE change_log;")
        .expect("drop change_log table to simulate metadata corruption");
    assert!(matches!(
        list_changes(path_string(repo.path()), mobile_filter(None)),
        Err(CoreError::Db { .. })
    ));

    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "docs/note-db.pdf", true);
    open_db(repo.path())
        .execute_batch("DROP TABLE notes;")
        .expect("drop notes table to simulate metadata corruption");
    assert!(matches!(
        read_note(path_string(repo.path()), file_id),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn mobile_detail_failure_edge_returns_note_io_errors_without_mutation() {
    let repo = initialized_repo();
    let relative_path = "docs/io.pdf";
    let file_id = insert_active_file(repo.path(), relative_path, true);
    insert_note_row(repo.path(), file_id, "db note");
    let sidecar = sidecar_path(repo.path(), relative_path);
    fs::write(&sidecar, [0xff, 0xfe]).expect("write invalid utf-8 sidecar");
    let before_counts = metadata_counts(repo.path());
    let before_file = fs::read(repo.path().join(relative_path)).expect("read user file before");
    let before_sidecar = fs::read(&sidecar).expect("read sidecar before");

    assert!(matches!(
        read_note(path_string(repo.path()), file_id),
        Err(CoreError::Io { .. })
    ));
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some("db note")
    );
    assert_eq!(
        fs::read(repo.path().join(relative_path)).expect("read user file after"),
        before_file
    );
    assert_eq!(
        fs::read(&sidecar).expect("read sidecar after"),
        before_sidecar
    );
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn mobile_detail_failure_edge_does_not_treat_missing_sidecar_as_empty_note() {
    let repo = initialized_repo();
    let relative_path = "docs/missing-sidecar.pdf";
    let file_id = insert_active_file(repo.path(), relative_path, true);
    insert_note_row(repo.path(), file_id, "db note");
    let sidecar = sidecar_path(repo.path(), relative_path);
    let before_counts = metadata_counts(repo.path());

    assert!(matches!(
        read_note(path_string(repo.path()), file_id),
        Err(CoreError::FileNotFound { .. })
    ));
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some("db note")
    );
    assert!(!sidecar.exists());
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[cfg(unix)]
#[test]
fn mobile_detail_failure_edge_maps_note_permission_denied_without_mutation() {
    let repo = initialized_repo();
    let relative_path = "docs/permission.pdf";
    let file_id = insert_active_file(repo.path(), relative_path, true);
    insert_note_row(repo.path(), file_id, "private note");
    let sidecar = sidecar_path(repo.path(), relative_path);
    fs::write(&sidecar, "private note").expect("write sidecar note");
    fs::set_permissions(&sidecar, fs::Permissions::from_mode(0o000))
        .expect("remove sidecar read permission");

    let result = read_note(path_string(repo.path()), file_id);

    fs::set_permissions(&sidecar, fs::Permissions::from_mode(0o600))
        .expect("restore sidecar permission");
    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert_eq!(
        fs::read_to_string(&sidecar).expect("read restored sidecar"),
        "private note"
    );
    assert_eq!(
        note_content(repo.path(), file_id).as_deref(),
        Some("private note")
    );
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn mobile_detail_failure_edge_maps_errors_to_recovery_metadata() {
    let file_missing = CoreError::file_not_found("docs/missing.pdf").to_error_mapping();
    assert_eq!(file_missing.kind, ErrorKind::FileNotFound);
    assert_eq!(file_missing.severity, ErrorSeverity::Low);
    assert_eq!(
        file_missing.recoverability,
        ErrorRecoverability::RefreshRequired
    );

    let db_locked = CoreError::db("database is locked").to_error_mapping();
    assert_eq!(db_locked.kind, ErrorKind::Db);
    assert_eq!(db_locked.severity, ErrorSeverity::Medium);
    assert_eq!(db_locked.recoverability, ErrorRecoverability::Retryable);

    let db_corrupt = CoreError::db("file is not a database").to_error_mapping();
    assert_eq!(db_corrupt.kind, ErrorKind::Db);
    assert_eq!(db_corrupt.severity, ErrorSeverity::Critical);
    assert_eq!(db_corrupt.recoverability, ErrorRecoverability::Fatal);

    let permission = CoreError::permission_denied("permission denied").to_error_mapping();
    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(permission.severity, ErrorSeverity::High);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let io = CoreError::io("io error").to_error_mapping();
    assert_eq!(io.kind, ErrorKind::Io);
    assert_eq!(io.severity, ErrorSeverity::Medium);
    assert_eq!(io.recoverability, ErrorRecoverability::Retryable);
}
