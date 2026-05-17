use area_matrix_core::{
    batch_move_to_category, preview_batch_move_to_category, BatchCategoryChangeItemResult,
    BatchCategoryChangeReport, BatchCategoryPreviewItem, BatchCategoryPreviewReport,
    BatchCategoryPreviewStatus, BatchCategoryResultStatus, CategoryDistributionItem, CoreError,
    CoreResult, FileEntry, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-08-batch-change-category.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const BATCH_CHANGE_CATEGORY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-12-batch-change-category.md");
const UNDO_TOAST_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-10-undo-toast.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const BATCH_CATEGORY_RS: &str = include_str!("../src/batch_category.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn batch_change_category_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_preview(
        _: fn(String, Vec<i64>, String, bool) -> CoreResult<BatchCategoryPreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(String, Vec<i64>, String, bool, String) -> CoreResult<BatchCategoryChangeReport>,
    ) {
    }

    assert_preview(preview_batch_move_to_category);
    assert_apply(batch_move_to_category);

    let preview = BatchCategoryPreviewReport {
        requested_file_count: 4,
        target_category: "finance".to_owned(),
        move_repo_owned_files: true,
        preview_token: "preview:batch-category:42".to_owned(),
        category_distribution: vec![
            CategoryDistributionItem {
                category: "reports".to_owned(),
                count: 2,
            },
            CategoryDistributionItem {
                category: "invoices".to_owned(),
                count: 2,
            },
        ],
        will_move_count: 1,
        metadata_only_count: 1,
        unchanged_count: 1,
        skipped_count: 1,
        blocked_count: 0,
        items: vec![
            BatchCategoryPreviewItem {
                file_id: 10,
                from_category: Some("reports".to_owned()),
                to_category: "finance".to_owned(),
                current_path: Some("reports/a.pdf".to_owned()),
                target_path: Some("finance/a.pdf".to_owned()),
                target_name: Some("a.pdf".to_owned()),
                storage_mode: Some(StorageMode::Copied),
                index_only: false,
                will_move_file: true,
                status: BatchCategoryPreviewStatus::WillMove,
                reason: None,
            },
            BatchCategoryPreviewItem {
                file_id: 11,
                from_category: Some("reports".to_owned()),
                to_category: "finance".to_owned(),
                current_path: Some("/external/b.pdf".to_owned()),
                target_path: Some("/external/b.pdf".to_owned()),
                target_name: Some("b.pdf".to_owned()),
                storage_mode: Some(StorageMode::Indexed),
                index_only: true,
                will_move_file: false,
                status: BatchCategoryPreviewStatus::MetadataOnly,
                reason: None,
            },
        ],
        can_apply: true,
        apply_blocked_reason: None,
    };
    assert_eq!(preview.requested_file_count, 4);
    assert_eq!(preview.category_distribution[0].count, 2);
    assert_eq!(
        preview.items[0].status,
        BatchCategoryPreviewStatus::WillMove
    );
    assert_eq!(
        preview.items[1].status,
        BatchCategoryPreviewStatus::MetadataOnly
    );
    assert!(preview.can_apply);

    let updated = FileEntry {
        id: 10,
        path: "finance/a.pdf".to_owned(),
        original_name: "a.pdf".to_owned(),
        current_name: "a.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 128,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/a.pdf".to_owned()),
        imported_at: 100,
        updated_at: 200,
    };
    let report = BatchCategoryChangeReport {
        requested_file_count: 4,
        target_category: "finance".to_owned(),
        moved_count: 1,
        metadata_only_count: 1,
        unchanged_count: 1,
        skipped_count: 1,
        failed_count: 1,
        item_results: vec![
            BatchCategoryChangeItemResult {
                file_id: 10,
                from_category: Some("reports".to_owned()),
                to_category: "finance".to_owned(),
                final_path: Some("finance/a.pdf".to_owned()),
                status: BatchCategoryResultStatus::Moved,
                error: None,
            },
            BatchCategoryChangeItemResult {
                file_id: 12,
                from_category: Some("invoices".to_owned()),
                to_category: "finance".to_owned(),
                final_path: None,
                status: BatchCategoryResultStatus::Failed,
                error: Some("permission denied".to_owned()),
            },
        ],
        updated_files: vec![updated],
        undo_token: Some("undo:move-files:42".to_owned()),
    };
    assert_eq!(report.moved_count, 1);
    assert_eq!(report.metadata_only_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchCategoryResultStatus::Moved
    );
    assert_eq!(
        report.item_results[1].status,
        BatchCategoryResultStatus::Failed
    );
    assert_eq!(report.updated_files[0].category, "finance");
    assert_eq!(report.undo_token.as_deref(), Some("undo:move-files:42"));

    let documented_errors = [
        CoreError::classify("missing category"),
        CoreError::conflict("stale preview"),
        CoreError::file_not_found("missing file"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("move failed"),
        CoreError::db("metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 6);
}

#[test]
fn batch_change_category_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        preview_batch_move_to_category(String::new(), vec![1], "finance".to_owned(), true),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        preview_batch_move_to_category(
            "/tmp/repo".to_owned(),
            Vec::new(),
            "finance".to_owned(),
            true
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_move_to_category("/tmp/repo".to_owned(), vec![0], "finance".to_owned(), true),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_move_to_category("/tmp/repo".to_owned(), vec![1], String::new(), true),
        Err(CoreError::Classify { .. })
    ));
    assert!(matches!(
        batch_move_to_category(
            "/tmp/repo".to_owned(),
            vec![1],
            "finance".to_owned(),
            true,
            String::new()
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert!(matches!(
        batch_move_to_category(
            "/tmp/repo".to_owned(),
            vec![1],
            "finance".to_owned(),
            true,
            "preview:batch-category:42".to_owned()
        ),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn batch_change_category_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-08 batch-change-category",
        "- S2-12 batch-change-category",
        "- S2-10 undo-toast",
        "`preview_batch_move_to_category(repo_path, file_ids, target_category, move_repo_owned_files) -> BatchCategoryPreviewReport`",
        "`batch_move_to_category(repo_path, file_ids, target_category, move_repo_owned_files, preview_token) -> BatchCategoryChangeReport`",
        "预览报告、执行报告、undo token。",
        "批量更新 `files.category/path`。",
        "写 change log 和 undo action。",
        "Index-only 不移动源文件。",
        "部分失败有摘要，不静默跳过。",
        "AI 规则批量重分类属于 C2-14/C2-15 或 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-12 | batch-change-category | C2-08, C2-07 | preview + batch move",
        "| S2-10 | undo-toast | C2-07 | undo action | undo_actions",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "BatchCategoryPreviewReport preview_batch_move_to_category(",
        "sequence<i64> file_ids",
        "string target_category",
        "boolean move_repo_owned_files",
        "BatchCategoryChangeReport batch_move_to_category(",
        "string preview_token",
        "dictionary CategoryDistributionItem",
        "dictionary BatchCategoryPreviewItem",
        "BatchCategoryPreviewStatus status;",
        "dictionary BatchCategoryPreviewReport",
        "sequence<CategoryDistributionItem> category_distribution;",
        "i64 will_move_count;",
        "i64 metadata_only_count;",
        "i64 unchanged_count;",
        "i64 skipped_count;",
        "i64 blocked_count;",
        "boolean can_apply;",
        "string? apply_blocked_reason;",
        "dictionary BatchCategoryChangeItemResult",
        "BatchCategoryResultStatus status;",
        "dictionary BatchCategoryChangeReport",
        "sequence<FileEntry> updated_files;",
        "string? undo_token;",
        "enum BatchCategoryPreviewStatus { \"WillMove\", \"MetadataOnly\", \"Unchanged\", \"Skipped\", \"Blocked\" };",
        "enum BatchCategoryResultStatus { \"Moved\", \"MetadataUpdated\", \"Unchanged\", \"Skipped\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `preview_batch_move_to_category(repo, file_ids, category, move)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "| `batch_move_to_category(repo, file_ids, category, move, preview_token)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "### `preview_batch_move_to_category(repoPath, fileIds, targetCategory, moveRepoOwnedFiles) throws -> BatchCategoryPreviewReport`",
        "### `batch_move_to_category(repoPath, fileIds, targetCategory, moveRepoOwnedFiles, previewToken) throws -> BatchCategoryChangeReport`",
        "`S2-12 batch-change-category`",
        "`S2-10 undo-toast`",
        "`preview_token`",
        "`category_distribution`",
        "`can_apply`",
        "`apply_blocked_reason`",
        "`updated_files`",
        "`undo_token`",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn batch_change_category_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "显示选中文件数量和示例。",
        "显示当前分类分布。",
        "选择是否移动文件到目标分类目录。",
        "预览会移动、只更新记录、无法处理的数量。",
        "应用后写入 change log 并接入 Undo。",
        "`Preview` 是次按钮，用于刷新并展开完整 dry-run 结果，不写任何数据。",
        "Apply 必须绑定最近一次 dry-run 结果",
        "Index-only 文件不能移动源文件，只更新记录。",
        "部分失败时成功项保留，失败项显示原因；可撤销项进入 Undo stack。",
    ] {
        assert_contains(BATCH_CHANGE_CATEGORY_PAGE, fragment);
    }

    for fragment in [
        "只有可撤销操作显示 `Undo`。",
        "Undo action 已过期、被后续写操作阻塞",
        "Undo 执行中禁用按钮并显示 `Undoing...`。",
        "Cmd+Z 与 toast Undo 指向同一个操作。",
    ] {
        assert_contains(UNDO_TOAST_PAGE, fragment);
    }

    for fragment in [
        "C2-08 batch category change types and entry points",
        "BatchCategoryPreviewReport",
        "BatchCategoryChangeReport",
        "preview_batch_move_to_category",
        "batch_move_to_category",
        "side-effect free",
        "build_batch_category_plan",
        "apply_batch_category_plan",
        "stale batch category preview",
    ] {
        assert_contains(BATCH_CATEGORY_RS, fragment);
    }

    for fragment in [
        "pub fn preview_batch_move_to_category(",
        "batch_category::preview_batch_move_to_category",
        "pub fn batch_move_to_category(",
        "batch_category::batch_move_to_category",
        "S2-12",
        "C2-08",
        "not create new categories",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in [
        "Classify",
        "Conflict",
        "FileNotFound",
        "PermissionDenied",
        "Io",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
