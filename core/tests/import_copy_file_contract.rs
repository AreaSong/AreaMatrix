use area_matrix_core::{
    import_file, CoreError, CoreResult, DuplicateStrategy, FileEntry, FileOrigin,
    ImportDestination, ImportOptions, StorageMode,
};
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
fn import_copy_file_contract_exports_callable_signature() {
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_import(import_file);
}

#[test]
fn import_copy_file_contract_exposes_documented_inputs() {
    let auto_classify = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some("invoice.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    };
    let selected_directory = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Ask,
    };
    let category = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::Category,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::KeepBoth,
    };

    assert_eq!(auto_classify.mode, StorageMode::Copied);
    assert_eq!(auto_classify.destination, ImportDestination::AutoClassify);
    assert_eq!(
        selected_directory.target_directory.as_deref(),
        Some("finance/2026")
    );
    assert_eq!(category.override_category.as_deref(), Some("docs"));
}

#[test]
fn import_copy_file_contract_exposes_documented_outputs() {
    let entry = FileEntry {
        id: 42,
        path: "finance/invoice.pdf".to_owned(),
        original_name: "invoice.pdf".to_owned(),
        current_name: "invoice.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 128,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/source/invoice.pdf".to_owned()),
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 10,
        updated_at: 10,
    };

    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(
        entry.source_path.as_deref(),
        Some("/tmp/source/invoice.pdf")
    );
    assert_eq!(entry.path, "finance/invoice.pdf");
}

#[test]
fn import_copy_file_contract_docs_udl_and_control_map_stay_aligned() {
    for fragment in [
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `import_file(repo, src, options)` | storage |",
        "`ImportOptions.destination` 语义",
        "| `AutoClassify` | `override_category` 可选 |",
        "| `SelectedDirectory` | `target_directory` 必填 |",
        "| `Category` | `override_category` 必填 |",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn import_copy_file_contract_documents_error_codes_and_side_effects() {
    let errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::DuplicateFile {
            existing_path: "finance/existing.pdf".to_owned(),
        },
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
    ];

    assert_eq!(errors.len(), 6);

    for error_name in [
        "InvalidPath",
        "DuplicateFile",
        "ICloudPlaceholder",
        "PermissionDenied",
        "Io",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "copied-file import defines the copied-file contract",
        "The original source file must remain unchanged.",
        "moved-file import defines the moved-file contract",
        "indexed-file import owns index-only semantics",
        "Failed imports must not leave active file rows",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn import_copy_file_contract_keeps_adjacent_modes_separate() {
    assert_ne!(StorageMode::Copied, StorageMode::Moved);
    assert_ne!(StorageMode::Copied, StorageMode::Indexed);

    assert_contains(API_RS, "moved-file import defines the moved-file contract");
    assert_contains(API_RS, "indexed-file import owns index-only semantics");
}
