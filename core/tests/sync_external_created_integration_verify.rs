use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, list_tree_json,
    sync_external_changes, ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileFilter,
    FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

const API_RS: &str = include_str!("../src/api.rs");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DB_SYNC_RS: &str = include_str!("../src/db/sync.rs");
const SYNC_RS: &str = include_str!("../src/sync/mod.rs");
const S1_09_MAIN_LIST: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md");
const S1_10_MAIN_LOADING: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md");
const S1_13_DETAIL_LOG: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md");
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

fn created(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Created,
        fs_event_id,
    }
}

fn modified(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Modified,
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
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

#[test]
fn sync_external_created_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_17_capability_spec();
    assert_core_api_and_udl_contract();
    assert_stage_one_consumers();
    assert_rust_entry_points_are_real_created_wiring();
}

fn assert_c1_17_capability_spec() {
    for fragment in [
        "C1-17 sync-external-created",
        "- S1-09 main-list",
        "- S1-10 main-loading",
        "- S1-13 detail-log",
        "- `sync_external_changes(repo_path, events)`",
        "- `get_fs_event_cursor(repo_path)`",
        "- `set_fs_event_cursor(repo_path, last_event_id)`",
        "- `ExternalEvent { kind: Created, path, fs_event_id }`",
        "- `SyncResult.detected_creates`",
        "- 新建 `files.origin = External`。",
        "- 写入 `change_log.external_modified` 或更具体动作。",
        "- 更新 `fs_event_cursor`。",
        "- 读取新增文件 metadata/hash。",
        "- 不移动、不覆盖新增文件。",
        "- `.areamatrix/` 和 generated overview 被跳过。",
        "- cursor 只在事件批次成功处理后推进。",
        "- FSEvents 启停与去抖属于 macOS app 层。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);",
        "i64? get_fs_event_cursor(string repo_path);",
        "void set_fs_event_cursor(string repo_path, i64 last_event_id);",
        "dictionary ExternalEvent",
        "string path;",
        "ExternalEventKind kind;",
        "i64 fs_event_id;",
        "dictionary SyncResult",
        "i64 detected_creates;",
        "i64 detected_renames;",
        "i64 detected_deletes;",
        "i64 detected_modifies;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `sync_external_changes(repoPath, events) throws -> SyncResult`",
        "去抖 + InFlight 过滤后传入",
        "### `get_fs_event_cursor(repoPath) throws -> Int64?`",
        "### `set_fs_event_cursor(repoPath, lastEventId) throws`",
        "每批 sync 完成后保存 cursor",
        "`sync_external_changes`（批量事件）",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_stage_one_consumers() {
    for fragment in [
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json`",
        "| S1-13 | detail-log | C1-13, C1-17, C1-18, C1-19 | `list_changes`, `sync_external_changes`",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "FSEvents external created：当前分类新增行并保持现有选择；如果分类不匹配，只更新 Tree 计数。",
        "FSEvents sync error / partial failure：显示 non-blocking banner",
        "Core `list_tree_json`，由 UI store 转成 sidebar tree。",
        "FSEvents 回流通知。",
    ] {
        assert_contains(S1_09_MAIN_LIST, fragment);
    }
    for fragment in [
        "rescan 有进度和失败提示。",
        "列表加载期间写操作禁用且不会误作用到旧 selection。",
        "scan progress。",
    ] {
        assert_contains(S1_10_MAIN_LOADING, fragment);
    }
    for fragment in [
        "刚发生外部修改时可追加新记录并保持当前选中。",
        "Core `list_changes`。",
        "FSEvents 同步结果。",
        "Collect Diagnostics 不包含用户文件内容。",
    ] {
        assert_contains(S1_13_DETAIL_LOG, fragment);
    }
}

fn assert_rust_entry_points_are_real_created_wiring() {
    for fragment in [
        "C1-17 owns the `ExternalEventKind::Created` contract",
        "`storage_mode = StorageMode::Indexed`",
        "`origin = FileOrigin::External`",
        "`change_log.action =",
        "external_modified`",
        "`kind = create`",
        "Cursor persistence is part of the batch success contract",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "ExternalEventKind::Created =>",
        "plan_created_event",
        "should_skip_relative_path",
        "has_icloud_placeholder_marker",
        "external_create_detail",
        "cursor_for_batch",
        "sha256_file",
    ] {
        assert_contains(SYNC_RS, fragment);
    }

    for fragment in [
        "apply_external_sync_batch",
        "INSERT OR IGNORE INTO files",
        "'external'",
        "storage_mode_to_db(&crate::StorageMode::Indexed)",
        "INSERT INTO change_log",
        "'external_modified'",
        "set_cursor(&tx, last_event_id)",
        "tx.commit()",
    ] {
        assert_contains(DB_SYNC_RS, fragment);
    }
}

#[test]
fn sync_external_created_integration_verify_real_flow_reaches_list_tree_detail_log_and_cursor() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/external.md", b"created by Finder");
    let before_bytes = fs::read(repo.path().join("docs/external.md")).expect("read user file");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.md", 310)],
    )
    .expect("sync created event");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(310));

    let files = list_files(path_string(repo.path()), default_file_filter()).expect("list files");
    assert_eq!(files.len(), 1);
    let file = &files[0];
    assert_eq!(file.path, "docs/external.md");
    assert_eq!(file.category, "docs");
    assert_eq!(file.storage_mode, StorageMode::Indexed);
    assert_eq!(file.origin, FileOrigin::External);
    assert_eq!(file.source_path, None);

    let detail = get_file(path_string(repo.path()), file.id).expect("get synced detail");
    assert_eq!(detail.path, "docs/external.md");
    let tree_json = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect("list tree for main-list and loading consumers");
    assert!(tree_json.contains("\"docs\""));

    let mut filter = default_change_filter();
    filter.file_id = Some(file.id);
    let changes = list_changes(path_string(repo.path()), filter).expect("list detail-log");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].action, "external_modified");
    let change = change_detail(&changes[0]);
    assert_eq!(change["kind"], "create");
    assert_eq!(change["path"], "docs/external.md");
    assert_eq!(change["category"], "docs");
    assert_eq!(change["hash_after"], file.hash_sha256);
    assert_eq!(change["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/external.md")).expect("user file remains untouched"),
        before_bytes
    );
}

#[test]
fn sync_external_created_integration_verify_scope_boundaries_do_not_claim_adjacent_sync() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/created.txt", b"created");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/created.txt", 320),
            modified("docs/created.txt", 321),
        ],
    )
    .expect("sync only the bound created capability");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), None);
}

#[test]
fn sync_external_created_integration_verify_skip_and_failure_boundaries_are_transactional() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/internal.md",
        b"generated",
    );
    write_repo_file(repo.path(), "AREAMATRIX.md", b"overview");
    write_repo_file(repo.path(), "docs/good.txt", b"good");

    let skipped = sync_external_changes(
        path_string(repo.path()),
        vec![
            created(".areamatrix/generated/internal.md", 330),
            created("AREAMATRIX.md", 331),
        ],
    )
    .expect("skip AreaMatrix-owned generated paths");
    assert_eq!(skipped.detected_creates, 0);
    assert_eq!(fs_cursor(repo.path()), Some(331));
    assert!(list_files(path_string(repo.path()), default_file_filter())
        .expect("list files after skip")
        .is_empty());

    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/good.txt", 332),
            created("docs/missing.txt", 333),
        ],
    );
    assert_eq!(failed, Err(CoreError::Io));
    assert_eq!(fs_cursor(repo.path()), Some(331));
    assert!(list_files(path_string(repo.path()), default_file_filter())
        .expect("list files after failed batch")
        .is_empty());
    assert_eq!(
        fs::read(repo.path().join("docs/good.txt")).expect("good user file remains readable"),
        b"good"
    );
}
