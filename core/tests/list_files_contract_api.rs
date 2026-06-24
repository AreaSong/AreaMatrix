use area_matrix_core::{list_files, CoreError, CoreResult, FileEntry, FileFilter};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn list_files_contract_api_exposes_documented_signature_filter_and_errors() {
    fn assert_list_files(_: fn(String, FileFilter) -> CoreResult<Vec<FileEntry>>) {}
    assert_list_files(list_files);

    let filter = FileFilter {
        category: Some("docs".to_owned()),
        include_deleted: Some(false),
        imported_after: Some(10),
        imported_before: Some(20),
        limit: 50,
        offset: 5,
    };

    assert_eq!(filter.category.as_deref(), Some("docs"));
    assert_eq!(filter.include_deleted, Some(false));
    assert_eq!(filter.imported_after, Some(10));
    assert_eq!(filter.imported_before, Some(20));
    assert_eq!(filter.limit, 50);
    assert_eq!(filter.offset, 5);
    assert!(matches!(
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::RepoNotInitialized { .. }
    ));
    assert!(matches!(
        CoreError::db("database error"),
        CoreError::Db { .. }
    ));
}

#[test]
fn list_files_contract_api_docs_api_udl_and_consumers_stay_aligned() {
    for fragment in [
        "sequence<FileEntry> list_files(string repo_path, FileFilter filter);",
        "dictionary FileFilter",
        "string? category;",
        "boolean? include_deleted;",
        "i64? imported_after;",
        "i64? imported_before;",
        "i64 limit;",
        "i64 offset;",
        "dictionary FileEntry",
        "i64 imported_at;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_contains(
        CORE_API,
        "按 `imported_at DESC` 排序。`limit > 1000` 自动 clamp。",
    );

    for fragment in ["`Db { message }`", "`RepoNotInitialized { path }`"] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "The file-list API is the read-only metadata query",
        "exact category filtering",
        "import-time bounds",
        "are ordered by `imported_at DESC`.",
        "must not write repository metadata or mutate user files",
        "tag filtering, smart lists",
        "Returns `CoreError::RepoNotInitialized { path }`",
        "`CoreError::Db { message }` when SQLite rows cannot be read",
    ] {
        assert_contains(API_RS, fragment);
    }
}
