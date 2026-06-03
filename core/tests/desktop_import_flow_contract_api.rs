use area_matrix_core::{
    import_file, predict_category, ClassifyResult, CoreError, CoreResult, DuplicateStrategy,
    FileAvailabilityStatus, FileEntry, FileOrigin, ImportDestination, ImportOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-61-c4-13-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-13-desktop-import-flow.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const WINDOWS_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-05-import-flow.md");
const LINUX_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-05-import-flow.md");
const REPLACE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-09-replace-confirm.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
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

    assert_predict(predict_category);
    assert_import(import_file);
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
    assert_eq!(copy_options.destination, ImportDestination::SelectedDirectory);
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
        "# 4-3/task-61: C4-13 contract-api",
        "为 C4-13 desktop-import-flow 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-13 desktop-import-flow",
        "- S4-WIN-05 import-flow",
        "- S4-LNX-05 import-flow",
        "- `predict_category`",
        "- `import_file`",
        "平台 file picker 返回路径和 ImportOptions。",
        "导入结果和冲突状态。",
        "Copy/Move/Index 按配置执行。",
        "- `DuplicateFile`",
        "- `Conflict`",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "Replace 必须走 S4-X-09。",
        "平台 Trash 不可用时禁止 destructive 路径。",
        "导入失败不显示成功状态。",
        "Explorer/Nautilus shell integration 后续再拆。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-05 | import-flow | C4-13, C4-21 | desktop import / replace | Trash 不可用则禁用危险动作",
        "| S4-LNX-05 | import-flow | C4-13, C4-21 | desktop import / replace | Trash 能力差异",
        "| S4-X-09 | replace-confirm | C4-16, C4-21 | replace confirm | Trash/备份，禁止永久删除",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
        "string? target_directory;",
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
        "Windows file/folder picker。",
        "Windows drag and drop。",
        "Core transactional import API。",
        "Duplicate and name conflict detection。",
        "Move preflight：源文件可读、源位置可删除/移动、目标可写、staging 可用。",
        "Windows Recycle Bin integration for Replace。",
        "Recycle Bin availability and move-to-bin preflight。",
        "同名不同内容默认保留两份。",
        "Replace 和 Move 都有额外确认；Recycle Bin 不可用或 move-to-bin 失败时 Replace 禁用",
        "成功导入后文件系统和 DB 都可见。",
    ] {
        assert_contains(WINDOWS_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "Linux file/folder picker 或 xdg-desktop-portal。",
        "Drag and drop。",
        "Core transactional import API。",
        "Duplicate/conflict detection。",
        "Move preflight：源文件可读、源目录可 unlink/rename、目标可写、staging 可用、same-mount / cross-mount 判断。",
        "freedesktop Trash 能力检测。",
        "Move-to-trash preflight。",
        "POSIX permission detection。",
        "同名冲突默认保留两份。",
        "Trash 不可用或检测失败：Replace 不能假装可逆，默认禁用",
    ] {
        assert_contains(LINUX_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "入口：`S4-WIN-05 import-flow`、`S4-LNX-05 import-flow`",
        "Replace 前必定出现二次确认。",
        "Trash/Recycle Bin Unknown：按不可用处理，禁用 Replace",
        "Stage 4 默认禁用不可逆 Replace",
        "不可逆 Replace 在 Stage 4 不可被执行。",
    ] {
        assert_contains(REPLACE_PAGE, fragment);
    }

    for fragment in [
        "C4-13 desktop-import-flow reuses this read-only preview surface",
        "Windows and Linux import dialogs",
        "Directory expansion, platform permission preflight",
        "Trash/Recycle Bin capability",
        "multi-item progress stay in the desktop shell",
        "`S4-WIN-05` and `S4-LNX-05` can show as suggested category state",
        "C4-13 desktop-import-flow reuses this same import contract",
        "Desktop shells pass the picker or drop source path plus",
        "folder recursion, batching, drag-and-drop",
        "Trash/Recycle Bin availability checks remain outside Core",
        "`StorageMode::Copied` is the safe default",
        "`StorageMode::Moved` keeps the Stage 1 transactional move contract",
        "`DuplicateStrategy::Overwrite` is only valid after the separate C4-21",
        "this API does not perform that confirmation",
        "or add a desktop-only replace capability",
        "must surface an error instead of a success state",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }

    for fragment in [
        "C4-13 desktop-import-flow reuses predict_category for read-only",
        "does not expand folders",
        "detect Trash/Recycle Bin support",
        "C4-13 desktop-import-flow reuses import_file for the final committed",
        "Desktop shells derive result state from FileEntry,",
        "Replace confirmation belongs to C4-21/S4-X-09",
        "does not add a desktop-only replace or platform Trash API",
        "Overwrite is the committed strategy token after that confirmation",
    ] {
        assert_contains_normalized(UDL, fragment);
    }
}
