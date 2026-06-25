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

#[test]
fn camera_import_contract_exports_existing_import_and_preview_signatures() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_predict(predict_category);
    assert_import(import_file);
}

#[test]
fn camera_import_contract_exposes_mobile_copy_inputs_outputs_and_errors() {
    let camera_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: Some("Photo 2026-04-29 1130.jpg".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    };
    assert_eq!(camera_options.mode, StorageMode::Copied);
    assert_eq!(camera_options.destination, ImportDestination::AutoClassify);
    assert_eq!(
        camera_options.override_filename.as_deref(),
        Some("Photo 2026-04-29 1130.jpg")
    );
    assert_eq!(camera_options.duplicate_strategy, DuplicateStrategy::Skip);

    let imported_photo = FileEntry {
        id: 404,
        path: "docs/Photo 2026-04-29 1130.jpg".to_owned(),
        original_name: "Photo 2026-04-29 1130.jpg".to_owned(),
        current_name: "Photo 2026-04-29 1130.jpg".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 2_048,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/areamatrix-camera/photo.jpg".to_owned()),
        availability_status: FileAvailabilityStatus::Available,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_000,
    };
    assert_eq!(imported_photo.storage_mode, StorageMode::Copied);
    assert_eq!(imported_photo.origin, FileOrigin::Imported);
    assert_eq!(
        imported_photo.source_path.as_deref(),
        Some("/tmp/areamatrix-camera/photo.jpg")
    );
    assert_eq!(
        imported_photo.availability_status,
        FileAvailabilityStatus::Available
    );

    let documented_errors = [
        CoreError::permission_denied("camera temp file is unreadable"),
        CoreError::invalid_path("camera temp path is invalid"),
        CoreError::io("camera import filesystem failure"),
        CoreError::db("camera import metadata failure"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn camera_import_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
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
        "`PermissionDenied { path }`",
        "`InvalidPath { path }`",
        "`Io { message }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn camera_import_documents_consumer_state_and_platform_boundaries() {
    for fragment in [
        "camera import reuses this read-only preview surface",
        "temporary-file lifetime management remain outside Core",
        "camera import reuses `StorageMode::Copied` import semantics",
        "platform-saved temporary photo path",
        "does not request camera",
        "or clean up the final repository file",
        "without adding a camera-specific Core API",
    ] {
        assert_contains(API_RS, fragment);
    }
}
