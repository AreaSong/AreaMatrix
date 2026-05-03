use area_matrix_core::{
    create_diagnostics_snapshot, reindex_from_filesystem, repair_metadata, CoreError, CoreResult,
    DiagnosticsSnapshot, ReindexReport, RepairOptions, RepairReport,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn repair_reindex_metadata_contract_api_exposes_documented_signatures_and_outputs() {
    fn assert_reindex(_: fn(String) -> CoreResult<ReindexReport>) {}
    fn assert_snapshot(_: fn(String) -> CoreResult<DiagnosticsSnapshot>) {}
    fn assert_repair(_: fn(String, RepairOptions) -> CoreResult<RepairReport>) {}

    assert_reindex(reindex_from_filesystem);
    assert_snapshot(create_diagnostics_snapshot);
    assert_repair(repair_metadata);

    let options = RepairOptions {
        full_rescan: true,
        preserve_diagnostics_snapshot: true,
    };
    let snapshot = DiagnosticsSnapshot {
        snapshot_path: ".areamatrix/diagnostics/db-20260503.sqlite".to_owned(),
        created_at: 1_777_766_400,
        warnings: vec!["partial metadata snapshot".to_owned()],
    };
    let report = RepairReport {
        scan_session_id: Some(26),
        diagnostics_snapshot_path: Some(snapshot.snapshot_path.clone()),
        inserted: 3,
        updated: 2,
        skipped: 1,
        errors: Vec::new(),
    };

    assert!(options.full_rescan);
    assert!(options.preserve_diagnostics_snapshot);
    assert!(snapshot.snapshot_path.starts_with(".areamatrix/"));
    assert_eq!(report.scan_session_id, Some(26));
    assert_eq!(
        report.diagnostics_snapshot_path.as_deref(),
        Some(".areamatrix/diagnostics/db-20260503.sqlite")
    );
}

#[test]
fn repair_reindex_metadata_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C1-26 repair-reindex-metadata",
        "- S1-37 db-repair-confirm",
        "- S1-11 main-repo-error",
        "- S1-32 error-recovery",
        "`reindex_from_filesystem(repo_path) -> ReindexReport`",
        "`create_diagnostics_snapshot(repo_path) -> DiagnosticsSnapshot`",
        "`repair_metadata(repo_path, options) -> RepairReport`",
        "- `RepairOptions.full_rescan`",
        "- `RepairOptions.preserve_diagnostics_snapshot`",
        "- `DiagnosticsSnapshot.snapshot_path` / `created_at` / `warnings`",
        "- `RepairReport.scan_session_id` / `diagnostics_snapshot_path`",
        "只处理 `.areamatrix/` 元数据。",
        "不移动、不重命名、不删除用户文件。",
        "不覆盖 `README.md`。",
        "修复失败不得删除用户文件，也不得清空诊断信息。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-37 | db-repair-confirm | C1-26, C1-16 | `repair_metadata`, `reindex_from_filesystem`",
        "metadata repair only",
        "Db, PermissionDenied, Io",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ReindexReport reindex_from_filesystem(string repo_path);",
        "DiagnosticsSnapshot create_diagnostics_snapshot(string repo_path);",
        "RepairReport repair_metadata(string repo_path, RepairOptions options);",
        "dictionary RepairOptions",
        "boolean full_rescan;",
        "boolean preserve_diagnostics_snapshot;",
        "dictionary DiagnosticsSnapshot",
        "string snapshot_path;",
        "i64 created_at;",
        "dictionary RepairReport",
        "string? diagnostics_snapshot_path;",
        "sequence<string> errors;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn repair_reindex_metadata_contract_documents_errors_and_side_effect_boundaries() {
    let documented_errors = [
        CoreError::db("database error"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::internal("internal error"),
    ];
    assert_eq!(documented_errors.len(), 4);

    for error_name in ["Db", "PermissionDenied", "Io", "Internal"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "Reindexes repository metadata from the current filesystem state.",
        "C1-26 exposes this full-rescan API",
        "Creates a diagnostics snapshot for C1-26 metadata repair.",
        "Repairs AreaMatrix metadata without mutating user files.",
        "The only allowed side effects are writes under `.areamatrix/` metadata",
        "must never move, rename, delete, overwrite, trash, or download user",
        "failure must leave any diagnostics reference intact",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Options for C1-26 metadata repair.",
        "Reference to an AreaMatrix-owned diagnostics snapshot.",
        "Metadata repair summary returned to Swift.",
        "Whether repair should run a full filesystem rescan after diagnostics.",
        "Repository-relative path under `.areamatrix/`",
        "Optional diagnostics snapshot path preserved before repair mutation.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "只允许写 `.areamatrix/index.db` 与 scan session metadata。",
        "不移动、不重命名、不删除、不覆盖、不 Trash 用户文件。",
        "不覆盖 `README.md`",
        "`preserve_diagnostics_snapshot = true`",
        "修复失败不得删除用户文件，也不得清空已生成的诊断信息。",
        "云端备份恢复和自动上传诊断不属于 Stage 1。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}
