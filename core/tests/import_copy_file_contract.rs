use area_matrix_core::{
    import_file, CoreError, CoreResult, DuplicateStrategy, FileEntry, FileOrigin,
    ImportDestination, ImportOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
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
        "`import_file(repo_path, source_path, ImportOptions { mode: Copied, ... }) -> FileEntry`",
        "- `repo_path`",
        "- `source_path`",
        "- `ImportOptions.destination`",
        "- `ImportOptions.duplicate_strategy`",
        "- 新增 `FileEntry`。",
        "可在列表、详情、Tree 和 change log 中查到。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

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

    for fragment in [
        "| S1-17 | import-single-sheet | C1-05, C1-06, C1-07, C1-08 | `predict_category`, `import_file`",
        "| S1-18 | import-batch-sheet | C1-05, C1-06, C1-09 | `predict_category`, `import_file`",
        "| S1-20 | import-progress | C1-06, C1-07, C1-08 | `import_file`",
        "| S1-21 | import-result | C1-06, C1-13 | `import_file`, `list_changes`",
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

#[test]
fn import_copy_file_contract_documents_error_codes_and_side_effects() {
    let errors = [
        CoreError::InvalidPath,
        CoreError::DuplicateFile,
        CoreError::ICloudPlaceholder,
        CoreError::PermissionDenied,
        CoreError::Io,
        CoreError::Db,
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
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "复制源文件到 `.areamatrix/staging/`。",
        "计算 hash 后 rename 到最终目录。",
        "保留原文件不变。",
        "失败不会留下 active 半成品",
        "staging 可由 C1-16 清理",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "C1-06 defines the copied-file contract",
        "The original source file must remain unchanged.",
        "C1-07 and",
        "C1-08 own move and index semantics",
        "Failed imports must not leave active file rows",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn import_copy_file_contract_keeps_adjacent_modes_separate() {
    assert_ne!(StorageMode::Copied, StorageMode::Moved);
    assert_ne!(StorageMode::Copied, StorageMode::Indexed);

    assert_contains(CAPABILITY_SPEC, "批量队列进度由 UI 层编排。");
    assert_contains(
        CAPABILITY_SPEC,
        "大文件细粒度进度回调不在 Stage 1 Core API 内",
    );
    assert_contains(API_RS, "C1-07 and");
    assert_contains(API_RS, "C1-08 own move and index semantics");
}
