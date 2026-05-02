use area_matrix_core::{
    sync_external_changes, CoreError, CoreResult, ExternalEvent, ExternalEventKind, SyncResult,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md");
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
fn sync_external_removed_contract_api_exposes_documented_signature_input_and_output() {
    fn assert_sync(_: fn(String, Vec<ExternalEvent>) -> CoreResult<SyncResult>) {}
    assert_sync(sync_external_changes);

    let event = ExternalEvent {
        path: "docs/removed.pdf".to_owned(),
        kind: ExternalEventKind::Removed,
        fs_event_id: 319,
    };
    assert_eq!(event.path, "docs/removed.pdf");
    assert_eq!(event.kind, ExternalEventKind::Removed);
    assert_eq!(event.fs_event_id, 319);

    let result = SyncResult {
        detected_creates: 0,
        detected_renames: 0,
        detected_deletes: 1,
        detected_modifies: 0,
        errors: Vec::new(),
    };
    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 1);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());

    let documented_errors = [CoreError::FileNotFound, CoreError::Db, CoreError::Io];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn sync_external_removed_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "# C1-19 sync-external-removed",
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

    for fragment in [
        "| S1-11 | main-repo-error | C1-01, C1-19, C1-21 |",
        "`validate_initialized_repo_path`, `sync_external_changes`",
        "| S1-13 | detail-log | C1-13, C1-17, C1-18, C1-19 |",
        "`list_changes`, `sync_external_changes`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突",
        "详情、日志、笔记、Tree、recovery、错误映射",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "FileNotFound();",
        "Db();",
        "Io();",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn sync_external_removed_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in ["`FileNotFound { path }`", "`Db(msg)`", "`Io(msg)`"] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "C1-19 owns the `ExternalEventKind::Removed` contract",
        "A removed event's",
        "`path` is the repository-relative or absolute path",
        "app-layer debounce and rename pairing",
        "only confirms the path is absent",
        "`status = deleted`",
        "`deleted_at`",
        "`updated_at`",
        "`change_log.action =",
        "deleted`",
        "external deletion detail",
        "`SyncResult::detected_deletes`",
        "must not",
        "remove, trash, move, rename, overwrite, copy, or download",
        "not visible to default `list_files`",
        "`CoreError::FileNotFound`",
        "through `get_file`",
        "Returns `CoreError::FileNotFound`",
        "`CoreError::Db`",
        "`CoreError::Io`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Filesystem event kind sent from the platform layer.",
        "externally removed",
        "External filesystem event from the platform layer.",
        "Repository-relative or absolute path supplied by the platform layer.",
        "Platform filesystem event identifier.",
        "Summary of external-change synchronization.",
        "Number of removed paths reflected as deleted metadata rows.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
