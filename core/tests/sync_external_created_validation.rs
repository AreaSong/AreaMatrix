use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, list_tree_json,
    sync_external_changes, ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileFilter,
    FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
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

fn event(relative_path: &str, kind: ExternalEventKind, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind,
        fs_event_id,
    }
}

fn created(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Created, fs_event_id)
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

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

fn listed_files(repo: &Path) -> Vec<area_matrix_core::FileEntry> {
    list_files(path_string(repo), default_file_filter()).expect("list files")
}

fn listed_changes(repo: &Path) -> Vec<area_matrix_core::ChangeLogEntry> {
    list_changes(path_string(repo), default_change_filter()).expect("list changes")
}

fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON object")
}

#[test]
fn sync_external_created_validation_success_path_reaches_list_tree_detail_log_and_cursor() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        "docs/external.md",
        b"external validation bytes",
    );

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.md", 200)],
    )
    .expect("sync external created event");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(200));

    let files = listed_files(repo.path());
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "docs/external.md");
    assert_eq!(files[0].current_name, "external.md");
    assert_eq!(files[0].category, "docs");
    assert_eq!(files[0].storage_mode, StorageMode::Indexed);
    assert_eq!(files[0].origin, FileOrigin::External);
    assert_eq!(files[0].source_path, None);

    let detail = get_file(path_string(repo.path()), files[0].id).expect("get synced file detail");
    assert_eq!(detail.path, "docs/external.md");

    let tree_json =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list tree json");
    assert!(tree_json.contains("\"docs\""));

    let changes = listed_changes(repo.path());
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].action, "external_modified");
    let detail = change_detail(&changes[0]);
    assert_eq!(detail["kind"], "create");
    assert_eq!(detail["path"], "docs/external.md");
    assert_eq!(detail["hash_after"], files[0].hash_sha256);
    assert_eq!(
        fs::read(repo.path().join("docs/external.md")).expect("read preserved user file"),
        b"external validation bytes"
    );
}

#[test]
fn sync_external_created_validation_skips_internal_paths_and_generated_overviews() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/internal.md",
        b"generated",
    );
    write_repo_file(repo.path(), "AREAMATRIX.md", b"overview");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            created(".areamatrix/generated/internal.md", 210),
            created("AREAMATRIX.md", 211),
        ],
    )
    .expect("sync skipped created events");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(fs_cursor(repo.path()), Some(211));
    assert!(listed_files(repo.path()).is_empty());
    assert!(listed_changes(repo.path()).is_empty());
}

#[test]
fn sync_external_created_validation_rejects_absolute_paths_outside_repo_without_state() {
    let repo = initialized_repo();
    let outside = tempfile::NamedTempFile::new().expect("create external file");
    fs::write(outside.path(), b"outside").expect("write external file");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created(&path_string(outside.path()), 220)],
    );

    assert_eq!(result, Err(CoreError::InvalidPath));
    assert_eq!(fs_cursor(repo.path()), None);
    assert!(listed_files(repo.path()).is_empty());
    assert!(listed_changes(repo.path()).is_empty());
}

#[test]
fn sync_external_created_validation_rejects_negative_created_event_id_without_state() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/bad-event.txt", b"bad event");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/bad-event.txt", -1)],
    );

    assert_eq!(result, Err(CoreError::InvalidPath));
    assert_eq!(fs_cursor(repo.path()), None);
    assert!(listed_files(repo.path()).is_empty());
    assert!(listed_changes(repo.path()).is_empty());
}

#[test]
fn sync_external_created_validation_does_not_claim_cursor_for_unimplemented_event_kinds() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/created.txt", b"created");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/created.txt", 230),
            event("docs/created.txt", ExternalEventKind::Modified, 231),
        ],
    )
    .expect("sync created event without claiming adjacent event kinds");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(fs_cursor(repo.path()), None);
    assert_eq!(listed_files(repo.path()).len(), 1);
    assert_eq!(listed_changes(repo.path()).len(), 1);
}
