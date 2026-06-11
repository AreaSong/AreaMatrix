use area_matrix_core::{
    get_file, list_files, list_tree_json, search_files, CoreError, CoreResult,
    FileAvailabilityStatus, FileEntry, FileFilter, FileOrigin, SearchFilter, SearchIndexStatus,
    SearchPagination, SearchResultPage, SearchScope, SearchSort, SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-51-c4-11-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-11-desktop-main-query.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const WINDOWS_MAIN_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-02-main-window.md");
const LINUX_MAIN_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-02-main-window.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const SEARCH_RS: &str = include_str!("../src/search.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn desktop_main_query_contract_exports_existing_query_signatures() {
    fn assert_list_files(_: fn(String, FileFilter) -> CoreResult<Vec<FileEntry>>) {}
    fn assert_get_file(_: fn(String, i64) -> CoreResult<FileEntry>) {}
    fn assert_tree(_: fn(String, String) -> CoreResult<String>) {}
    fn assert_search(
        _: fn(
            String,
            String,
            SearchFilter,
            SearchSort,
            SearchPagination,
        ) -> CoreResult<SearchResultPage>,
    ) {
    }

    assert_list_files(list_files);
    assert_get_file(get_file);
    assert_tree(list_tree_json);
    assert_search(search_files);

    let list_filter = FileFilter {
        category: Some("docs".to_owned()),
        include_deleted: Some(false),
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 200,
    };
    assert_eq!(list_filter.limit, 100);
    assert_eq!(list_filter.offset, 200);

    let search_filter = SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: Some("docs".to_owned()),
        file_kind: Some("pdf".to_owned()),
        tags: Vec::new(),
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: Some(StorageMode::Indexed),
        include_deleted: Some(false),
    };
    let search_pagination = SearchPagination {
        limit: 50,
        offset: 0,
    };
    assert_eq!(search_filter.scope, SearchScope::AllRepo);
    assert_eq!(search_filter.storage_mode, Some(StorageMode::Indexed));
    assert_eq!(search_pagination.limit, 50);

    let entry = FileEntry {
        id: 411,
        path: "docs/report.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report.pdf".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 4096,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Indexed,
        origin: FileOrigin::External,
        source_path: Some("/desktop/docs/report.pdf".to_owned()),
        availability_status: FileAvailabilityStatus::Missing,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_900,
    };
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Missing);

    let page = SearchResultPage {
        query: "report".to_owned(),
        total_count: 0,
        results: Vec::new(),
        diagnostics: Vec::new(),
        index_status: SearchIndexStatus::Ready,
    };
    assert_eq!(page.index_status, SearchIndexStatus::Ready);

    let documented_errors = [
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn desktop_main_query_docs_core_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-51: C4-11 contract-api",
        "为 C4-11 desktop-main-query 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-11 desktop-main-query",
        "- S4-WIN-02 main-window",
        "- S4-LNX-02 main-window",
        "- `list_files`",
        "- `get_file`",
        "- `list_tree_json`",
        "- `search_files`",
        "repo path、filter、pagination。",
        "跨桌面平台主窗口数据。",
        "- 只读。",
        "- 无写入。",
        "- `Db`",
        "- `RepoNotInitialized`",
        "Windows/Linux 主窗口使用同一 Core 查询能力。",
        "平台 UI 不直接扫描 repo 拼列表。",
        "大库分页可用。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-02 | main-window | C4-11 | desktop query | 平台 UI 不直接扫描 repo",
        "| S4-LNX-02 | main-window | C4-11 | desktop query | 平台 UI 不直接扫描 repo",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "sequence<FileEntry> list_files(string repo_path, FileFilter filter);",
        "FileEntry get_file(string repo_path, i64 file_id);",
        "string list_tree_json(string repo_path, string locale);",
        "SearchResultPage search_files(",
        "SearchFilter filter,",
        "SearchPagination pagination",
        "dictionary FileFilter",
        "i64 limit;",
        "i64 offset;",
        "dictionary SearchPagination",
        "dictionary SearchResultPage",
        "FileAvailabilityStatus availability_status;",
        "RepoNotInitialized(string path);",
        "Db(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_files(repo, filter)` | query | √ | Db |",
        "| `search_files(repo, query, filter, sort, pagination)` | search | √ | Db / Config / InvalidPath |",
        "| `get_file(repo, file_id)` | query | √ | FileNotFound |",
        "| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / Io |",
        "### `list_files(repoPath, filter) throws -> [FileEntry]`",
        "按 `imported_at DESC` 排序。`limit > 1000` 自动 clamp。",
        "### `search_files(repoPath, query, filter, sort, pagination) throws -> SearchResultPage`",
        "### `get_file(repoPath, fileId) throws -> FileEntry`",
        "返回的 `FileEntry.availability_status` 与 `list_files` 一致",
        "### `list_tree_json(repoPath, locale) throws -> String`",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in ["`RepoNotInitialized { path }`", "`Db { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn desktop_main_query_documents_consumer_state_without_adjacent_capabilities() {
    for fragment in [
        "显示资料库分类树或导航栏。",
        "显示当前分类的文件列表。",
        "显示右侧详情：Meta、Log、Note 摘要。",
        "提供搜索入口",
        "只刷新当前 UI 和 Core 只读 snapshot，不触发全库 rescan。",
        "DB locked：顶部显示黄色 banner，允许重试，不清空列表缓存。",
        "缺失文件：列表行保留并标记，详情提供恢复入口。",
        "Rust core list/detail/change log/note API。",
        "`Refresh` 不写 DB、不触发 watcher 回流",
    ] {
        assert_contains(WINDOWS_MAIN_PAGE, fragment);
    }

    for fragment in [
        "浏览分类和文件列表。",
        "查看文件详情：Meta、Log、Note。",
        "提供 `Refresh`，只刷新当前 UI 和 Core 只读 snapshot，不触发全库 rescan。",
        "DB locked：保留缓存列表并显示重试。",
        "权限不足：文件行或详情显示恢复动作，不自动 chmod。",
        "Rust core list/detail/log/note API。",
        "`Refresh` 不写 DB、不触发 inotify 回流",
    ] {
        assert_contains(LINUX_MAIN_PAGE, fragment);
    }

    for fragment in [
        "C4-11 reuses the same paginated metadata query",
        "`S4-WIN-02` and",
        "`S4-LNX-02` desktop main-window rows",
        "must not scan the",
        "repository directly",
        "`FileFilter::limit` and",
        "`FileFilter::offset` carry the page request",
        "C4-11 desktop main-window consumers use this detail query",
        "does not add platform-side preview, watcher, rescan, or",
        "recovery behavior",
        "C4-11 desktop main-window consumers may use the same tree snapshot",
        "Core only returns the read-only tree JSON",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-11 desktop main-window consumers may use this same read-only page shape",
        "Windows and Linux search entry",
        "only supplies paginated results, diagnostics, and index readiness",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for fragment in [
        "C4-11 desktop-main-query reuses list_files, get_file, list_tree_json,",
        "and search_files for S4-WIN-02/S4-LNX-02 main-window state.",
        "Desktop",
        "shells page through FileFilter.limit/offset",
        "C4-11 also uses this read-only tree JSON for desktop sidebar state.",
    ] {
        assert_contains(UDL, fragment);
    }
}
