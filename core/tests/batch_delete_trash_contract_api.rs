use area_matrix_core::{
    batch_delete_to_trash, preview_batch_delete, BatchDeleteItemResult, BatchDeleteMode,
    BatchDeletePreviewItem, BatchDeletePreviewReport, BatchDeletePreviewStatus, BatchDeleteReport,
    BatchDeleteResultStatus, CoreError, CoreResult, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-09-batch-delete-trash.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const BATCH_DELETE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-13-batch-delete-confirm.md");
const UNDO_TOAST_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-10-undo-toast.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const BATCH_DELETE_RS: &str = include_str!("../src/batch_delete.rs");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn batch_delete_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_preview(
        _: fn(String, Vec<i64>, BatchDeleteMode) -> CoreResult<BatchDeletePreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(String, Vec<i64>, BatchDeleteMode, String) -> CoreResult<BatchDeleteReport>,
    ) {
    }

    assert_preview(preview_batch_delete);
    assert_apply(batch_delete_to_trash);

    let preview = BatchDeletePreviewReport {
        requested_file_count: 4,
        delete_mode: BatchDeleteMode::MoveToTrash,
        preview_token: "preview:batch-delete:42".to_owned(),
        trash_available: true,
        undo_available: true,
        will_trash_count: 2,
        index_only_count: 1,
        missing_count: 1,
        skipped_count: 0,
        blocked_count: 1,
        items: vec![
            BatchDeletePreviewItem {
                file_id: 10,
                current_path: Some("reports/a.pdf".to_owned()),
                current_name: Some("a.pdf".to_owned()),
                storage_mode: Some(StorageMode::Copied),
                delete_mode: BatchDeleteMode::MoveToTrash,
                will_move_to_trash: true,
                will_remove_index: false,
                status: BatchDeletePreviewStatus::WillMoveToTrash,
                reason: None,
            },
            BatchDeletePreviewItem {
                file_id: 11,
                current_path: Some("/external/b.pdf".to_owned()),
                current_name: Some("b.pdf".to_owned()),
                storage_mode: Some(StorageMode::Indexed),
                delete_mode: BatchDeleteMode::RemoveFromIndex,
                will_move_to_trash: false,
                will_remove_index: true,
                status: BatchDeletePreviewStatus::IndexOnly,
                reason: None,
            },
            BatchDeletePreviewItem {
                file_id: 12,
                current_path: None,
                current_name: Some("missing.pdf".to_owned()),
                storage_mode: None,
                delete_mode: BatchDeleteMode::RemoveFromIndex,
                will_move_to_trash: false,
                will_remove_index: true,
                status: BatchDeletePreviewStatus::Missing,
                reason: Some("file missing".to_owned()),
            },
        ],
        can_apply: true,
        apply_blocked_reason: None,
    };
    assert_eq!(preview.requested_file_count, 4);
    assert_eq!(preview.delete_mode, BatchDeleteMode::MoveToTrash);
    assert!(preview.trash_available);
    assert!(preview.undo_available);
    assert_eq!(preview.will_trash_count, 2);
    assert_eq!(preview.index_only_count, 1);
    assert_eq!(preview.missing_count, 1);
    assert_eq!(
        preview.items[0].status,
        BatchDeletePreviewStatus::WillMoveToTrash
    );
    assert_eq!(preview.items[1].status, BatchDeletePreviewStatus::IndexOnly);
    assert_eq!(preview.items[2].status, BatchDeletePreviewStatus::Missing);

    let report = BatchDeleteReport {
        requested_file_count: 4,
        delete_mode: BatchDeleteMode::MoveToTrash,
        moved_to_trash_count: 2,
        removed_from_index_count: 1,
        skipped_count: 0,
        failed_count: 1,
        item_results: vec![
            BatchDeleteItemResult {
                file_id: 10,
                final_path: Some("reports/a.pdf".to_owned()),
                status: BatchDeleteResultStatus::MovedToTrash,
                error: None,
            },
            BatchDeleteItemResult {
                file_id: 11,
                final_path: Some("/external/b.pdf".to_owned()),
                status: BatchDeleteResultStatus::RemovedFromIndex,
                error: None,
            },
            BatchDeleteItemResult {
                file_id: 13,
                final_path: None,
                status: BatchDeleteResultStatus::Failed,
                error: Some("permission denied".to_owned()),
            },
        ],
        affected_file_ids: vec![10, 11],
        undo_token: Some("undo:trash-delete:42".to_owned()),
    };
    assert_eq!(report.moved_to_trash_count, 2);
    assert_eq!(report.removed_from_index_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchDeleteResultStatus::MovedToTrash
    );
    assert_eq!(
        report.item_results[1].status,
        BatchDeleteResultStatus::RemovedFromIndex
    );
    assert_eq!(
        report.item_results[2].status,
        BatchDeleteResultStatus::Failed
    );
    assert_eq!(report.affected_file_ids, vec![10, 11]);
    assert_eq!(report.undo_token.as_deref(), Some("undo:trash-delete:42"));

    let documented_errors = [
        CoreError::permission_denied("trash unavailable"),
        CoreError::file_not_found("missing file"),
        CoreError::io("trash failed"),
        CoreError::db("metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn batch_delete_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        preview_batch_delete(String::new(), vec![1], BatchDeleteMode::MoveToTrash),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        preview_batch_delete(
            "/tmp/repo".to_owned(),
            Vec::new(),
            BatchDeleteMode::MoveToTrash
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_delete(
            "/tmp/repo".to_owned(),
            vec![0],
            BatchDeleteMode::MoveToTrash
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        batch_delete_to_trash(
            "/tmp/repo".to_owned(),
            vec![1, 1],
            BatchDeleteMode::RemoveFromIndex,
            "preview:batch-delete:42".to_owned()
        ),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn batch_delete_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-09 batch-delete-trash",
        "- S2-13 batch-delete-confirm",
        "- S2-10 undo-toast",
        "计划新增：`preview_batch_delete`、`batch_delete_to_trash`",
        "file_ids、delete mode。",
        "预览报告、执行报告、undo token。",
        "软删除 files。",
        "写 change log 和 undo action。",
        "Copy / Move 文件进入 Trash。",
        "Indexed / Missing 条目只移除索引。",
        "不提供永久删除。",
        "- `PermissionDenied`",
        "- `FileNotFound`",
        "- `Io`",
        "- `Db`",
        "Trash 不可用时禁用删除。",
        "失败项不被当作成功删除。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-13 | batch-delete-confirm | C2-09, C2-07 | preview + Trash delete",
        "| S2-10 | undo-toast | C2-07 | undo action | undo_actions",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "BatchDeletePreviewReport preview_batch_delete(",
        "sequence<i64> file_ids",
        "BatchDeleteMode delete_mode",
        "BatchDeleteReport batch_delete_to_trash(",
        "string preview_token",
        "dictionary BatchDeletePreviewReport",
        "string preview_token",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "BatchDeletePreviewReport preview_batch_delete(",
        "sequence<i64> file_ids",
        "BatchDeleteMode delete_mode",
        "BatchDeleteReport batch_delete_to_trash(",
        "dictionary BatchDeletePreviewItem",
        "StorageMode? storage_mode;",
        "BatchDeleteMode delete_mode;",
        "boolean will_move_to_trash;",
        "boolean will_remove_index;",
        "BatchDeletePreviewStatus status;",
        "dictionary BatchDeletePreviewReport",
        "boolean trash_available;",
        "boolean undo_available;",
        "i64 will_trash_count;",
        "i64 index_only_count;",
        "i64 missing_count;",
        "i64 blocked_count;",
        "boolean can_apply;",
        "dictionary BatchDeleteItemResult",
        "BatchDeleteResultStatus status;",
        "dictionary BatchDeleteReport",
        "i64 moved_to_trash_count;",
        "i64 removed_from_index_count;",
        "sequence<i64> affected_file_ids;",
        "string? undo_token;",
        "enum BatchDeleteMode { \"MoveToTrash\", \"RemoveFromIndex\" };",
        "enum BatchDeletePreviewStatus { \"WillMoveToTrash\", \"IndexOnly\", \"Missing\", \"Skipped\", \"Blocked\" };",
        "enum BatchDeleteResultStatus { \"MovedToTrash\", \"RemovedFromIndex\", \"Skipped\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `preview_batch_delete(repo, file_ids, delete_mode)` | storage | √ | PermissionDenied / FileNotFound / Io / Db |",
        "| `batch_delete_to_trash(repo, file_ids, delete_mode, preview_token)` | storage | √ | PermissionDenied / FileNotFound / Io / Db |",
        "### `preview_batch_delete(repoPath, fileIds, deleteMode) throws -> BatchDeletePreviewReport`",
        "### `batch_delete_to_trash(repoPath, fileIds, deleteMode, previewToken) throws -> BatchDeleteReport`",
        "`preview_token`",
        "`S2-13 batch-delete-confirm`",
        "`S2-10 undo-toast`",
        "`MoveToTrash`",
        "`RemoveFromIndex`",
        "`trash_available`",
        "`undo_available`",
        "`will_trash_count`",
        "`index_only_count`",
        "`missing_count`",
        "`affected_file_ids`",
        "不得提供永久删除替代",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn batch_delete_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "默认删除语义是移到 Trash，不提供永久删除。",
        "Index-only 条目可以仅从索引移除，不删除源文件。",
        "显示总选择数量和预计处理结果。",
        "Trash 不可用时禁用 `Move to Trash`",
        "Index-only 条目不会进入 Trash，只能 `Remove from index`。",
        "blocked 项默认 excluded",
        "操作成功后显示 Undo toast",
        "Undo 不可用时，必须显示确认 checkbox",
        "Cancel 不移动文件、不移除索引、不写 change_log。",
        "部分失败时能看到哪些失败以及为什么。",
    ] {
        assert_contains(BATCH_DELETE_PAGE, fragment);
    }

    for fragment in [
        "Moved 3 files to Trash.",
        "删除类 toast 文案必须是 `Moved ... to Trash`",
        "只有可撤销操作显示 `Undo`。",
        "Undo action 已过期、被后续写操作阻塞",
        "Undo 执行中禁用按钮并显示 `Undoing...`。",
        "Cmd+Z 与 toast Undo 指向同一个操作。",
    ] {
        assert_contains(UNDO_TOAST_PAGE, fragment);
    }

    for fragment in [
        "C2-09 batch delete to Trash contract",
        "BatchDeletePreviewReport",
        "BatchDeleteReport",
        "preview_batch_delete",
        "batch_delete_to_trash",
        "side-effect free",
        "must never delete, move, rename, overwrite",
        "not touch external source files",
    ] {
        assert_contains(BATCH_DELETE_RS, fragment);
    }

    for fragment in [
        "pub fn preview_batch_delete(",
        "batch_delete::preview_batch_delete",
        "pub fn batch_delete_to_trash(",
        "batch_delete::batch_delete_to_trash",
        "S2-13",
        "C2-09",
        "permanent deletion",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["PermissionDenied", "FileNotFound", "Io", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
