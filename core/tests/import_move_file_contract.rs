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
fn import_move_file_contract_exports_callable_signature() {
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_import(import_file);
}

#[test]
fn import_move_file_contract_exposes_documented_inputs() {
    let moved_auto_classify = ImportOptions {
        mode: StorageMode::Moved,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some("invoice.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
        content_locale: area_matrix_core::ContentLocale::En,
    };
    let moved_selected_directory = ImportOptions {
        mode: StorageMode::Moved,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Ask,
        content_locale: area_matrix_core::ContentLocale::En,
    };

    assert_eq!(moved_auto_classify.mode, StorageMode::Moved);
    assert_eq!(
        moved_auto_classify.destination,
        ImportDestination::AutoClassify
    );
    assert_eq!(
        moved_selected_directory.target_directory.as_deref(),
        Some("finance/2026")
    );
    assert_eq!(
        moved_auto_classify.override_category.as_deref(),
        Some("finance")
    );
}

#[test]
fn import_move_file_contract_exposes_documented_outputs() {
    let entry = FileEntry {
        id: 7,
        path: "finance/invoice.pdf".to_owned(),
        original_name: "invoice.pdf".to_owned(),
        current_name: "invoice.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 512,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Moved,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/source/invoice.pdf".to_owned()),
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 10,
        updated_at: 10,
    };

    assert_eq!(entry.storage_mode, StorageMode::Moved);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(
        entry.source_path.as_deref(),
        Some("/tmp/source/invoice.pdf")
    );
    assert_eq!(entry.path, "finance/invoice.pdf");
}

#[test]
fn import_move_file_contract_docs_api_udl_and_control_map_stay_aligned() {
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
        "string? source_path;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `import_file(repo, src, options)` | storage |",
        "`ImportOptions.destination` 语义",
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath`",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn import_move_file_contract_documents_error_codes_and_side_effects() {
    let errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::DuplicateFile {
            existing_path: "finance/existing.pdf".to_owned(),
        },
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
    ];

    assert_eq!(errors.len(), 5);

    for error_name in [
        "InvalidPath",
        "DuplicateFile",
        "PermissionDenied",
        "Io",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "moved-file import defines the moved-file contract",
        "files.storage_mode = Moved",
        "files.source_path",
        "change_log.action =",
        "failed moved",
        "must not cross unconfirmed user directory",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn import_move_file_contract_keeps_adjacent_modes_separate() {
    assert_ne!(StorageMode::Moved, StorageMode::Copied);
    assert_ne!(StorageMode::Moved, StorageMode::Indexed);

    assert_contains(API_RS, "indexed-file import owns index-only semantics");
}
