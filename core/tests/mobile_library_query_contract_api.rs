use area_matrix_core::{
    get_file, list_changes, list_files, list_tree_json, ChangeFilter, ChangeLogEntry, CoreError,
    CoreResult, FileAvailabilityStatus, FileEntry, FileFilter, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../workflow/versions/v1-mvp/execution/phase-4/4-3-stage4-multiplatform/task-11-c4-03-contract-api.md"
);
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
        availability_status: FileAvailabilityStatus::Missing,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_900,
    };
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.origin, FileOrigin::External);
    assert_eq!(
        entry.source_path.as_deref(),
        Some("/provider/docs/report.pdf")
    );
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Missing);

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
        "FileAvailabilityStatus availability_status;",
        "enum FileAvailabilityStatus { \"Available\", \"Missing\" };",
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
        "`FileEntry.availability_status` 会结构化标记 backing file 是否 `Missing`",
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
        "C4-03 reuses this query for `S4-IOS-02` mobile-library rows.",
        "availability status",
        "must use the documented `limit` and `offset` fields",
        "missing-file recovery stays with C4-18",
        "C4-03 allows a mobile list row to open a Core-backed detail record",
        "C4-07 composes this API with [`list_changes`] and",
        "lazily request a small `limit`/`offset`",
        "does not trigger filesystem rescan, sync",
        "C4-03 mobile-library uses this tree snapshot",
    ] {
        assert_contains(API_RS, fragment);
    }
}
