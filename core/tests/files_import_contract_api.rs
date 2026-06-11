use area_matrix_core::{
    import_file, predict_category, ClassifyResult, CoreError, CoreResult, DuplicateStrategy,
    FileAvailabilityStatus, FileEntry, FileOrigin, ImportDestination, ImportOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-26-c4-06-contract-api.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-06-files-import.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const FILES_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-07-files-import.md");
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
        "# 4-3/task-26: C4-06 contract-api",
        "为 C4-06 files-import 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-06 files-import",
        "- S4-IOS-07 files-import",
        "- `import_file`",
        "- `predict_category`",
        "iOS Files provider 授权后的 file URL。",
        "导入预览和导入结果。",
        "Core 只处理授权后的可读文件。",
        "- `ICloudPlaceholder`",
        "- `PermissionDenied`",
        "- `DuplicateFile`",
        "- `Conflict`",
        "文件未下载/无权限时给出结构化状态。",
        "Replace 必须进入 S4-X-09。",
        "Cancel 不写 DB。",
        "Provider 后台下载管理不在 Core。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-07 | files-import | C4-06, C4-21 | Files import / replace confirm | 授权 URL、placeholder",
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
        "iOS document picker / SwiftUI file importer。",
        "security scoped access for selected files。",
        "Core transactional import API。",
        "Duplicate/name conflict detection。",
        "默认保存方式只复制到 repo，不移动源文件。",
        "同名冲突默认 `Keep both`，重复内容默认 `Skip duplicate`。",
        "Replace 必须进入 `S4-X-09` 二次确认。",
        "iCloud 下载失败能进入权限/恢复页。",
        "导入成功后资料库列表立即可见新文件。",
        "用户取消时不写入 repo，也不删除 Files app 中的源文件。",
    ] {
        assert_contains(FILES_PAGE, fragment);
    }

    for fragment in [
        "入口：`S4-WIN-05 import-flow`、`S4-LNX-05 import-flow`、`S4-IOS-07 files-import`",
        "iOS：不保证系统回收站，优先保留两份；Replace 默认隐藏，除非 Core 提供安全备份。",
        "Core conflict/import replacement API。",
        "Replace 前必定出现二次确认。",
        "iOS 不默认显示 Replace，除非有安全备份能力。",
    ] {
        assert_contains(REPLACE_PAGE, fragment);
    }

    for fragment in [
        "C4-06 files-import reuses this read-only preview surface",
        "iOS Files provider or document picker has granted access",
        "Provider browsing",
        "iCloud placeholder download orchestration",
        "C4-06 files-import reuses `StorageMode::Copied` import semantics",
        "authorized path plus",
        "does not open the document picker",
        "retain security-scoped bookmarks",
        "trigger provider downloads",
        "move source files",
        "perform C4-21 replace confirmation",
        "`S4-IOS-07` can derive its preview and result states",
        "structured `ICloudPlaceholder`, `PermissionDenied`,",
        "`DuplicateFile`, and `Conflict` errors",
        "Cancelled selections stay in the platform sheet",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }
}
