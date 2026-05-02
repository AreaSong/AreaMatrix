use area_matrix_core::{
    get_fs_event_cursor, set_fs_event_cursor, sync_external_changes, CoreError, CoreResult,
    ExternalEvent, ExternalEventKind, SyncResult,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn sync_external_created_contract_api_exposes_documented_signatures_inputs_and_outputs() {
    fn assert_sync(_: fn(String, Vec<ExternalEvent>) -> CoreResult<SyncResult>) {}
    fn assert_get_cursor(_: fn(String) -> CoreResult<Option<i64>>) {}
    fn assert_set_cursor(_: fn(String, i64) -> CoreResult<()>) {}

    assert_sync(sync_external_changes);
    assert_get_cursor(get_fs_event_cursor);
    assert_set_cursor(set_fs_event_cursor);

    let event = ExternalEvent {
        path: "docs/new.pdf".to_owned(),
        kind: ExternalEventKind::Created,
        fs_event_id: 42,
    };
    assert_eq!(event.path, "docs/new.pdf");
    assert_eq!(event.kind, ExternalEventKind::Created);
    assert_eq!(event.fs_event_id, 42);

    let result = SyncResult {
        detected_creates: 1,
        detected_renames: 0,
        detected_deletes: 0,
        detected_modifies: 0,
        errors: Vec::new(),
    };
    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());

    let documented_errors = [
        CoreError::InvalidPath,
        CoreError::ICloudPlaceholder,
        CoreError::Db,
        CoreError::Io,
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn sync_external_created_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "# C1-17 sync-external-created",
        "- S1-09 main-list",
        "- S1-10 main-loading",
        "- S1-13 detail-log",
        "- `sync_external_changes(repo_path, events)`",
        "- `get_fs_event_cursor(repo_path)`",
        "- `set_fs_event_cursor(repo_path, last_event_id)`",
        "- `ExternalEvent { kind: Created, path, fs_event_id }`",
        "- `SyncResult.detected_creates`",
        "- 新建 `files.origin = External`。",
        "- 更新 `fs_event_cursor`。",
        "- 读取新增文件 metadata/hash。",
        "- 不移动、不覆盖新增文件。",
        "- `InvalidPath`",
        "- `ICloudPlaceholder`",
        "- `Db`",
        "- `Io`",
        "- `.areamatrix/` 和 generated overview 被跳过。",
        "- cursor 只在事件批次成功处理后推进。",
        "- FSEvents 启停与去抖属于 macOS app 层。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json`",
        "| S1-13 | detail-log | C1-13, C1-17, C1-18, C1-19 | `list_changes`, `sync_external_changes`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "sequence<string> errors;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn sync_external_created_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in [
        "`InvalidPath { path }`",
        "`ICloudPlaceholder { path }`",
        "`Db(msg)`",
        "`Io(msg)`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "Synchronizes external filesystem changes after app-layer filtering.",
        "C1-17 owns the `ExternalEventKind::Created` contract",
        "platform layer is responsible for FSEvents startup, debounce",
        "in-flight filtering, and iCloud placeholder download coordination",
        "inserts an active",
        "`FileEntry`",
        "`storage_mode = StorageMode::Indexed`",
        "`origin = FileOrigin::External`",
        "queryable change-log entry",
        "`SyncResult::detected_creates`",
        "skip `.areamatrix/`",
        "generated overview output",
        "delete, rename, overwrite, copy, or download",
        "Cursor persistence is part of the batch success contract",
        "Returns `CoreError::InvalidPath`",
        "`CoreError::ICloudPlaceholder`",
        "`CoreError::Io`",
        "`CoreError::Db`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "External filesystem event from the platform layer.",
        "Repository-relative or absolute path supplied by the platform layer.",
        "Platform filesystem event identifier.",
        "Summary of external-change synchronization.",
        "Number of created paths detected.",
        "Human-readable errors.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
