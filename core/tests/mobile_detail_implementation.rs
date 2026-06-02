use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, init_repo, list_changes, read_note, ChangeFilter, CoreError, FileAvailabilityStatus,
    FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
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

fn mobile_log_filter(file_id: i64, limit: i64, offset: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: None,
        since: None,
        until: None,
        limit,
        offset,
    }
}

fn insert_mobile_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    size_bytes: i64,
    imported_at: i64,
    write_backing_file: bool,
) -> i64 {
    if write_backing_file {
        write_repo_file(
            repo,
            relative_path,
            b"physical bytes deliberately differ from metadata",
        );
    }

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("test path has a filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4,
                ?5, 'copied', 'imported', NULL,
                ?6, ?7, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                size_bytes,
                format!("{imported_at:064x}"),
                imported_at,
                imported_at + 10,
            ],
        )
        .expect("insert active mobile detail file row");
    connection.last_insert_rowid()
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let file_path = repo.join(relative_path);
    let parent = file_path.parent().expect("test file has parent directory");
    fs::create_dir_all(parent).expect("create fixture parent directory");
    fs::write(file_path, bytes).expect("write fixture user file");
}

fn insert_change(repo: &Path, file_id: i64, action: &str, detail_json: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![file_id, action, detail_json, occurred_at],
        )
        .expect("insert mobile detail change-log row");
}

fn insert_note(repo: &Path, file_id: i64, relative_path: &str, content: &str) -> PathBuf {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at)
             VALUES (?1, ?2, 100)",
            params![file_id, content],
        )
        .expect("insert mobile detail note row");
    let sidecar = repo.join(format!("{relative_path}.md"));
    fs::write(&sidecar, content).expect("write tracked note sidecar");
    sidecar
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

fn parse_detail(detail_json: &str) -> Value {
    serde_json::from_str(detail_json).expect("mobile detail change payload is JSON")
}

struct MobileDetailFixture {
    file_id: i64,
    sidecar: PathBuf,
    before_counts: (i64, i64, i64),
    before_file: Vec<u8>,
    before_sidecar: String,
}

fn seed_mobile_detail_fixture(repo: &Path, note: &str) -> MobileDetailFixture {
    let file_id = insert_mobile_file(repo, "docs/report.pdf", "docs", 4_096, 407, true);
    let sidecar = insert_note(repo, file_id, "docs/report.pdf", note);
    insert_change(
        repo,
        file_id,
        "imported",
        r#"{"source":"ios-files","by":"user"}"#,
        1_000,
    );
    insert_change(
        repo,
        file_id,
        "external_modified",
        r#"{"platform":"ios","by":"sync"}"#,
        1_100,
    );
    insert_change(
        repo,
        file_id,
        "edited_note",
        r#"{"length_after":28,"by":"user"}"#,
        1_200,
    );
    let before_file = fs::read(repo.join("docs/report.pdf")).expect("read user file");
    let before_sidecar = fs::read_to_string(&sidecar).expect("read note sidecar");
    MobileDetailFixture {
        file_id,
        sidecar,
        before_counts: metadata_counts(repo),
        before_file,
        before_sidecar,
    }
}

fn assert_mobile_metadata(repo: &Path, file_id: i64) {
    let entry = get_file(path_string(repo), file_id).expect("load mobile detail metadata");
    assert_eq!(entry.id, file_id);
    assert_eq!(entry.path, "docs/report.pdf");
    assert_eq!(entry.current_name, "report.pdf");
    assert_eq!(entry.category, "docs");
    assert_eq!(entry.size_bytes, 4_096);
    assert_eq!(entry.hash_sha256, format!("{:064x}", 407));
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
}

fn assert_mobile_log_page(repo: &Path, file_id: i64) {
    let changes = list_changes(path_string(repo), mobile_log_filter(file_id, 2, 0))
        .expect("load first mobile detail log page");
    assert_eq!(
        changes
            .iter()
            .map(|change| change.action.as_str())
            .collect::<Vec<_>>(),
        vec!["edited_note", "external_modified"]
    );
    assert_eq!(
        changes
            .iter()
            .map(|change| change.file_id)
            .collect::<Vec<_>>(),
        vec![Some(file_id), Some(file_id)]
    );
    assert_eq!(parse_detail(&changes[0].detail_json)["by"], "user");
}

#[test]
fn mobile_detail_implementation_loads_metadata_log_and_note_without_writes() {
    let repo = initialized_repo();
    let note = "Reviewed from mobile detail.";
    let fixture = seed_mobile_detail_fixture(repo.path(), note);

    assert_mobile_metadata(repo.path(), fixture.file_id);
    assert_mobile_log_page(repo.path(), fixture.file_id);
    assert_eq!(
        read_note(path_string(repo.path()), fixture.file_id),
        Ok(Some(note.to_owned()))
    );
    assert_eq!(metadata_counts(repo.path()), fixture.before_counts);
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read user file after detail load"),
        fixture.before_file
    );
    assert_eq!(
        fs::read_to_string(&fixture.sidecar).expect("read note sidecar after detail load"),
        fixture.before_sidecar
    );
}

#[test]
fn mobile_detail_implementation_preserves_missing_rows_for_recovery_route() {
    let repo = initialized_repo();
    let file_id = insert_mobile_file(repo.path(), "docs/missing.pdf", "docs", 512, 4_071, false);
    insert_change(
        repo.path(),
        file_id,
        "imported",
        r#"{"source":"missing-mobile-fixture","by":"user"}"#,
        2_000,
    );
    let before_counts = metadata_counts(repo.path());

    let entry =
        get_file(path_string(repo.path()), file_id).expect("load missing mobile detail metadata");

    assert_eq!(entry.id, file_id);
    assert_eq!(entry.path, "docs/missing.pdf");
    assert_eq!(entry.current_name, "missing.pdf");
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Missing);
    assert!(!repo.path().join("docs/missing.pdf").exists());

    let changes = list_changes(path_string(repo.path()), mobile_log_filter(file_id, 10, 0))
        .expect("load log for missing mobile detail row");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].file_id, Some(file_id));
    assert_eq!(changes[0].action, "imported");
    assert_eq!(read_note(path_string(repo.path()), file_id), Ok(None));

    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert!(!repo.path().join("docs/missing.pdf").exists());
}

#[test]
fn mobile_detail_implementation_maps_absent_file_id_to_file_not_found() {
    let repo = initialized_repo();

    assert!(matches!(
        get_file(path_string(repo.path()), 999),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        read_note(path_string(repo.path()), 999),
        Err(CoreError::FileNotFound { .. })
    ));
}
