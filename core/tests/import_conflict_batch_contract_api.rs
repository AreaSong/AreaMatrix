use area_matrix_core::{
    apply_import_conflict_batch, preview_import_conflict_batch, CoreError, CoreResult,
    ImportConflictBatchApplyReport, ImportConflictBatchApplyRequest,
    ImportConflictBatchConflictType, ImportConflictBatchItemResult, ImportConflictBatchPreviewItem,
    ImportConflictBatchPreviewReport, ImportConflictBatchPreviewRequest,
    ImportConflictBatchPreviewStatus, ImportConflictBatchResultStatus, ImportConflictBatchStrategy,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-1-stage2-experience/task-81-c2-17-contract-api.md");
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-17-import-conflict-batch.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const S2_21_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-21-import-conflict-batch.md");
const DEDUP_CONFLICT: &str = include_str!("../../docs/ux/dedup-conflict.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_RS: &str = include_str!("../src/import_conflict_batch.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn preview_request() -> ImportConflictBatchPreviewRequest {
    ImportConflictBatchPreviewRequest {
        import_session_id: "session-42".to_owned(),
        conflict_ids: vec!["dup-1".to_owned(), "name-1".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: true,
    }
}

fn apply_request(replace_confirmed: bool) -> ImportConflictBatchApplyRequest {
    ImportConflictBatchApplyRequest {
        import_session_id: "session-42".to_owned(),
        conflict_ids: vec!["dup-1".to_owned(), "name-1".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::Replace,
        apply_to_all_similar_conflicts: true,
        replace_confirmed,
    }
}

#[test]
fn import_conflict_batch_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_preview(
        _: fn(
            String,
            ImportConflictBatchPreviewRequest,
        ) -> CoreResult<ImportConflictBatchPreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(
            String,
            ImportConflictBatchApplyRequest,
            String,
        ) -> CoreResult<ImportConflictBatchApplyReport>,
    ) {
    }

    assert_preview(preview_import_conflict_batch);
    assert_apply(apply_import_conflict_batch);

    let preview_item = ImportConflictBatchPreviewItem {
        conflict_id: "name-1".to_owned(),
        conflict_type: ImportConflictBatchConflictType::SameNameDifferentContent,
        existing_file_id: Some(7),
        existing_path: Some("docs/report.pdf".to_owned()),
        incoming_path: ".areamatrix/staging/session-42/report.pdf".to_owned(),
        target_path: Some("docs/report_1.pdf".to_owned()),
        selected_strategy: ImportConflictBatchStrategy::KeepBoth,
        status: ImportConflictBatchPreviewStatus::Ready,
        will_replace: false,
        will_keep_both: true,
        will_skip: false,
        will_ask_per_item: false,
        index_only: false,
        risk_summary: "Existing file will remain unchanged".to_owned(),
        reason: None,
    };
    let preview = ImportConflictBatchPreviewReport {
        import_session_id: "session-42".to_owned(),
        preview_token: "preview:import-conflict:session-42".to_owned(),
        apply_to_all_similar_conflicts: true,
        requested_conflict_count: 2,
        duplicate_conflict_count: 1,
        same_name_conflict_count: 1,
        included_count: 2,
        pending_count: 0,
        blocked_count: 0,
        replace_count: 0,
        skip_count: 1,
        keep_both_count: 1,
        ask_per_item_count: 0,
        trash_available: true,
        undo_available: true,
        can_apply: true,
        apply_blocked_reason: None,
        replace_confirmation_required: false,
        replace_confirmation_summary: None,
        items: vec![preview_item],
    };
    assert_eq!(preview.duplicate_conflict_count, 1);
    assert_eq!(preview.same_name_conflict_count, 1);
    assert_eq!(
        preview.items[0].conflict_type,
        ImportConflictBatchConflictType::SameNameDifferentContent
    );
    assert_eq!(
        preview.items[0].selected_strategy,
        ImportConflictBatchStrategy::KeepBoth
    );
    assert_eq!(
        preview.items[0].status,
        ImportConflictBatchPreviewStatus::Ready
    );
    assert!(preview.can_apply);

    let result = ImportConflictBatchItemResult {
        conflict_id: "name-1".to_owned(),
        conflict_type: ImportConflictBatchConflictType::SameNameDifferentContent,
        applied_strategy: ImportConflictBatchStrategy::KeepBoth,
        status: ImportConflictBatchResultStatus::KeptBoth,
        file_id: Some(42),
        final_path: Some("docs/report_1.pdf".to_owned()),
        error: None,
    };
    let report = ImportConflictBatchApplyReport {
        import_session_id: "session-42".to_owned(),
        requested_conflict_count: 2,
        resolved_count: 2,
        skipped_count: 1,
        kept_both_count: 1,
        replaced_count: 0,
        queued_for_per_item_count: 0,
        pending_count: 0,
        failed_count: 0,
        item_results: vec![result],
        affected_file_ids: vec![42],
        undo_token: Some("undo:import-conflict:session-42".to_owned()),
        change_log_actions: vec!["imported".to_owned()],
        failure_summary: None,
    };
    assert_eq!(report.resolved_count, 2);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.kept_both_count, 1);
    assert_eq!(
        report.item_results[0].status,
        ImportConflictBatchResultStatus::KeptBoth
    );
    assert_eq!(report.affected_file_ids, vec![42]);

    let documented_errors = [
        CoreError::conflict("stale import conflict preview"),
        CoreError::file_not_found("missing import conflict"),
        CoreError::permission_denied("staging permission denied"),
        CoreError::staging_recovery_required(".areamatrix/staging"),
        CoreError::io("staging promote failed"),
        CoreError::db("import session metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 6);
}

#[test]
fn import_conflict_batch_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        preview_import_conflict_batch("/tmp/repo".to_owned(), preview_request()),
        Err(CoreError::Db { .. })
    ));

    let mut empty_session = preview_request();
    empty_session.import_session_id.clear();
    assert!(matches!(
        preview_import_conflict_batch("/tmp/repo".to_owned(), empty_session),
        Err(CoreError::FileNotFound { .. })
    ));

    let mut empty_conflicts = preview_request();
    empty_conflicts.conflict_ids.clear();
    assert!(matches!(
        preview_import_conflict_batch("/tmp/repo".to_owned(), empty_conflicts),
        Err(CoreError::FileNotFound { .. })
    ));

    assert!(matches!(
        preview_import_conflict_batch(String::new(), preview_request()),
        Err(CoreError::PermissionDenied { .. })
    ));

    assert!(matches!(
        apply_import_conflict_batch(
            "/tmp/repo".to_owned(),
            apply_request(false),
            "preview:import-conflict:session-42".to_owned()
        ),
        Err(CoreError::Conflict { .. })
    ));

    assert!(matches!(
        apply_import_conflict_batch("/tmp/repo".to_owned(), apply_request(true), String::new()),
        Err(CoreError::Conflict { .. })
    ));

    assert!(matches!(
        apply_import_conflict_batch(
            "/tmp/repo".to_owned(),
            apply_request(true),
            "preview:import-conflict:session-42".to_owned()
        ),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn import_conflict_batch_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-1/task-81: C2-17 contract-api",
        "为 C2-17 import-conflict-batch 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C2-17 import-conflict-batch",
        "- S2-21 import-conflict-batch",
        "计划新增：`preview_import_conflict_batch`、`apply_import_conflict_batch`",
        "import_session_id、conflict_ids、批量策略。",
        "每个冲突项的策略预览、风险说明、执行结果和失败摘要。",
        "写入 import session 决策、file 记录变化、change log 和 undo action。",
        "按策略 Skip、Keep both、Replace 或 Ask per item 处理 staged 文件。",
        "Replace 必须走二次确认和可恢复路径。",
        "- `Conflict`",
        "- `FileNotFound`",
        "- `PermissionDenied`",
        "- `StagingRecoveryRequired`",
        "- `Io`",
        "- `Db`",
        "Hash duplicate 默认 Skip，同名不同内容默认 Keep both。",
        "批量策略执行前必须预览每一项影响。",
        "失败时保留 staged 文件和冲突状态，不覆盖用户文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-21 | import-conflict-batch | C2-17, C2-07 | import conflict batch decision | import session, staging, change_log",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ImportConflictBatchPreviewReport preview_import_conflict_batch(",
        "ImportConflictBatchPreviewRequest request",
        "ImportConflictBatchApplyReport apply_import_conflict_batch(",
        "ImportConflictBatchApplyRequest request",
        "string preview_token",
        "dictionary ImportConflictBatchPreviewRequest",
        "sequence<string> conflict_ids;",
        "ImportConflictBatchStrategy duplicate_strategy;",
        "ImportConflictBatchStrategy same_name_strategy;",
        "dictionary ImportConflictBatchPreviewItem",
        "ImportConflictBatchConflictType conflict_type;",
        "ImportConflictBatchPreviewStatus status;",
        "dictionary ImportConflictBatchPreviewReport",
        "boolean replace_confirmation_required;",
        "string? replace_confirmation_summary;",
        "dictionary ImportConflictBatchApplyRequest",
        "boolean replace_confirmed;",
        "dictionary ImportConflictBatchItemResult",
        "ImportConflictBatchResultStatus status;",
        "dictionary ImportConflictBatchApplyReport",
        "sequence<i64> affected_file_ids;",
        "sequence<string> change_log_actions;",
        "enum ImportConflictBatchConflictType { \"DuplicateHash\", \"SameNameDifferentContent\" };",
        "enum ImportConflictBatchStrategy { \"Skip\", \"KeepBoth\", \"Replace\", \"AskPerItem\" };",
        "StagingRecoveryRequired(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `preview_import_conflict_batch(repo, request)` | conflict | √ | Conflict / FileNotFound / PermissionDenied / StagingRecoveryRequired / Io / Db |",
        "| `apply_import_conflict_batch(repo, request, preview_token)` | conflict | √ | Conflict / FileNotFound / PermissionDenied / StagingRecoveryRequired / Io / Db |",
        "### `preview_import_conflict_batch(repoPath, request) throws -> ImportConflictBatchPreviewReport`",
        "### `apply_import_conflict_batch(repoPath, request, previewToken) throws -> ImportConflictBatchApplyReport`",
        "`duplicate_strategy`：hash duplicate 行策略，默认应为 `Skip`。",
        "`same_name_strategy`：same-name different-content 行策略，默认应为 `KeepBoth`。",
        "`replace_confirmation_required` / `replace_confirmation_summary`",
        "`replace_confirmed`；当任一策略为 `Replace` 且该字段为 false 时必须返回",
        "任一失败必须保留 staged 文件和冲突状态",
        "本合同不新增",
        "control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn import_conflict_batch_contract_matches_consuming_page_state_without_adjacent_scope() {
    for fragment in [
        "按冲突类型分组展示：hash duplicate、same-name different-content。",
        "为 hash duplicate 提供 `Skip`、`Keep both`、`Replace`。",
        "为 same-name different-content 提供 `Keep both (auto-number)`、`Ask per item`、`Replace`。",
        "默认策略安全：hash duplicate 默认 `Skip`，same-name different-content 默认 `Keep both (auto-number)`。",
        "Apply this strategy to all similar conflicts",
        "未勾选行保持 `Pending`",
        "Replace 必须二次确认",
        "Index-only 目标不得被 Replace 覆盖",
        "恢复态：策略应用部分失败后停留结果摘要",
        "部分失败显示成功、失败、skipped、replaced、kept-both 和 pending 数量。",
        "成功策略写 change_log，并在可逆时显示 Undo toast。",
    ] {
        assert_contains(S2_21_PAGE, fragment);
    }

    for fragment in [
        "批量导入时冲突不弹 N 次对话框，而是用汇总策略。",
        "重复（hash dup）：`Skip`（默认）/ `Keep both` / `Replace`（危险）",
        "重名不同内容：`Keep both (auto-number)`（默认）/ `Ask per item` / `Replace`",
        "Replace 是唯一可能造成用户“丢数据”的选择",
        "必须二次确认",
    ] {
        assert_contains(DEDUP_CONFLICT, fragment);
    }

    for fragment in [
        "C2-17 import conflict batch contract types and entry points.",
        "preview_import_conflict_batch",
        "apply_import_conflict_batch",
        "side-effect free",
        "missing replace confirmation",
        "stale import conflict batch preview",
    ] {
        assert_contains(CONTRACT_RS, fragment);
    }

    for fragment in [
        "pub fn preview_import_conflict_batch(",
        "import_conflict_batch::preview_import_conflict_batch",
        "pub fn apply_import_conflict_batch(",
        "import_conflict_batch::apply_import_conflict_batch",
        "S2-21",
        "C2-17",
        "This contract does not implement iCloud conflict resolution",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in [
        "Conflict",
        "FileNotFound",
        "PermissionDenied",
        "StagingRecoveryRequired",
        "Io",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
