use area_matrix_core::{list_changes, ChangeFilter, ChangeLogEntry, CoreError, CoreResult};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn list_change_log_contract_api_exposes_documented_signature_filter_and_errors() {
    fn assert_list_changes(_: fn(String, ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>) {}
    assert_list_changes(list_changes);

    let filter = ChangeFilter {
        file_id: Some(42),
        category: Some("finance".to_owned()),
        action: Some("renamed".to_owned()),
        since: Some(100),
        until: Some(200),
        limit: 50,
        offset: 10,
    };

    assert_eq!(filter.file_id, Some(42));
    assert_eq!(filter.category.as_deref(), Some("finance"));
    assert_eq!(filter.action.as_deref(), Some("renamed"));
    assert_eq!(filter.since, Some(100));
    assert_eq!(filter.until, Some(200));
    assert_eq!(filter.limit, 50);
    assert_eq!(filter.offset, 10);

    let entry = ChangeLogEntry {
        id: 7,
        file_id: Some(42),
        filename: "report.pdf".to_owned(),
        category: "finance".to_owned(),
        action: "renamed".to_owned(),
        detail_json: r#"{"from_name":"draft.pdf","final_name":"report.pdf"}"#.to_owned(),
        occurred_at: 150,
    };

    assert_eq!(entry.file_id, Some(42));
    assert_eq!(entry.filename, "report.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.action, "renamed");
    serde_json::from_str::<serde_json::Value>(&entry.detail_json)
        .expect("contract fixture detail_json is parseable JSON");
    assert_eq!(entry.occurred_at, 150);

    let documented_errors = [
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn list_change_log_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);",
        "dictionary ChangeFilter",
        "i64? file_id;",
        "string? category;",
        "string? action;",
        "i64? since;",
        "i64? until;",
        "i64 limit;",
        "i64 offset;",
        "dictionary ChangeLogEntry",
        "i64 id;",
        "i64? file_id;",
        "string filename;",
        "string category;",
        "string action;",
        "string detail_json;",
        "i64 occurred_at;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `list_changes(repoPath, filter) throws -> [ChangeLogEntry]`",
        "当前先用 `get_file` + `list_changes` + `read_note` 组合",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn list_change_log_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in ["`RepoNotInitialized { path }`", "`Db { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "The change-log API is the read-only log query",
        "detail, import",
        "optional `file_id`, `category`, `action`",
        "`occurred_at` bounds, `limit`, and `offset`",
        "ordered by",
        "`occurred_at DESC`",
        "remain parseable JSON",
        "This API has no write side effects",
        "must not mutate repository metadata",
        "create files, rename files, or probe user file contents",
        "Undo history",
        "belong to undo/redo capabilities",
        "Returns `CoreError::RepoNotInitialized { path }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "exact action string such as `imported`, `renamed`, or `external_modified`",
        "Lower `occurred_at` timestamp bound, inclusive.",
        "Upper `occurred_at` timestamp bound, exclusive.",
        "JSON detail payload that callers may parse for action-specific metadata.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
