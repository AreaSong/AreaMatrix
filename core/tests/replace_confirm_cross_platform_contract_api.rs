use area_matrix_core::{
    delete_file, import_file, resolve_sync_conflict, CoreError, CoreResult, DuplicateStrategy,
    FileEntry, ImportDestination, ImportOptions, StorageMode, SyncConflictReplacePlan,
    SyncConflictResolutionRequest, SyncConflictResolutionStrategy, SyncConflictResolveReport,
    SyncConflictStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-101-c4-21-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-21-replace-confirm-cross-platform.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const FILES_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-07-files-import.md");
const WINDOWS_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-05-import-flow.md");
const LINUX_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-05-import-flow.md");
const SYNC_CONFLICT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-01-sync-conflict.md");
const REPLACE_CONFIRM_PAGE: &str =
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

#[test]
fn replace_confirm_contract_exports_existing_core_entry_points() {
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}
    fn assert_delete(_: fn(String, i64) -> CoreResult<()>) {}
    fn assert_resolve(
        _: fn(
            String,
            String,
            SyncConflictResolutionRequest,
        ) -> CoreResult<SyncConflictResolveReport>,
    ) {
    }

    assert_import(import_file);
    assert_delete(delete_file);
    assert_resolve(resolve_sync_conflict);

    let overwrite_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("docs".to_owned()),
        override_category: None,
        override_filename: Some("report.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Overwrite,
    };
    assert_eq!(
        overwrite_options.duplicate_strategy,
        DuplicateStrategy::Overwrite
    );

    let replace_plan = SyncConflictReplacePlan {
        old_path: "docs/report.pdf".to_owned(),
        new_path: "docs/report (incoming).pdf".to_owned(),
        old_hash_sha256: Some("oldhash".to_owned()),
        new_hash_sha256: Some("newhash".to_owned()),
        affected_file_id: Some(21),
        backup_target: Some("Trash".to_owned()),
        database_update: "canonical record will point to incoming file".to_owned(),
        change_log_action: "conflict_resolved_use_incoming".to_owned(),
        recovery_note: "existing file must remain recoverable".to_owned(),
    };
    assert_eq!(replace_plan.affected_file_id, Some(21));
    assert_eq!(replace_plan.backup_target.as_deref(), Some("Trash"));

    let request = SyncConflictResolutionRequest {
        strategy: SyncConflictResolutionStrategy::UseIncoming,
        preview_token: "sync-conflict-preview:token".to_owned(),
        replace_confirmed: true,
        replace_confirmation_id: Some("replace-confirm:s4-x-09:21".to_owned()),
    };
    assert!(request.replace_confirmed);
    assert_eq!(
        request.replace_confirmation_id.as_deref(),
        Some("replace-confirm:s4-x-09:21")
    );

    let report = SyncConflictResolveReport {
        conflict_id: "sync-conflict:same-name:docs/report.pdf".to_owned(),
        resolution: SyncConflictResolutionStrategy::UseIncoming,
        status: SyncConflictStatus::Resolved,
        kept_paths: vec!["docs/report.pdf".to_owned()],
        retained_paths: Vec::new(),
        trashed_paths: vec!["docs/report.pdf".to_owned()],
        affected_file_ids: vec![21],
        change_log_action: "conflict_resolved_use_incoming".to_owned(),
        undo_token: Some("undo:sync-conflict:21".to_owned()),
        resolved_at: Some(1_777_800_000),
    };
    assert_eq!(report.status, SyncConflictStatus::Resolved);
    assert_eq!(report.trashed_paths, vec!["docs/report.pdf"]);

    let documented_errors = [
        CoreError::permission_denied("replace confirmation is required"),
        CoreError::conflict("replace plan is stale"),
        CoreError::io("trash preflight failed"),
        CoreError::db("replace change log failed"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn replace_confirm_docs_core_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-101: C4-21 contract-api",
        "为 C4-21 replace-confirm-cross-platform 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-21 replace-confirm-cross-platform",
        "- S4-X-09 replace-confirm",
        "`import_file` with overwrite strategy",
        "`delete_file`",
        "`resolve_sync_conflict`",
        "target file、incoming file、confirmed overwrite action。",
        "replace report。",
        "软删除/替换旧记录。",
        "写 change log。",
        "丢弃版本必须进入平台 Trash 或保留备份。",
        "不直接永久删除。",
        "- `PermissionDenied`",
        "- `Conflict`",
        "- `Io`",
        "- `Db`",
        "Replace 必须二次确认。",
        "平台 Trash 不可用时禁用 replace。",
        "失败后旧版本和新版本状态可解释。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-07 | files-import | C4-06, C4-21 | Files import / replace confirm",
        "| S4-WIN-05 | import-flow | C4-13, C4-21 | desktop import / replace",
        "| S4-LNX-05 | import-flow | C4-13, C4-21 | desktop import / replace",
        "| S4-X-01 | sync-conflict | C4-15, C4-16, C4-21 | conflict detect/resolve",
        "| S4-X-09 | replace-confirm | C4-16, C4-21 | replace confirm | Trash/备份，禁止永久删除",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "FileEntry import_file(",
        "void delete_file(string repo_path, i64 file_id);",
        "SyncConflictResolveReport resolve_sync_conflict(",
        "dictionary ImportOptions",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary SyncConflictReplacePlan",
        "string old_path;",
        "string new_path;",
        "i64? affected_file_id;",
        "string? backup_target;",
        "string database_update;",
        "string change_log_action;",
        "string recovery_note;",
        "dictionary SyncConflictResolutionRequest",
        "boolean replace_confirmed;",
        "string? replace_confirmation_id;",
        "dictionary SyncConflictResolveReport",
        "sequence<string> trashed_paths;",
        "string? undo_token;",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "enum SyncConflictResolutionStrategy { \"KeepBoth\", \"UseExisting\", \"UseIncoming\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |",
        "| `delete_file(repo, file_id)` | storage | √ | Io / Db / FileNotFound / PermissionDenied / Internal |",
        "| `resolve_sync_conflict(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |",
        "Replace 仍属于 C4-21 / `S4-X-09`",
        "Replace 仍属于 C4-21 / `S4-X-09`",
        "`UseIncoming`：incoming 将成为 canonical path；必须先进入 S4-X-09 二次确认。",
        "S4-X-09 可以从 `replace_plan` 得到二次确认所需的 old/new file、hash、record id、",
        "existing 只能进入 Trash/Recycle Bin",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`PermissionDenied { path }`",
        "`Conflict { path }`",
        "`Io { message }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn replace_confirm_consumers_have_required_state_without_adjacent_capabilities() {
    for fragment in [
        "Replace 选项如展示，必须标为危险，并在应用前进入 `S4-X-09 replace-confirm`。",
        "Replace 必须进入 `S4-X-09` 二次确认。",
    ] {
        assert_contains(FILES_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "`Replace existing file` 需要二次确认",
        "Replace：必须进入 `S4-X-09 replace-confirm` 二次确认",
        "Recycle Bin 不可用、检测失败、网络盘不支持、组织策略禁止或 move-to-bin 失败时禁用 Replace",
        "Replace 执行顺序：先确认 Recycle Bin 移动成功，再执行替换；任一步失败都不得覆盖 existing 文件。",
    ] {
        assert_contains(WINDOWS_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "Replace：如果 Trash 可用，进入 [S4-X-09 replace-confirm]",
        "Trash 不可用或检测失败：Replace 不能假装可逆，默认禁用",
        "Trash 检测失败时 Replace 禁用，并提示改用 `Keep both`。",
    ] {
        assert_contains(LINUX_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "对 Replace、Use incoming、删除类动作要求进入",
        "Change log：写入 `conflict_resolved_use_incoming`",
        "若策略涉及替换、删除或移动旧版本，进入 [S4-X-09 replace-confirm]",
        "Replace/Use incoming 等破坏性结果必须进入",
    ] {
        assert_contains(SYNC_CONFLICT_PAGE, fragment);
    }

    for fragment in [
        "Confirm Replace",
        "展示 Replace plan：文件、hash、路径、受影响 DB record、change log 计划和旧文件保留位置。",
        "显示平台回收站/Trash 可用性。",
        "要求用户完成二次确认。",
        "Old version will be kept at: Recycle Bin / Trash / Core safety backup path",
        "Change log: replace_file",
        "Trash/Recycle Bin Unknown：按不可用处理，禁用 Replace",
        "执行顺序固定为：preflight -> move old to Recycle Bin/Trash",
        "任一步失败时 existing 必须保持可用",
        "不可逆 Replace 在 Stage 4 不可被执行。",
    ] {
        assert_contains(REPLACE_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "DuplicateStrategy::Overwrite",
        "C4-21 /",
        "replace confirmation has proven",
        "delete_file",
        "Moves a repo-owned file entry to the system Trash",
        "replace-confirm",
        "replace_confirmed",
        "Failure must leave",
    ] {
        assert_contains(API_RS, fragment);
    }
}
