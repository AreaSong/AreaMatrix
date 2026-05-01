use area_matrix_core::{
    import_file, CoreError, CoreResult, DuplicateStrategy, FileEntry, FileOrigin,
    ImportDestination, ImportOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md");
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
    };
    let moved_selected_directory = ImportOptions {
        mode: StorageMode::Moved,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Ask,
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
        "`import_file(repo_path, source_path, ImportOptions { mode: Moved, ... }) -> FileEntry`",
        "- `repo_path`",
        "- `source_path`",
        "- `ImportOptions`",
        "- 新增 `FileEntry`。",
        "- 原路径被安全移入资料库最终位置。",
        "- `files.storage_mode = Moved`。",
        "- `files.source_path` 记录原始来源。",
        "- `change_log.action = imported`。",
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

    for fragment in [
        "| S1-17 | import-single-sheet | C1-05, C1-06, C1-07, C1-08 | `predict_category`, `import_file`",
        "| S1-20 | import-progress | C1-06, C1-07, C1-08 | `import_file`",
        "| S1-26 | settings-general | C1-04, C1-07 | `load_config`, `update_config`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

#[test]
fn import_move_file_contract_documents_error_codes_and_side_effects() {
    let errors = [
        CoreError::InvalidPath,
        CoreError::DuplicateFile,
        CoreError::PermissionDenied,
        CoreError::Io,
        CoreError::Db,
    ];

    assert_eq!(errors.len(), 5);

    for error_name in [
        "InvalidPath",
        "DuplicateFile",
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
        "源文件移动到 staging，再原子 rename 到最终目录。",
        "不跨越用户未确认的目录边界。",
        "成功后原路径不存在，最终路径存在。",
        "移动失败必须保留源文件或可恢复 staging，不丢数据。",
        "与 Copy 模式共享重复检测和同名冲突处理。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "C1-07 defines the moved-file contract",
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

    assert_contains(CAPABILITY_SPEC, "多文件 move 队列由 Phase 2 UI 任务处理。");
    assert_contains(CAPABILITY_SPEC, "从外部云盘占位符自动下载由 macOS 层处理。");
    assert_contains(API_RS, "C1-08 owns index-only semantics");
}
