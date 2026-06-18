use area_matrix_core::{
    delete_file, import_file, resolve_sync_conflict, CoreError, CoreResult, DuplicateStrategy,
    FileEntry, ImportDestination, ImportOptions, StorageMode, SyncConflictReplacePlan,
    SyncConflictResolutionRequest, SyncConflictResolutionStrategy, SyncConflictResolveReport,
    SyncConflictStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../workflow/versions/v1-mvp/execution/phase-4/4-3-stage4-multiplatform/task-101-c4-21-contract-api.md"
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
