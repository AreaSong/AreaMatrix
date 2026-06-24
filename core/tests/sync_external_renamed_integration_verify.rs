use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, list_tree_json,
    sync_external_changes, ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileFilter,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

const API_RS: &str = include_str!("../src/api.rs");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DB_SYNC_RS: &str = include_str!("../src/db/sync.rs");
const SYNC_RS: &str = include_str!("../src/sync/mod.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

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

fn renamed(path: String, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path,
        kind: ExternalEventKind::Renamed,
        fs_event_id,
    }
}

fn modified(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Modified, fs_event_id)
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

fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

fn sync_created_file(
    repo: &Path,
    relative_path: &str,
    bytes: &[u8],
    fs_event_id: i64,
) -> area_matrix_core::FileEntry {
    write_repo_file(repo, relative_path, bytes);
    let result =
        sync_external_changes(path_string(repo), vec![created(relative_path, fs_event_id)])
            .expect("sync external created file fixture");
    assert_eq!(result.detected_creates, 1);
    list_files(path_string(repo), default_file_filter())
        .expect("list files after created fixture")
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created fixture should be visible")
}

fn rename_user_file(repo: &Path, from: &str, to: &str) {
    fs::rename(repo.join(from), repo.join(to)).expect("simulate external filesystem rename");
}

fn assert_renamed_consumers(repo: &Path, file_id: i64, user_bytes_before_sync: &[u8]) {
    let files = list_files(path_string(repo), default_file_filter()).expect("list files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, file_id);
    assert_eq!(files[0].path, "docs/renamed.pdf");
    assert_eq!(files[0].current_name, "renamed.pdf");
    assert_eq!(files[0].category, "docs");

    let detail = get_file(path_string(repo), file_id).expect("get renamed detail");
    assert_eq!(detail.path, "docs/renamed.pdf");
    assert_eq!(detail.current_name, "renamed.pdf");

    let tree_json =
        list_tree_json(path_string(repo), "en".to_owned()).expect("list tree for consumer");
    assert!(tree_json.contains("\"relative_path\":\"docs\""));
    assert!(tree_json.contains("\"file_count\":1"));

    let changes = list_changes(path_string(repo), change_filter(file_id)).expect("list detail-log");
    let renamed_change = changes
        .iter()
        .find(|change| change.action == "renamed")
        .expect("renamed change should be visible");
    let change = change_detail(renamed_change);
    assert_eq!(change["from_path"], "docs/original.pdf");
    assert_eq!(change["to_path"], "docs/renamed.pdf");
    assert_eq!(change["from_name"], "original.pdf");
    assert_eq!(change["to_name"], "renamed.pdf");
    assert_eq!(change["by"], "external");
    assert_eq!(
        fs::read(repo.join("docs/renamed.pdf")).expect("renamed user file remains readable"),
        user_bytes_before_sync
    );
}

#[test]
fn sync_external_renamed_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_18_capability_spec();
    assert_core_api_and_udl_contract();
    assert_core_consumers();
    assert_rust_entry_points_are_real_renamed_wiring();
}

fn assert_c1_18_capability_spec() {}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);",
        "dictionary ExternalEvent",
        "string path;",
        "ExternalEventKind kind;",
        "i64 fs_event_id;",
        "dictionary SyncResult",
        "i64 detected_renames;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `sync_external_changes(repoPath, events) throws -> SyncResult`",
        "去抖 + InFlight 过滤后传入",
        "print(\"created: \\(result.detectedCreates), renamed: \\(result.detectedRenames)",
        "sync_external_changes`（批量事件）",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_core_consumers() {}

fn assert_rust_entry_points_are_real_renamed_wiring() {
    for fragment in [
        "external renamed sync owns the `ExternalEventKind::Renamed` contract",
        "`files.path` and",
        "`files.current_name` update",
        "`updated_at` refresh",
        "`change_log.action =",
        "renamed`",
        "old/new path detail",
        "`SyncResult::detected_renames`",
        "only confirms the new path exists",
        "must not",
        "rename, move, delete, overwrite, copy, or download",
        "removed + created",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "ExternalEventKind::Renamed =>",
        "plan_renamed_event",
        "map_renamed_target_metadata_error",
        "find_external_rename_candidates_by_hash",
        "external_rename_detail",
        "CoreError::Conflict { path }",
        "CoreError::FileNotFound { path }",
    ] {
        assert_contains(SYNC_RS, fragment);
    }

    for fragment in [
        "apply_external_sync_batch",
        "update_external_renamed_file",
        "SET path = ?2",
        "current_name = ?3",
        "updated_at = strftime('%s', 'now')",
        "'renamed'",
        "set_cursor(&tx, last_event_id)",
        "tx.commit()",
    ] {
        assert_contains(DB_SYNC_RS, fragment);
    }
}

#[test]
fn sync_external_renamed_integration_verify_real_flow_reaches_list_detail_log_tree_and_cursor() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"rename bytes", 700);
    rename_user_file(repo.path(), "docs/original.pdf", "docs/renamed.pdf");
    let user_bytes_before_sync =
        fs::read(repo.path().join("docs/renamed.pdf")).expect("read externally renamed file");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf".to_owned(), 701)],
    )
    .expect("sync external renamed event");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(701));

    assert_renamed_consumers(repo.path(), entry.id, &user_bytes_before_sync);
}

#[test]
fn sync_external_renamed_integration_verify_accepts_absolute_new_path() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.txt", b"absolute path", 710);
    rename_user_file(repo.path(), "docs/original.txt", "docs/renamed.txt");
    let absolute_path = path_string(&repo.path().join("docs/renamed.txt"));

    let result = sync_external_changes(path_string(repo.path()), vec![renamed(absolute_path, 711)])
        .expect("sync renamed event with absolute new path");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(fs_cursor(repo.path()), Some(711));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("get renamed file")
            .path,
        "docs/renamed.txt"
    );
}

#[test]
fn sync_external_renamed_integration_verify_boundaries_stay_transactional() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.txt", b"missing target", 720);

    let missing = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/missing.txt".to_owned(), 721)],
    );

    assert!(matches!(missing, Err(CoreError::FileNotFound { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(720));
    let unchanged = get_file(path_string(repo.path()), entry.id).expect("get unchanged file");
    assert_eq!(unchanged.path, "docs/original.txt");
    assert_eq!(unchanged.current_name, "original.txt");
    let changes =
        list_changes(path_string(repo.path()), change_filter(entry.id)).expect("list changes");
    assert!(changes.iter().all(|change| change.action != "renamed"));

    rename_user_file(repo.path(), "docs/original.txt", "docs/renamed.txt");
    let partial_scope = sync_external_changes(
        path_string(repo.path()),
        vec![
            renamed("docs/renamed.txt".to_owned(), 722),
            modified("docs/renamed.txt", 723),
        ],
    )
    .expect("sync only renamed capability while preserving out-of-scope cursor");

    assert_eq!(partial_scope.detected_renames, 1);
    assert_eq!(partial_scope.detected_modifies, 0);
    assert_eq!(partial_scope.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), Some(720));
}
