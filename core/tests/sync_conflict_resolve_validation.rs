use area_matrix_core::{
    preview_sync_conflict_resolution, resolve_sync_conflict, CoreError, CoreResult,
    SyncConflictResolutionPreviewReport, SyncConflictResolutionRequest,
    SyncConflictResolutionStrategy, SyncConflictResolveReport, SyncConflictStatus,
};
use pretty_assertions::assert_eq;

mod support;
#[path = "support/sync_conflict_resolve_validation.rs"]
mod sync_conflict_resolve_validation_support;

use support::system_trash_home::with_test_system_trash;
use sync_conflict_resolve_validation_support::{
    active_file_snapshot, conflict_state, path_string, setup_same_name_conflict,
    sync_resolution_change_count, user_files, validation_snapshot,
};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-79-c4-16-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-16-sync-conflict-resolve.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const SYNC_CONFLICT_RESOLVE_RS: &str = include_str!("../src/sync_conflict_resolve.rs");
const PLAN_RS: &str = include_str!("../src/sync_conflict_resolve/plan.rs");
const APPLY_RS: &str = include_str!("../src/sync_conflict_resolve/apply.rs");
const DB_SYNC_CONFLICT_RS: &str = include_str!("../src/db/sync_conflicts.rs");
const CONTRACT_TEST: &str = include_str!("sync_conflict_resolve_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("sync_conflict_resolve_implementation.rs");
const FAILURE_TEST: &str = include_str!("sync_conflict_resolve_failure_recovery.rs");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn sync_conflict_resolve_validation_success_paths_cover_preview_and_apply() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let before_preview = validation_snapshot(repo.path());

        let preview = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionStrategy::KeepBoth,
        )
        .expect("preview keep both");

        assert_keep_both_preview(&preview, &conflict_id);
        assert_eq!(validation_snapshot(repo.path()), before_preview);

        let report = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::KeepBoth,
                preview_token: preview.preview_token.expect("preview token is available"),
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        )
        .expect("resolve keep both");

        assert_keep_both_report(&report, &conflict_id);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::Resolved
        );
        assert_eq!(sync_resolution_change_count(repo.path()), 1);
        assert_eq!(
            user_files(repo.path()),
            vec![
                ("docs/report (Alice's conflicted copy).pdf".to_owned(), b"conflicted".to_vec()),
                ("docs/report.pdf".to_owned(), b"original".to_vec()),
            ]
        );
        assert_eq!(active_file_snapshot(repo.path(), file_id).0, "docs/report.pdf");
        assert!(!trash_dir.join("report.pdf").exists());
    });
}

fn assert_keep_both_preview(
    preview: &SyncConflictResolutionPreviewReport,
    conflict_id: &str,
) {
    assert_eq!(preview.conflict_id, conflict_id);
    assert_eq!(
        preview.default_resolution,
        SyncConflictResolutionStrategy::KeepBoth
    );
    assert_eq!(preview.status_after, SyncConflictStatus::Resolved);
    assert!(preview.can_apply);
    assert!(!preview.destructive);
    assert!(!preview.requires_replace_confirmation);
    assert_eq!(preview.change_log_action, "conflict_resolved_keep_both");
    assert_eq!(preview.planned_trash_paths, Vec::<String>::new());
    assert_eq!(
        preview.kept_paths,
        vec![
            "docs/report.pdf".to_owned(),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
        ]
    );
}

fn assert_keep_both_report(report: &SyncConflictResolveReport, conflict_id: &str) {
    assert_eq!(report.conflict_id, conflict_id);
    assert_eq!(report.resolution, SyncConflictResolutionStrategy::KeepBoth);
    assert_eq!(report.status, SyncConflictStatus::Resolved);
    assert_eq!(report.change_log_action, "conflict_resolved_keep_both");
    assert!(report.trashed_paths.is_empty());
    assert!(report.undo_token.is_none());
    assert!(report.resolved_at.is_some());
}

#[test]
fn sync_conflict_resolve_validation_failure_paths_keep_conflict_unresolved() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let before = validation_snapshot(repo.path());
        let before_file_row = active_file_snapshot(repo.path(), file_id);
        let preview = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionStrategy::UseIncoming,
        )
        .expect("preview use incoming");

        assert!(preview.destructive);
        assert!(preview.requires_replace_confirmation);
        assert!(!preview.can_apply);
        assert_eq!(
            preview.blocked_reason.as_deref(),
            Some("replace confirmation is required")
        );
        assert_eq!(preview.planned_trash_paths, vec!["docs/report.pdf"]);
        assert!(preview.replace_plan.is_some());

        let result = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: preview.preview_token.expect("preview token is available"),
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        );

        assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
        assert_eq!(validation_snapshot(repo.path()), before);
        assert_eq!(active_file_snapshot(repo.path(), file_id), before_file_row);
        assert_eq!(sync_resolution_change_count(repo.path()), 0);
        assert!(!trash_dir.join("report.pdf").exists());
    });
}

#[test]
fn sync_conflict_resolve_validation_core_api_udl_rust_and_tests_stay_aligned() {
    fn assert_preview(
        _: fn(
            String,
            String,
            SyncConflictResolutionStrategy,
        ) -> CoreResult<SyncConflictResolutionPreviewReport>,
    ) {
    }
    fn assert_resolve(
        _: fn(
            String,
            String,
            SyncConflictResolutionRequest,
        ) -> CoreResult<SyncConflictResolveReport>,
    ) {
    }

    assert_preview(preview_sync_conflict_resolution);
    assert_resolve(resolve_sync_conflict);
    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-79: C4-16 validation",
        "为 C4-16 sync-conflict-resolve 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-79",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-16 sync-conflict-resolve",
        "- S4-X-01 sync-conflict",
        "- S4-X-09 replace-confirm",
        "计划新增：`preview_sync_conflict_resolution`、`resolve_sync_conflict`",
        "更新 conflict state。",
        "写 change log。",
        "默认保留版本；丢弃版本进入 Trash。",
        "Replace 必须二次确认。",
        "Resolve 失败保持 unresolved。",
        "不自动删除任何版本。",
        "Replace 必须经过 S4-X-09。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-X-01 | sync-conflict | C4-15, C4-16, C4-21 | conflict detect/resolve | 不静默删除任一版本",
        "| S4-X-09 | replace-confirm | C4-16, C4-21 | replace confirm | Trash/备份，禁止永久删除",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "Sync 模块", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_core_api_and_udl_type_alignment();
    assert_core_api_behavior_alignment();
    assert_error_and_rust_surface_alignment();
    assert_implementation_alignment();
}

fn assert_core_api_and_udl_type_alignment() {
    for fragment in [
        "SyncConflictResolutionPreviewReport preview_sync_conflict_resolution(",
        "string conflict_id",
        "SyncConflictResolutionStrategy resolution",
        "SyncConflictResolveReport resolve_sync_conflict(",
        "SyncConflictResolutionRequest resolution",
        "dictionary SyncConflictVersionImpact",
        "boolean will_remain_user_visible;",
        "boolean will_move_to_trash;",
        "dictionary SyncConflictReplacePlan",
        "string database_update;",
        "string recovery_note;",
        "dictionary SyncConflictResolutionPreviewReport",
        "SyncConflictStatus status_after;",
        "sequence<string> retained_paths;",
        "sequence<string> planned_trash_paths;",
        "boolean requires_replace_confirmation;",
        "string? preview_token;",
        "SyncConflictReplacePlan? replace_plan;",
        "dictionary SyncConflictResolutionRequest",
        "boolean replace_confirmed;",
        "dictionary SyncConflictResolveReport",
        "sequence<string> trashed_paths;",
        "enum SyncConflictResolutionStrategy { \"KeepBoth\", \"UseExisting\", \"UseIncoming\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_behavior_alignment() {
    for fragment in [
        "### `preview_sync_conflict_resolution(repoPath, conflictId, resolution) throws -> SyncConflictResolutionPreviewReport`",
        "`preview_sync_conflict_resolution` 是 C4-16 的多端同步冲突解决预览入口",
        "`default_resolution` 必须为 `KeepBoth`",
        "`KeepBoth`：默认安全策略，所有版本继续留在用户可见位置。",
        "`UseIncoming`：incoming 将成为 canonical path；必须先进入 S4-X-09 二次确认。",
        "不移动、不删除、不重命名、不覆盖、不 Trash、不隐藏任何用户文件或冲突副本。",
        "### `resolve_sync_conflict(repoPath, conflictId, resolution) throws -> SyncConflictResolveReport`",
        "`resolve_sync_conflict` 是 C4-16 的执行入口",
        "任一阶段失败必须保持 conflict unresolved",
        "解决失败时 UI 必须继续展示该冲突",
        "| `preview_sync_conflict_resolution(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |",
        "| `resolve_sync_conflict(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_error_and_rust_surface_alignment() {
    for fragment in [
        "`Conflict { path }`",
        "`PermissionDenied { path }`",
        "`Io { message }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "pub fn preview_sync_conflict_resolution(",
        "pub fn resolve_sync_conflict(",
        "must not mark a conflict resolved",
        "Failure must leave",
        "CoreError::Conflict",
        "CoreError::PermissionDenied",
        "CoreError::Io",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "SyncConflictReplacePlan",
        "SyncConflictResolutionPreviewReport",
        "SyncConflictResolutionRequest",
        "SyncConflictResolutionStrategy",
        "SyncConflictResolveReport",
        "SyncConflictVersionImpact",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}

fn assert_implementation_alignment() {
    for fragment in [
        "pub(crate) fn preview_sync_conflict_resolution(",
        "pub(crate) fn resolve_sync_conflict(",
        "validate_resolution_request",
        "ensure_request_matches_plan",
        "ensure_use_incoming_enabled",
        "resolution_detail_json",
        "sync_conflict_resolved",
    ] {
        assert_contains(SYNC_CONFLICT_RESOLVE_RS, fragment);
    }

    for fragment in [
        "build_resolution_plan",
        "non_destructive_plan",
        "use_incoming_plan",
        "replace confirmation is required",
        "preview_token",
        "Trash unavailable",
    ] {
        assert_contains(PLAN_RS, fragment);
    }

    for fragment in [
        "apply_resolution",
        "apply_file_replacement",
        "persist_resolution",
        "rollback_replacement",
        "TrashMoveGuard",
        "IncomingMoveGuard",
    ] {
        assert_contains(APPLY_RS, fragment);
    }

    for fragment in [
        "preflight_sync_conflict_resolution",
        "record_sync_conflict_resolution",
        "update_canonical_file_metadata",
        "insert_resolution_change",
    ] {
        assert_contains(DB_SYNC_CONFLICT_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "sync_conflict_resolve_contract_exports_signatures_outputs_and_errors",
        "sync_conflict_resolve_contract_rejects_uninitialized_and_unconfirmed_requests",
        "sync_conflict_resolve_docs_api_udl_and_control_map_stay_aligned",
        "sync_conflict_resolve_documents_consumers_and_scope_boundaries",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "sync_conflict_resolve_implementation_previews_keep_both_read_only",
        "sync_conflict_resolve_implementation_keep_both_resolves_state_without_moving_versions",
        "sync_conflict_resolve_implementation_use_incoming_requires_replace_confirmation",
        "sync_conflict_resolve_implementation_use_incoming_moves_existing_to_trash",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "sync_conflict_resolve_failure_recovery_preview_rejects_unwritable_metadata_read_only",
        "sync_conflict_resolve_failure_recovery_preflights_db_before_file_moves",
        "sync_conflict_resolve_failure_recovery_rolls_back_files_when_db_write_fails",
        "sync_conflict_resolve_failure_recovery_rejects_stale_preview_token_read_only",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
