use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, list_tree_json,
    sync_external_changes, ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileEntry,
    FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const API_RS: &str = include_str!("../src/api.rs");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DB_SYNC_RS: &str = include_str!("../src/db/sync.rs");
const S1_09_MAIN_LIST: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md");
const S1_11_MAIN_REPO_ERROR: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md");
const S1_13_DETAIL_LOG: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md");
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

fn removed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Removed, fs_event_id)
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

fn include_deleted_file_filter() -> FileFilter {
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

fn listed_files(repo: &Path, filter: FileFilter) -> Vec<FileEntry> {
    list_files(path_string(repo), filter).expect("list files")
}

fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON object")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
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

fn sync_created_file(
    repo: &Path,
    relative_path: &str,
    bytes: &[u8],
    fs_event_id: i64,
) -> FileEntry {
    write_repo_file(repo, relative_path, bytes);
    let result =
        sync_external_changes(path_string(repo), vec![created(relative_path, fs_event_id)])
            .expect("sync external created file fixture");
    assert_eq!(result.detected_creates, 1);
    listed_files(repo, default_file_filter())
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created fixture should be visible")
}

fn assert_only_keeper_is_visible(repo: &Path, keeper_id: i64) {
    let files = listed_files(repo, default_file_filter());
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, keeper_id);
    assert_eq!(files[0].path, "docs/keeper.pdf");

    let tree_json =
        list_tree_json(path_string(repo), "en".to_owned()).expect("list tree for main-list");
    let tree: Value = serde_json::from_str(&tree_json).expect("parse tree JSON");
    assert_eq!(tree["file_count"], 1);
    assert!(
        !tree_json.contains("remove.pdf"),
        "deleted file should not remain in main-list tree projection"
    );
}

#[test]
fn sync_external_removed_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_19_capability_spec();
    assert_core_api_and_udl_contract();
    assert_stage_one_consumers();
    assert_rust_entry_points_are_real_removed_wiring();
}

fn assert_c1_19_capability_spec() {
    for fragment in [
        "C1-19 sync-external-removed",
        "- S1-09 main-list",
        "- S1-11 main-repo-error",
        "- S1-13 detail-log",
        "- `sync_external_changes(repo_path, events)`",
        "- `ExternalEvent { kind: Removed, path, fs_event_id }`",
        "- `SyncResult.detected_deletes`",
        "- 对对应 `files` 标记 `status=deleted` 或等价状态。",
        "- 写入 `change_log.deleted`。",
        "- 只读确认路径缺失。",
        "- 不删除其他文件。",
        "- `FileNotFound`",
        "- `Db`",
        "- `Io`",
        "- 外部删除后默认列表不再显示该文件。",
        "- Detail 打开已删除 file_id 时给出可理解错误。",
        "- change log 可追溯删除事件。",
        "- 从 Trash 自动恢复属于 Stage 2+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);",
        "dictionary ExternalEvent",
        "string path;",
        "ExternalEventKind kind;",
        "i64 fs_event_id;",
        "dictionary SyncResult",
        "i64 detected_deletes;",
        "sequence<string> errors;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `sync_external_changes(repoPath, events) throws -> SyncResult`",
        "去抖 + InFlight 过滤后传入",
        "print(\"created: \\(result.detectedCreates), renamed: \\(result.detectedRenames), deleted: \\(result.detectedDeletes)\")",
        "`sync_external_changes`（批量事件）",
        "文件不存在抛 `FileNotFound`。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_stage_one_consumers() {
    for fragment in [
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
        "| S1-11 | main-repo-error | C1-01, C1-19, C1-21 | `validate_initialized_repo_path`, `sync_external_changes`",
        "| S1-13 | detail-log | C1-13, C1-17, C1-18, C1-19 | `list_changes`, `sync_external_changes`",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "删除或移动导致选中项消失时，Detail 显示 moved/missing 提示。",
        "FSEvents external removed：行变为 missing 或从当前过滤结果移除，Detail 显示缺失恢复入口。",
        "行状态 `OK` / `Missing` / `Index-only` / `iCloud` 需要文本标签。",
        "FSEvents sync error / partial failure：显示 non-blocking banner",
    ] {
        assert_contains(S1_09_MAIN_LIST, fragment);
    }
    for fragment in [
        "避免用户误以为文件已被删除。",
        "路径缺失：`AreaMatrix cannot find this folder. It may have been moved, renamed, or disconnected.`",
        "错误页不得自动删除 repo 配置。",
        "错误页不得移动、重命名或删除用户文件。",
    ] {
        assert_contains(S1_11_MAIN_REPO_ERROR, fragment);
    }
    for fragment in [
        "文件缺失或只读 repo：仍可查看日志；只禁用会修改文件或索引的操作。",
        "Core `list_changes`。",
        "FSEvents 同步结果。",
        "只读或缺失文件仍可查看已有日志。",
    ] {
        assert_contains(S1_13_DETAIL_LOG, fragment);
    }
}

fn assert_rust_entry_points_are_real_removed_wiring() {
    for fragment in [
        "C1-19 owns the `ExternalEventKind::Removed` contract",
        "only confirms the path is absent",
        "marks the matching active row as `status = deleted`",
        "`deleted_at`",
        "`change_log.action = deleted`",
        "`SyncResult::detected_deletes`",
        "must not",
        "remove, trash, move, rename, overwrite, copy, or download",
        "Deleted rows are not visible to default `list_files`",
        "return `CoreError::FileNotFound { path }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "ExternalEventKind::Removed =>",
        "plan_removed_event",
        "ensure_path_absent",
        "find_active_file_by_path",
        "external_removed_detail",
        "has_icloud_placeholder_marker",
        "cursor_for_batch",
    ] {
        assert_contains(SYNC_RS, fragment);
    }

    for fragment in [
        "apply_external_sync_batch",
        "soft_delete_external_removed_file",
        "deleted_at = strftime('%s', 'now')",
        "status = 'deleted'",
        "'deleted'",
        "set_cursor(&tx, last_event_id)",
        "tx.commit()",
    ] {
        assert_contains(DB_SYNC_RS, fragment);
    }
}

#[test]
fn sync_external_removed_integration_verify_real_flow_reaches_list_detail_log_tree_and_cursor() {
    let repo = initialized_repo();
    let removed_entry = sync_created_file(repo.path(), "docs/remove.pdf", b"remove bytes", 900);
    let keeper_entry = sync_created_file(repo.path(), "docs/keeper.pdf", b"keeper bytes", 901);
    let keeper_before_sync =
        fs::read(repo.path().join("docs/keeper.pdf")).expect("read keeper before removed sync");
    fs::remove_file(repo.path().join("docs/remove.pdf")).expect("simulate external deletion");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/remove.pdf", 902)],
    )
    .expect("sync external removed event");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 1);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(902));

    assert_only_keeper_is_visible(repo.path(), keeper_entry.id);
    assert!(matches!(
        get_file(path_string(repo.path()), removed_entry.id),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_eq!(file_status(repo.path(), removed_entry.id).0, "deleted");
    assert!(
        file_status(repo.path(), removed_entry.id).1.is_some(),
        "deleted_at should be populated for missing recovery UI"
    );

    let include_deleted = listed_files(repo.path(), include_deleted_file_filter());
    assert!(include_deleted
        .iter()
        .any(|file| file.id == removed_entry.id));
    assert!(include_deleted
        .iter()
        .any(|file| file.id == keeper_entry.id));

    let changes = list_changes(path_string(repo.path()), change_filter(removed_entry.id))
        .expect("list detail-log for deleted entry");
    let deleted_change = changes
        .iter()
        .find(|change| change.action == "deleted")
        .expect("deleted change should be visible to detail-log");
    assert_eq!(deleted_change.file_id, Some(removed_entry.id));
    assert_eq!(deleted_change.filename, "remove.pdf");
    assert_eq!(deleted_change.category, "docs");
    let detail = change_detail(deleted_change);
    assert_eq!(detail["hard"], false);
    assert_eq!(detail["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/keeper.pdf")).expect("keeper user file remains readable"),
        keeper_before_sync
    );
}

#[test]
fn sync_external_removed_integration_verify_boundaries_stay_transactional_and_scope_limited() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/present.pdf", b"present bytes", 910);

    let existing_path = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/present.pdf", 911)],
    );

    assert!(matches!(existing_path, Err(CoreError::Io { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(910));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("active row remains visible")
            .path,
        "docs/present.pdf"
    );
    assert_eq!(
        file_status(repo.path(), entry.id),
        ("active".to_owned(), None)
    );
    assert_eq!(
        fs::read(repo.path().join("docs/present.pdf")).expect("user file remains readable"),
        b"present bytes"
    );

    fs::remove_file(repo.path().join("docs/present.pdf")).expect("simulate external deletion");
    let partial_scope = sync_external_changes(
        path_string(repo.path()),
        vec![
            removed("docs/present.pdf", 912),
            modified("docs/present.pdf", 913),
        ],
    )
    .expect("sync only the bound removed capability");

    assert_eq!(partial_scope.detected_creates, 0);
    assert_eq!(partial_scope.detected_renames, 0);
    assert_eq!(partial_scope.detected_deletes, 1);
    assert_eq!(partial_scope.detected_modifies, 0);
    assert_eq!(fs_cursor(repo.path()), Some(910));
    assert_eq!(count_deleted_changes(repo.path(), entry.id), 1);
}

fn count_deleted_changes(repo: &Path, file_id: i64) -> usize {
    list_changes(path_string(repo), change_filter(file_id))
        .expect("list changes")
        .into_iter()
        .filter(|change| change.action == "deleted")
        .count()
}
