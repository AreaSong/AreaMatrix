use area_matrix_core::{
    import_file, CoreError, CoreResult, DuplicateStrategy, FileEntry, FileOrigin,
    ImportDestination, ImportOptions, StorageMode,
};
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
fn import_index_file_contract_exports_callable_signature() {
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_import(import_file);
}

#[test]
fn import_index_file_contract_exposes_documented_inputs() {
    let indexed_auto_classify = ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some("invoice.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    };
    let indexed_selected_directory = ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("external/references".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Ask,
    };
    let indexed_category = ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::Category,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::KeepBoth,
    };

    assert_eq!(indexed_auto_classify.mode, StorageMode::Indexed);
    assert_eq!(
        indexed_auto_classify.destination,
        ImportDestination::AutoClassify
    );
    assert_eq!(
        indexed_selected_directory.target_directory.as_deref(),
        Some("external/references")
    );
    assert_eq!(indexed_category.override_category.as_deref(), Some("docs"));
}

#[test]
fn import_index_file_contract_exposes_documented_outputs() {
    let entry = FileEntry {
        id: 8,
        path: "/external/source/invoice.pdf".to_owned(),
        original_name: "invoice.pdf".to_owned(),
        current_name: "invoice.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 256,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Indexed,
        origin: FileOrigin::Imported,
        source_path: Some("/external/source/invoice.pdf".to_owned()),
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 10,
        updated_at: 10,
    };

    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(
        entry.source_path.as_deref(),
        Some("/external/source/invoice.pdf")
    );
    assert_eq!(entry.path, "/external/source/invoice.pdf");
}

#[test]
fn import_index_file_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "string? source_path;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `import_file(repo, src, options)` | storage |",
        "`ImportOptions.destination` 语义",
        "导入进度 / 队列语义",
        "copied-file import, moved-file import, indexed-file import",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn import_index_file_contract_documents_error_codes_and_side_effects() {
    let errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::file_not_found("missing file"),
        CoreError::permission_denied("permission denied"),
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::db("database error"),
    ];

    assert_eq!(errors.len(), 5);

    for error_name in [
        "InvalidPath",
        "FileNotFound",
        "PermissionDenied",
        "ICloudPlaceholder",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "indexed-file import defines the indexed-file contract",
        "`mode` is `StorageMode::Indexed`",
        "must not copy, move, rename, or",
        "must not create",
        "final repository-owned file copy",
        "files.storage_mode = Indexed",
        "preserves `files.source_path`",
        "change_log.action = imported",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn import_index_file_contract_keeps_adjacent_modes_separate() {
    assert_ne!(StorageMode::Indexed, StorageMode::Copied);
    assert_ne!(StorageMode::Indexed, StorageMode::Moved);

    assert_contains(
        API_RS,
        "copied-file import defines the copied-file contract",
    );
    assert_contains(API_RS, "moved-file import defines the moved-file contract");
    assert_contains(
        API_RS,
        "indexed-file import defines the indexed-file contract",
    );
}
