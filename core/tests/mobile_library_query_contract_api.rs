use area_matrix_core::{
    get_file, list_changes, list_files, list_tree_json, ChangeFilter, ChangeLogEntry, CoreError,
    CoreResult, FileEntry, FileFilter, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-11-c4-03-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-03-mobile-library-query.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const MOBILE_LIBRARY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-02-mobile-library.md");
const MOBILE_DETAIL_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-05-mobile-file-detail.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn mobile_library_query_contract_exports_existing_query_signatures_and_page_inputs() {
    fn assert_list_files(_: fn(String, FileFilter) -> CoreResult<Vec<FileEntry>>) {}
    fn assert_get_file(_: fn(String, i64) -> CoreResult<FileEntry>) {}
    fn assert_list_changes(_: fn(String, ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>) {}
    fn assert_tree(_: fn(String, String) -> CoreResult<String>) {}

    assert_list_files(list_files);
    assert_get_file(get_file);
    assert_list_changes(list_changes);
    assert_tree(list_tree_json);

    let file_filter = FileFilter {
        category: Some("docs".to_owned()),
        include_deleted: Some(false),
        imported_after: Some(1_777_300_000),
        imported_before: None,
        limit: 50,
        offset: 100,
    };
    assert_eq!(file_filter.limit, 50);
    assert_eq!(file_filter.offset, 100);

    let change_filter = ChangeFilter {
        file_id: Some(42),
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 20,
        offset: 0,
    };
    assert_eq!(change_filter.file_id, Some(42));
    assert_eq!(change_filter.limit, 20);

    let entry = FileEntry {
        id: 42,
        path: "docs/report.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report.pdf".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 4096,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Indexed,
        origin: FileOrigin::External,
        source_path: Some("/provider/docs/report.pdf".to_owned()),
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_900,
    };
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.origin, FileOrigin::External);
    assert_eq!(entry.source_path.as_deref(), Some("/provider/docs/report.pdf"));

    let change = ChangeLogEntry {
        id: 7,
        file_id: Some(entry.id),
        filename: entry.current_name.clone(),
        category: entry.category.clone(),
        action: "external_modified".to_owned(),
        detail_json: "{}".to_owned(),
        occurred_at: 1_777_300_950,
    };
    assert_eq!(change.file_id, Some(42));
    assert_eq!(change.action, "external_modified");

    let documented_errors = [
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::db("database error"),
        CoreError::file_not_found("missing file"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn mobile_library_query_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "# 4-3/task-11: C4-03 contract-api",
        "为 C4-03 mobile-library-query 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-03 mobile-library-query",
        "- S4-IOS-02 mobile-library",
        "- S4-IOS-05 mobile-file-detail",
        "- `list_files`",
        "- `get_file`",
        "- `list_tree_json`",
        "- `list_changes`",
        "repo path、filter、pagination。",
        "移动端可分页数据。",
        "- 无写入。",
        "- `Db`",
        "- `RepoNotInitialized`",
        "移动端不需要一次加载全库。",
        "详情数据来自 Core，而非平台侧扫描。",
        "缺失文件状态可被 UI 表达。",
        "离线缓存同步策略后续细化。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-02 | mobile-library | C4-03 | mobile list/tree query | 分页，不全量加载",
        "| S4-IOS-05 | mobile-file-detail | C4-07 | detail/log/note query | 缺失进入 recovery",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "sequence<FileEntry> list_files(string repo_path, FileFilter filter);",
        "FileEntry get_file(string repo_path, i64 file_id);",
        "sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);",
        "string list_tree_json(string repo_path, string locale);",
        "dictionary FileFilter",
        "i64 limit;",
        "i64 offset;",
        "dictionary ChangeFilter",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "dictionary ChangeLogEntry",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_files(repo, filter)` | query | √ | Db |",
        "| `get_file(repo, file_id)` | query | √ | FileNotFound |",
        "| `list_changes(repo, filter)` | query | √ | Db |",
        "| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / Io |",
        "按 `imported_at DESC` 排序。`limit > 1000` 自动 clamp。",
        "单条 `list_files`（limit ≤ 50）",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`RepoNotInitialized { path }`",
        "`Db { message }`",
        "`FileNotFound { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn mobile_library_query_documents_consumer_state_without_adjacent_capabilities() {
    for fragment in [
        "浏览分类、最近文件、冲突文件三个核心集合。",
        "显示 iCloud 占位符、冲突、缺失文件等状态，不静默吞掉。",
        "缺失文件：行保留，显示 `Missing`，进入详情时给恢复动作。",
        "下拉刷新触发只读状态刷新",
        "不启动 `Run rescan now`。",
        "Core list/tree/recent API。",
        "点击文件行进入移动端详情页。",
    ] {
        assert_contains(MOBILE_LIBRARY_PAGE, fragment);
    }

    for fragment in [
        "Core file metadata API。",
        "Core change log API。",
        "缺失文件：显示 `File is missing from the repository`",
        "进入 `S4-X-06 missing-file-recovery`。",
        "Note 读写 API。",
    ] {
        assert_contains(MOBILE_DETAIL_PAGE, fragment);
    }

    for fragment in [
        "C4-03 reuses this query for `S4-IOS-02` mobile-library rows.",
        "must use the documented `limit` and `offset` fields",
        "missing-file recovery stays with C4-18",
        "C4-03 allows a mobile list row to open a Core-backed detail record",
        "C4-07 owns the mobile detail aggregation",
        "lazily request a small `limit`/`offset`",
        "does not trigger filesystem rescan or sync repair",
        "C4-03 mobile-library uses this tree snapshot",
    ] {
        assert_contains(API_RS, fragment);
    }
}
