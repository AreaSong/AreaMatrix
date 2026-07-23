use area_matrix_core::{
    import_file, predict_category, ClassifyResult, CoreError, CoreResult, DuplicateStrategy,
    FileAvailabilityStatus, FileEntry, FileOrigin, ImportDestination, ImportOptions, StorageMode,
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
fn files_import_contract_exports_existing_import_and_preview_signatures() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_predict(predict_category);
    assert_import(import_file);
}

#[test]
fn files_import_contract_exposes_authorized_copy_inputs_outputs_and_errors() {
    let files_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: Some("Quarterly Report.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::KeepBoth,
        content_locale: area_matrix_core::ContentLocale::En,
    };
    assert_eq!(files_options.mode, StorageMode::Copied);
    assert_eq!(files_options.destination, ImportDestination::AutoClassify);
    assert_eq!(files_options.override_category.as_deref(), Some("docs"));
    assert_eq!(
        files_options.override_filename.as_deref(),
        Some("Quarterly Report.pdf")
    );
    assert_eq!(
        files_options.duplicate_strategy,
        DuplicateStrategy::KeepBoth
    );

    let imported_file = FileEntry {
        id: 406,
        path: "docs/Quarterly Report.pdf".to_owned(),
        original_name: "Report.pdf".to_owned(),
        current_name: "Quarterly Report.pdf".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 32_768,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some(
            "/private/var/mobile/Containers/Shared/AppGroup/files/Report.pdf".to_owned(),
        ),
        availability_status: FileAvailabilityStatus::Available,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_000,
    };
    assert_eq!(imported_file.storage_mode, StorageMode::Copied);
    assert_eq!(imported_file.origin, FileOrigin::Imported);
    assert_eq!(
        imported_file.source_path.as_deref(),
        Some("/private/var/mobile/Containers/Shared/AppGroup/files/Report.pdf")
    );
    assert_eq!(
        imported_file.availability_status,
        FileAvailabilityStatus::Available
    );

    let documented_errors = [
        CoreError::icloud_placeholder("/Files/Report.pdf"),
        CoreError::permission_denied("/Files/Report.pdf"),
        CoreError::DuplicateFile {
            existing_path: "docs/Report.pdf".to_owned(),
        },
        CoreError::conflict("docs/Report.pdf"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn files_import_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
        "string? override_category;",
        "string? override_filename;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "FileAvailabilityStatus availability_status;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum ImportDestination { \"AutoClassify\", \"SelectedDirectory\", \"Category\" };",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |",
        "catch CoreError.PermissionDenied(let p)",
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `PermissionDenied` / `Internal`。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`ICloudPlaceholder { path }`",
        "`PermissionDenied { path }`",
        "`DuplicateFile { existing_path }`",
        "`Conflict { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn files_import_documents_consumer_state_and_platform_boundaries() {
    for fragment in [
        "files import reuses this read-only preview surface",
        "iOS Files provider or document picker has granted access",
        "Provider browsing",
        "iCloud placeholder download orchestration",
        "files import reuses `StorageMode::Copied` import semantics",
        "authorized path plus",
        "does not open the document picker",
        "retain security-scoped bookmarks",
        "trigger provider downloads",
        "move source files",
        "perform replace confirmation",
        "`iOS files import surface` can derive its preview and result states",
        "structured `ICloudPlaceholder`, `PermissionDenied`,",
        "`DuplicateFile`, and `Conflict` errors",
        "Cancelled selections stay in the platform sheet",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }
}
