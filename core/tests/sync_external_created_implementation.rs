use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, list_tree_json,
    set_fs_event_cursor, sync_external_changes, ChangeFilter, CoreError, ExternalEvent,
    ExternalEventKind, FileFilter, FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

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

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent directory");
    }
    fs::write(path, bytes).expect("write repository file");
}

fn created(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Created,
        fs_event_id,
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

fn default_change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON object")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

#[test]
fn sync_external_created_implementation_indexes_created_file_and_advances_cursor() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/external.pdf", b"external bytes");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.pdf", 42)],
    )
    .expect("sync external created file");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read fs cursor"),
        Some(42)
    );

    let files = list_files(path_string(repo.path()), default_file_filter()).expect("list files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "docs/external.pdf");
    assert_eq!(files[0].current_name, "external.pdf");
    assert_eq!(files[0].category, "docs");
    assert_eq!(files[0].size_bytes, 14);
    assert_eq!(files[0].storage_mode, StorageMode::Indexed);
    assert_eq!(files[0].origin, FileOrigin::External);
    assert_eq!(files[0].source_path, None);

    let detail = get_file(path_string(repo.path()), files[0].id).expect("get synced file detail");
    assert_eq!(detail.path, "docs/external.pdf");

    let tree_json = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect("list tree after external sync");
    assert!(
        tree_json.contains("\"docs\""),
        "tree JSON should include the created file category"
    );

    let mut filter = default_change_filter();
    filter.file_id = Some(files[0].id);
    let changes = list_changes(path_string(repo.path()), filter).expect("list created changes");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].action, "external_modified");
    let detail = change_detail(&changes[0]);
    assert_eq!(detail["kind"], "create");
    assert_eq!(detail["path"], "docs/external.pdf");
    assert_eq!(detail["category"], "docs");
    assert_eq!(detail["hash_after"], files[0].hash_sha256);
    assert_eq!(detail["size_bytes"], 14);
    assert_eq!(detail["by"], "external");
}

#[test]
fn sync_external_created_implementation_skips_internal_generated_output_but_indexes_readme() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/internal.md",
        b"generated",
    );
    write_repo_file(repo.path(), "AREAMATRIX.md", b"overview");
    write_repo_file(repo.path(), "README.md", b"user readme");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            created(".areamatrix/generated/internal.md", 10),
            created("AREAMATRIX.md", 11),
            created("README.md", 12),
        ],
    )
    .expect("sync mixed generated and user files");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read fs cursor"),
        Some(12)
    );
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("README remains readable"),
        b"user readme"
    );

    let files = list_files(path_string(repo.path()), default_file_filter()).expect("list files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "README.md");
    assert_eq!(files[0].category, "__root__");
}

#[test]
fn sync_external_created_implementation_rolls_back_batch_and_cursor_on_failure() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/good.pdf", b"good");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/good.pdf", 20),
            created("docs/missing.pdf", 21),
        ],
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));

    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read missing cursor"),
        None
    );
}

#[test]
fn sync_external_created_implementation_rejects_escaping_paths_without_writes() {
    let repo = initialized_repo();

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("../outside.pdf", 30)],
    );

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));

    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read missing cursor"),
        None
    );
}

#[test]
fn sync_external_created_implementation_rejects_icloud_placeholder_marker() {
    let repo = initialized_repo();

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/waiting.pdf.icloud", 40)],
    );

    assert_eq!(
        result,
        Err(CoreError::icloud_placeholder("icloud placeholder"))
    );
    assert_eq!(active_file_count(repo.path()), 0);
}

#[test]
fn sync_external_created_implementation_is_idempotent_for_duplicate_created_events() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/external.pdf", b"external bytes");

    sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.pdf", 50)],
    )
    .expect("sync external created file first time");
    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.pdf", 51)],
    )
    .expect("sync duplicate external created event");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read fs cursor"),
        Some(51)
    );
    let changes =
        list_changes(path_string(repo.path()), default_change_filter()).expect("list changes");
    assert_eq!(changes.len(), 1);
}

#[test]
fn sync_external_created_implementation_cursor_api_roundtrips_without_file_mutation() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/user.txt", b"untouched");

    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read initial cursor"),
        None
    );
    set_fs_event_cursor(path_string(repo.path()), 99).expect("set cursor");

    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read updated cursor"),
        Some(99)
    );
    assert_eq!(
        fs::read(repo.path().join("docs/user.txt")).expect("user file remains readable"),
        b"untouched"
    );
}
