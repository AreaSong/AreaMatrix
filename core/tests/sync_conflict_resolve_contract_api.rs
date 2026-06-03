use area_matrix_core::{
    preview_sync_conflict_resolution, resolve_sync_conflict, CoreError, CoreResult,
    SyncConflictFileRole, SyncConflictReplacePlan, SyncConflictResolutionPreviewReport,
    SyncConflictResolutionRequest, SyncConflictResolutionStrategy, SyncConflictResolveReport,
    SyncConflictStatus, SyncConflictVersionImpact,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-76-c4-16-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-16-sync-conflict-resolve.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const SYNC_CONFLICT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-01-sync-conflict.md");
const REPLACE_CONFIRM_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-09-replace-confirm.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const SYNC_CONFLICT_RESOLVE_RS: &str = include_str!("../src/sync_conflict_resolve.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn sync_conflict_resolve_contract_exports_signatures_outputs_and_errors() {
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

    let impact = SyncConflictVersionImpact {
        path: "docs/report.pdf".to_owned(),
        file_id: Some(42),
        role: SyncConflictFileRole::Existing,
        will_keep: true,
        will_be_canonical: true,
        will_remain_user_visible: true,
        will_move_to_trash: false,
        recovery_target: None,
        reason: None,
    };
    let replace_plan = SyncConflictReplacePlan {
        old_path: "docs/report.pdf".to_owned(),
        new_path: "docs/report (incoming).pdf".to_owned(),
        old_hash_sha256: Some("oldhash".to_owned()),
        new_hash_sha256: Some("newhash".to_owned()),
        affected_file_id: Some(42),
        backup_target: Some("Trash".to_owned()),
        database_update: "canonical record will point to incoming file".to_owned(),
        change_log_action: "conflict_resolved_use_incoming".to_owned(),
        recovery_note: "existing file must remain recoverable".to_owned(),
    };
    let preview = SyncConflictResolutionPreviewReport {
        conflict_id: "sync-conflict:same-name:docs/report.pdf".to_owned(),
        resolution: SyncConflictResolutionStrategy::UseIncoming,
        default_resolution: SyncConflictResolutionStrategy::KeepBoth,
        status_after: SyncConflictStatus::Resolved,
        version_impacts: vec![impact],
        kept_paths: vec!["docs/report (incoming).pdf".to_owned()],
        retained_paths: Vec::new(),
        planned_trash_paths: vec!["docs/report.pdf".to_owned()],
        affected_file_ids: vec![42],
        canonical_path: Some("docs/report.pdf".to_owned()),
        change_log_action: "conflict_resolved_use_incoming".to_owned(),
        destructive: true,
        requires_replace_confirmation: true,
        trash_required: true,
        trash_available: true,
        can_apply: false,
        blocked_reason: Some("replace confirmation is required".to_owned()),
        preview_token: Some("preview-token".to_owned()),
        replace_plan: Some(replace_plan),
    };

    assert_eq!(
        preview.default_resolution,
        SyncConflictResolutionStrategy::KeepBoth
    );
    assert_eq!(preview.status_after, SyncConflictStatus::Resolved);
    assert!(preview.requires_replace_confirmation);
    assert_eq!(
        preview
            .replace_plan
            .as_ref()
            .expect("replace plan")
            .backup_target,
        Some("Trash".to_owned())
    );

    let request = SyncConflictResolutionRequest {
        strategy: SyncConflictResolutionStrategy::KeepBoth,
        preview_token: "preview-token".to_owned(),
        replace_confirmed: false,
        replace_confirmation_id: None,
    };
    assert_eq!(request.strategy, SyncConflictResolutionStrategy::KeepBoth);

    let report = SyncConflictResolveReport {
        conflict_id: preview.conflict_id.clone(),
        resolution: SyncConflictResolutionStrategy::KeepBoth,
        status: SyncConflictStatus::Resolved,
        kept_paths: vec![
            "docs/report.pdf".to_owned(),
            "docs/report (incoming).pdf".to_owned(),
        ],
        retained_paths: vec!["docs/report (incoming).pdf".to_owned()],
        trashed_paths: Vec::new(),
        affected_file_ids: vec![42, 43],
        change_log_action: "conflict_resolved_keep_both".to_owned(),
        undo_token: None,
        resolved_at: Some(1_777_700_000),
    };
    assert_eq!(report.status, SyncConflictStatus::Resolved);
    assert!(report.trashed_paths.is_empty());

    let documented_errors = [
        CoreError::conflict("stale sync conflict"),
        CoreError::permission_denied("replace confirmation is required"),
        CoreError::io("trash preflight failed"),
        CoreError::db("conflict state unavailable"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn sync_conflict_resolve_contract_has_no_fake_success_before_implementation() {
    assert!(matches!(
        preview_sync_conflict_resolution(
            "/tmp/repo".to_owned(),
            "sync-conflict:same-name:docs/report.pdf".to_owned(),
            SyncConflictResolutionStrategy::KeepBoth
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert!(matches!(
        resolve_sync_conflict(
            "/tmp/repo".to_owned(),
            "sync-conflict:same-name:docs/report.pdf".to_owned(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::KeepBoth,
                preview_token: "preview-token".to_owned(),
                replace_confirmed: false,
                replace_confirmation_id: None,
            }
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert!(matches!(
        resolve_sync_conflict(
            "/tmp/repo".to_owned(),
            "sync-conflict:same-name:docs/report.pdf".to_owned(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: "preview-token".to_owned(),
                replace_confirmed: false,
                replace_confirmation_id: None,
            }
        ),
        Err(CoreError::PermissionDenied { .. })
    ));
}

#[test]
fn sync_conflict_resolve_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-76: C4-16 contract-api",
        "为 C4-16 sync-conflict-resolve 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-16 sync-conflict-resolve",
        "- S4-X-01 sync-conflict",
        "- S4-X-09 replace-confirm",
        "计划新增：`preview_sync_conflict_resolution`、`resolve_sync_conflict`",
        "conflict_id、resolution。",
        "预览和解决报告。",
        "更新 conflict state。",
        "写 change log。",
        "默认保留版本；丢弃版本进入 Trash。",
        "Replace 必须二次确认。",
        "- `Conflict`",
        "- `PermissionDenied`",
        "- `Io`",
        "- `Db`",
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
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "SyncConflictResolutionPreviewReport preview_sync_conflict_resolution(",
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

    for fragment in [
        "| `preview_sync_conflict_resolution(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |",
        "| `resolve_sync_conflict(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |",
        "### `preview_sync_conflict_resolution(repoPath, conflictId, resolution) throws -> SyncConflictResolutionPreviewReport`",
        "### `resolve_sync_conflict(repoPath, conflictId, resolution) throws -> SyncConflictResolveReport`",
        "`default_resolution` 必须为 `KeepBoth`",
        "`KeepBoth`：默认安全策略，所有版本继续留在用户可见位置。",
        "`UseExisting`：canonical path 继续指向 existing",
        "`UseIncoming`：incoming 将成为 canonical path；必须先进入 S4-X-09 二次确认。",
        "不移动、不删除、不重命名、不覆盖、不 Trash、不隐藏任何用户文件或冲突副本。",
        "任一阶段失败必须保持 conflict unresolved",
        "本合同没有引入 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`Conflict { path }`",
        "`PermissionDenied { path }`",
        "`Io { message }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn sync_conflict_resolve_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "默认提供 `Keep both`",
        "Use existing version",
        "Use incoming version",
        "对 Replace、Use incoming、删除类动作要求进入",
        "Impact summary",
        "每个解决策略都能看到文件影响、DB record 影响和 change log 类型。",
        "解决失败：冲突保持未解决状态，不删除中间文件。",
    ] {
        assert_contains(SYNC_CONFLICT_PAGE, fragment);
    }

    for fragment in [
        "Confirm Replace",
        "Replace plan",
        "显示平台回收站/Trash 可用性。",
        "要求用户完成二次确认。",
        "Trash/Recycle Bin Unknown：按不可用处理，禁用 Replace",
        "执行顺序固定为：preflight -> move old to Recycle Bin/Trash",
        "任一步失败时 existing 必须保持可用",
    ] {
        assert_contains(REPLACE_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "Previews a C4-16 sync conflict resolution plan without mutating files.",
        "`S4-X-01 sync-conflict` consumes this contract",
        "`S4-X-09",
        "must not mark a conflict resolved",
        "move files, rename files, overwrite files, Trash versions",
        "Resolves one C4-16 sync conflict after preview and required confirmation.",
        "replace_confirmed",
        "Failure must leave",
        "CoreError::Conflict",
        "CoreError::PermissionDenied",
        "CoreError::Io",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-16 sync conflict resolution contract types and entry points.",
        "User-selected C4-16 sync conflict resolution strategy.",
        "Per-version impact shown in S4-X-01 before applying a resolution.",
        "Replace plan required before S4-X-09 can confirm a destructive resolution.",
        "Read-only preview report for one planned sync conflict resolution.",
        "Apply request for resolving one sync conflict after preview.",
        "Result report returned after resolving one sync conflict.",
        "replace confirmation is required",
    ] {
        assert_contains(SYNC_CONFLICT_RESOLVE_RS, fragment);
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
