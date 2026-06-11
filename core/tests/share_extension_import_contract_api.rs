use area_matrix_core::{
    import_file, predict_category, ClassifyResult, CoreError, CoreResult, DuplicateStrategy,
    FileAvailabilityStatus, FileEntry, FileOrigin, ImportDestination, ImportOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-21-c4-05-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-05-share-extension-import.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const SHARE_PAGE: &str = include_str!(
    "../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-04-share-extension-import.md"
);
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

#[test]
fn share_extension_import_contract_exports_existing_import_and_preview_signatures() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_predict(predict_category);
    assert_import(import_file);
}

#[test]
fn share_extension_import_contract_exposes_staged_input_output_and_errors() {
    let queued_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: Some("Shared Article.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Ask,
    };
    assert_eq!(queued_options.mode, StorageMode::Copied);
    assert_eq!(queued_options.destination, ImportDestination::AutoClassify);
    assert_eq!(
        queued_options.override_filename.as_deref(),
        Some("Shared Article.pdf")
    );
    assert_eq!(queued_options.duplicate_strategy, DuplicateStrategy::Ask);

    let imported_share_item = FileEntry {
        id: 405,
        path: "inbox/Shared Article.pdf".to_owned(),
        original_name: "Safari Article.pdf".to_owned(),
        current_name: "Shared Article.pdf".to_owned(),
        category: "inbox".to_owned(),
        size_bytes: 16_384,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/app-group/share/staged/article.pdf".to_owned()),
        availability_status: FileAvailabilityStatus::Available,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_000,
    };
    assert_eq!(imported_share_item.storage_mode, StorageMode::Copied);
    assert_eq!(imported_share_item.origin, FileOrigin::Imported);
    assert_eq!(
        imported_share_item.source_path.as_deref(),
        Some("/app-group/share/staged/article.pdf")
    );
    assert_eq!(
        imported_share_item.availability_status,
        FileAvailabilityStatus::Available
    );

    let documented_errors = [
        CoreError::permission_denied("share staged file is unreadable"),
        CoreError::invalid_path("share staged path is invalid"),
        CoreError::io("share import filesystem failure"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn share_extension_import_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "# 4-3/task-21: C4-05 contract-api",
        "为 C4-05 share-extension-import 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-05 share-extension-import",
        "- S4-IOS-04 share-extension-import",
        "- `import_file`",
        "- `predict_category`",
        "Share Extension 提供的 staged file URL。",
        "导入结果或 deferred import ticket。",
        "导入成功后写 files/change_log。",
        "平台层把 share payload materialize 成 Core 可读文件。",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "- `Io`",
        "Share Extension 超时不留下成功假状态。",
        "deferred import 可被主 app 继续。",
        "不把外部 app payload 内容写入日志。",
        "后台批量分享导入优化后续处理。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-04 | share-extension-import | C4-05 | share staged import | Extension 超时/deferred import",
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
        "`PermissionDenied { path }`",
        "`InvalidPath { path }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn share_extension_import_documents_consumer_state_and_platform_boundaries() {
    for fragment in [
        "iOS Share Extension sheet",
        "Save queued",
        "Open AreaMatrix",
        "权限过期或没有 repo",
        "Cancel 返回来源 App / Share Sheet，不写入 repo。",
        "AreaMatrix will copy these items into the repository after you confirm.",
        "Import may continue in AreaMatrix.",
        "超过合理时间的操作转交主 App，扩展只显示排队结果。",
        "默认写入任务时标记为 `needsConflictReview`",
        "保存后主 App 能继续完成导入。",
        "Main App takeover 协议：queued、needs review、permission expired、completed。",
    ] {
        assert_contains(SHARE_PAGE, fragment);
    }

    for fragment in [
        "C4-05 share-extension-import reuses this read-only preview surface",
        "Share Extension has parsed an `NSExtensionItem`",
        "app-group queue persistence",
        "timeout handling stay in the platform layer",
        "C4-05 share-extension-import reuses `StorageMode::Copied` import semantics",
        "Core-readable app",
        "group staged file",
        "store the deferred",
        "import ticket",
        "log external app payload bytes",
        "platform-owned ticket records queued",
        "needs-review, or permission-expired takeover state",
        "calls this same Core import contract",
    ] {
        assert_contains(API_RS, fragment);
    }
}
