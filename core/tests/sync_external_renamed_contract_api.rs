use area_matrix_core::{
    sync_external_changes, CoreError, CoreResult, ExternalEvent, ExternalEventKind, SyncResult,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md");
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
fn sync_external_renamed_contract_api_exposes_documented_signature_input_and_output() {
    fn assert_sync(_: fn(String, Vec<ExternalEvent>) -> CoreResult<SyncResult>) {}
    assert_sync(sync_external_changes);

    let event = ExternalEvent {
        path: "docs/renamed.pdf".to_owned(),
        kind: ExternalEventKind::Renamed,
        fs_event_id: 184,
    };
    assert_eq!(event.path, "docs/renamed.pdf");
    assert_eq!(event.kind, ExternalEventKind::Renamed);
    assert_eq!(event.fs_event_id, 184);

    let result = SyncResult {
        detected_creates: 0,
        detected_renames: 1,
        detected_deletes: 0,
        detected_modifies: 0,
        errors: Vec::new(),
    };
    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::conflict("path conflict"),
        CoreError::db("database error"),
        CoreError::io("io error"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn sync_external_renamed_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "# C1-18 sync-external-renamed",
        "- S1-09 main-list",
        "- S1-13 detail-log",
        "- `sync_external_changes(repo_path, events)`",
        "- `ExternalEvent { kind: Renamed, path, fs_event_id }`",
        "- 可能需要 app 层合并 old/new path。",
        "- `SyncResult.detected_renames`",
        "- 更新 `files.path`、`files.current_name`、`updated_at`。",
        "- 写入 `change_log.renamed`。",
        "- 只读确认新路径存在。",
        "- 不主动重命名用户文件。",
        "- `FileNotFound`",
        "- `Conflict`",
        "- `Db`",
        "- `Io`",
        "- 外部 rename 后列表和详情显示新名称。",
        "- change log 保留 old/new path。",
        "- 无法配对 rename 时可降级为 removed + created。",
        "- 跨目录复杂 rename 配对优化属于 Stage 2。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
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
        "i64 detected_renames;",
        "sequence<string> errors;",
        "enum ExternalEventKind { \"Created\", \"Removed\", \"Modified\", \"Renamed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn sync_external_renamed_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in [
        "`FileNotFound { path }`",
        "`Conflict { path }`",
        "`Db { message }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "C1-18 owns the `ExternalEventKind::Renamed` contract",
        "A rename event's",
        "`path` is the repository-relative or absolute new path",
        "app-layer",
        "FSEvents pairing/debounce",
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
        "cannot be paired",
        "removed + created",
        "Returns `CoreError::FileNotFound { path }`",
        "`CoreError::Conflict { path }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Filesystem event kind sent from the platform layer.",
        "A path was renamed.",
        "External filesystem event from the platform layer.",
        "Repository-relative or absolute path supplied by the platform layer.",
        "Platform filesystem event identifier.",
        "Summary of external-change synchronization.",
        "Number of renames detected.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
