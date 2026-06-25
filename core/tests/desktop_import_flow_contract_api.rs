use area_matrix_core::{
    import_file, import_file_with_result, predict_category, ClassifyResult, CoreError, CoreResult,
    DuplicateStrategy, FileAvailabilityStatus, FileEntry, FileOrigin, ImportDestination,
    ImportOptions, ImportResult, ImportSourceRemovalStatus, StorageMode,
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
        "expected text to contain `{needle}`"
    );
}

fn assert_contains_normalized(haystack: &str, needle: &str) {
    let normalized_haystack = normalize_text(haystack);
    let normalized_needle = needle.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        normalized_haystack.contains(&normalized_needle),
        "expected normalized text to contain `{needle}`"
    );
}

fn normalize_text(text: &str) -> String {
    text.lines()
        .map(|line| {
            line.trim_start()
                .strip_prefix("///")
                .or_else(|| line.trim_start().strip_prefix("//"))
                .unwrap_or(line.trim_start())
                .trim_start()
        })
        .collect::<Vec<_>>()
        .join(" ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn desktop_import_flow_contract_exports_existing_import_and_preview_signatures() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}
    fn assert_import_result(_: fn(String, String, ImportOptions) -> CoreResult<ImportResult>) {}

    assert_predict(predict_category);
    assert_import(import_file);
    assert_import_result(import_file_with_result);
}

#[test]
fn desktop_import_flow_contract_exposes_page_ready_inputs_outputs_and_errors() {
    let copy_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("docs/projects".to_owned()),
        override_category: None,
        override_filename: Some("Desktop Report.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::KeepBoth,
    };
    assert_eq!(copy_options.mode, StorageMode::Copied);
    assert_eq!(
        copy_options.destination,
        ImportDestination::SelectedDirectory
    );
    assert_eq!(
        copy_options.target_directory.as_deref(),
        Some("docs/projects")
    );
    assert_eq!(
        copy_options.override_filename.as_deref(),
        Some("Desktop Report.pdf")
    );
    assert_eq!(copy_options.duplicate_strategy, DuplicateStrategy::KeepBoth);

    let moved_options = ImportOptions {
        mode: StorageMode::Moved,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Ask,
    };
    assert_eq!(moved_options.mode, StorageMode::Moved);
    assert_eq!(moved_options.duplicate_strategy, DuplicateStrategy::Ask);

    let imported_file = FileEntry {
        id: 413,
        path: "docs/projects/Desktop Report.pdf".to_owned(),
        original_name: "Report.pdf".to_owned(),
        current_name: "Desktop Report.pdf".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 65_536,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/home/user/Downloads/Report.pdf".to_owned()),
        availability_status: FileAvailabilityStatus::Available,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_000,
    };
    assert_eq!(imported_file.storage_mode, StorageMode::Copied);
    assert_eq!(imported_file.origin, FileOrigin::Imported);
    assert_eq!(
        imported_file.source_path.as_deref(),
        Some("/home/user/Downloads/Report.pdf")
    );
    assert_eq!(
        imported_file.availability_status,
        FileAvailabilityStatus::Available
    );
    let import_result = ImportResult {
        entry: imported_file.clone(),
        source_removal_status: ImportSourceRemovalStatus::Retained,
        source_removal_failure: Some("permission denied".to_owned()),
    };
    assert_eq!(import_result.entry, imported_file);
    assert_eq!(
        import_result.source_removal_status,
        ImportSourceRemovalStatus::Retained
    );
    assert_eq!(
        import_result.source_removal_failure.as_deref(),
        Some("permission denied")
    );

    let documented_errors = [
        CoreError::DuplicateFile {
            existing_path: "docs/projects/Report.pdf".to_owned(),
        },
        CoreError::conflict("docs/projects/Report.pdf"),
        CoreError::permission_denied("/home/user/Downloads/Report.pdf"),
        CoreError::invalid_path("/home/user/Downloads/Report.pdf"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn desktop_import_flow_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "FileEntry import_file(",
        "ImportResult import_file_with_result(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
        "string? target_directory;",
        "string? override_category;",
        "string? override_filename;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "dictionary ImportResult",
        "FileEntry entry;",
        "ImportSourceRemovalStatus source_removal_status;",
        "string? source_removal_failure;",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "FileAvailabilityStatus availability_status;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum ImportSourceRemovalStatus { \"NotRequested\", \"Removed\", \"Retained\" };",
        "enum ImportDestination { \"AutoClassify\", \"SelectedDirectory\", \"Category\" };",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |",
        "| `import_file_with_result(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |",
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `PermissionDenied` / `Internal`。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`DuplicateFile { existing_path }`",
        "`Conflict { path }`",
        "`PermissionDenied { path }`",
        "`InvalidPath { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn desktop_import_flow_documents_consumer_state_without_adjacent_capabilities() {
    for fragment in [
        "desktop import flow reuses this read-only preview surface",
        "Windows and Linux import dialogs",
        "Directory expansion, platform permission preflight",
        "Trash/Recycle Bin capability",
        "multi-item progress stay in the desktop shell",
        "`Windows import surface` and `Linux import surface` can show as suggested category state",
        "desktop import flow keeps this same import contract available",
        "should use [`import_file_with_result`]",
        "Imports one source file and returns desktop-ready result state.",
        "desktop import flow uses this wrapper for `Windows import surface` and `Linux import surface`",
        "ImportSourceRemovalStatus::Retained",
        "Imported, original retained",
        "Desktop shells pass the picker or drop source path plus",
        "folder recursion, batching, drag-and-drop",
        "Trash/Recycle Bin availability checks remain outside Core",
        "`StorageMode::Copied` is the safe default",
        "`StorageMode::Moved` first commits",
        "`DuplicateStrategy::Overwrite` is only valid after the separate replace confirmation",
        "this API does not perform that confirmation",
        "or add a desktop-only replace capability",
        "must surface an error instead of a success state",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }

    for fragment in [
        "desktop import flow reuses predict_category for read-only",
        "does not expand folders",
        "detect Trash/Recycle Bin support",
        "desktop import flow uses import_file_with_result for the final",
        "backwards-compatible FileEntry entry point",
        "source removal status",
        "Imported, original retained",
        "Replace confirmation belongs to replace confirmation",
        "does not add a desktop-only replace or platform Trash API",
        "Overwrite is the committed strategy token after that confirmation",
    ] {
        assert_contains_normalized(UDL, fragment);
    }
}
