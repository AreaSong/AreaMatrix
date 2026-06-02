use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, DuplicateStrategy, FileAvailabilityStatus, FileFilter,
    FileOrigin, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
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

fn app_group_share_payload(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let app_group = tempfile::tempdir().expect("create app-group staging directory");
    let source_path = app_group.path().join(name);
    fs::write(&source_path, content).expect("write staged share payload");
    (app_group, source_path)
}

fn share_import_options(filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::KeepBoth,
    }
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn row_count(repo: &Path, table: &str) -> i64 {
    open_db(repo)
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| row.get(0))
        .expect("count rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

#[test]
fn share_extension_import_implementation_copies_staged_payload_into_repo() {
    let repo = initialized_repo();
    let payload = b"external app payload bytes: private article body";
    let (_app_group, staged) = app_group_share_payload("safari-article.pdf", payload);
    let staged_path = path_string(&staged);

    let entry = import_file(
        path_string(repo.path()),
        staged_path.clone(),
        share_import_options("Shared Article.pdf"),
    )
    .expect("import staged share payload");

    assert_eq!(fs::read(&staged).expect("read staged payload"), payload);
    assert_eq!(entry.path, "inbox/Shared Article.pdf");
    assert_eq!(entry.original_name, "safari-article.pdf");
    assert_eq!(entry.current_name, "Shared Article.pdf");
    assert_eq!(entry.category, "inbox");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(staged_path.as_str()));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied repo file"),
        payload
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list files");
    assert_eq!(files, vec![entry.clone()]);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn share_extension_import_implementation_deferred_ticket_can_be_continued_by_main_app() {
    let repo = initialized_repo();
    let payload = b"queued share payload bytes";
    let (_app_group, staged) = app_group_share_payload("queued-share.txt", payload);

    assert_eq!(row_count(repo.path(), "files"), 0);
    assert_eq!(row_count(repo.path(), "change_log"), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let continued = import_file(
        path_string(repo.path()),
        path_string(&staged),
        share_import_options("Queued Share.txt"),
    )
    .expect("main app continues deferred share import");

    assert_eq!(continued.path, "inbox/Queued Share.txt");
    assert_eq!(fs::read(&staged).expect("read staged payload"), payload);
    assert_eq!(
        fs::read(repo.path().join(&continued.path)).expect("read continued repo file"),
        payload
    );
    assert_eq!(row_count(repo.path(), "files"), 1);
    assert_eq!(row_count(repo.path(), "change_log"), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn share_extension_import_implementation_change_log_omits_payload_content() {
    let repo = initialized_repo();
    let secret_payload = b"shared payload secret marker must not be logged";
    let (_app_group, staged) = app_group_share_payload("mail-attachment.pdf", secret_payload);

    let entry = import_file(
        path_string(repo.path()),
        path_string(&staged),
        share_import_options("Mail Attachment.pdf"),
    )
    .expect("import share payload");

    let detail_json: String = open_db(repo.path())
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = 'imported'",
            [entry.id],
            |row| row.get(0),
        )
        .expect("read share import change log");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse import detail json");

    assert_eq!(detail["mode"], "copied");
    assert_eq!(detail["category"], "inbox");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["requested_name"], "Mail Attachment.pdf");
    assert_eq!(detail["final_path"], entry.path);
    assert_eq!(detail["by"], "user");
    assert!(
        !detail_json.contains("secret marker"),
        "change log must not include external app payload content"
    );
}
