use area_matrix_core::{get_file, CoreError, CoreResult, FileEntry, FileOrigin, StorageMode};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn get_file_detail_contract_api_exposes_callable_signature_input_and_output() {
    fn assert_get_file(_: fn(String, i64) -> CoreResult<FileEntry>) {}
    assert_get_file(get_file);

    let file_id = 42;
    let entry = FileEntry {
        id: file_id,
        path: "finance/report.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 2048,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/report.pdf".to_owned()),
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 100,
        updated_at: 110,
    };

    assert_eq!(entry.id, file_id);
    assert_eq!(entry.path, "finance/report.pdf");
    assert_eq!(entry.current_name, "report.pdf");
    assert_eq!(entry.category, "finance");

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn get_file_detail_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "FileEntry get_file(string repo_path, i64 file_id);",
        "dictionary FileEntry",
        "i64 id;",
        "string path;",
        "string current_name;",
        "string category;",
        "i64 size_bytes;",
        "string hash_sha256;",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "i64 imported_at;",
        "i64 updated_at;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `get_file(repoPath, fileId) throws -> FileEntry`",
        "文件不存在抛 `FileNotFound`。",
        "下列函数轻量，可同步调",
        "- `get_file`",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn get_file_detail_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in [
        "`FileNotFound { path }`",
        "`RepoNotInitialized { path }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "The file-detail API is the read-only detail query",
        "The caller supplies a repository path and stable `file_id`",
        "returns exactly one active [`FileEntry`]",
        "must not infer",
        "metadata from the filesystem path in the UI layer",
        "This API has no write side effects.",
        "must not create, delete, move",
        "rename, or overwrite user files",
        "File preview, Quick Look, OCR metadata",
        "change-log aggregation, and note aggregation belong to adjacent capabilities",
        "Returns `CoreError::RepoNotInitialized { path }`",
        "`CoreError::FileNotFound { path }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "详情聚合 DTO",
        "当前先用 `get_file` + `list_changes` + `read_note` 组合",
    ] {
        assert_contains(CORE_API, fragment);
    }
}
