use area_matrix_core::{
    create_diagnostics_snapshot, preflight_repair_metadata, reindex_from_filesystem,
    repair_metadata, CoreError, CoreResult, DiagnosticsSnapshot, ReindexReport, RepairMetadataOutcome,
    RepairMetadataPreflight, RepairOptions, RepairReport,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
#[path = "support/domain_contract_source.rs"]
mod domain_contract_source;

use domain_contract_source::DOMAIN_RS;
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
    fn assert_preflight(_: fn(String) -> CoreResult<RepairMetadataPreflight>) {}
    fn assert_repair(_: fn(String, RepairOptions) -> CoreResult<RepairReport>) {}

    assert_reindex(reindex_from_filesystem);
    assert_snapshot(create_diagnostics_snapshot);
    assert_preflight(preflight_repair_metadata);
    assert_repair(repair_metadata);

    let options = RepairOptions {
        preserve_diagnostics_snapshot: true,
        preflight_token: "token".to_owned(),
        repository_locale_policy: "system".to_owned(),
    };
    let snapshot = DiagnosticsSnapshot {
        snapshot_path: ".areamatrix/diagnostics/db-20260503.sqlite".to_owned(),
        created_at: 1_777_766_400,
        warnings: vec!["partial metadata snapshot".to_owned()],
    };
    let report = RepairReport {
        diagnostics_snapshot_path: Some(snapshot.snapshot_path.clone()),
        outcome: RepairMetadataOutcome::Rebuilt,
    };

    assert!(options.preserve_diagnostics_snapshot);
    assert!(snapshot.snapshot_path.starts_with(".areamatrix/"));
    assert_eq!(report.outcome, RepairMetadataOutcome::Rebuilt);
    assert_eq!(
        report.diagnostics_snapshot_path.as_deref(),
        Some(".areamatrix/diagnostics/db-20260503.sqlite")
    );
}

#[test]
fn repair_reindex_metadata_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "ReindexReport reindex_from_filesystem(string repo_path);",
        "DiagnosticsSnapshot create_diagnostics_snapshot(string repo_path);",
        "RepairMetadataPreflight preflight_repair_metadata(string repo_path);",
        "RepairReport repair_metadata(string repo_path, RepairOptions options);",
        "dictionary RepairOptions",
        "boolean preserve_diagnostics_snapshot;",
        "string preflight_token;",
        "string repository_locale_policy;",
        "dictionary RepairMetadataPreflight",
        "RepairMetadataLocaleState locale_state;",
        "enum RepairMetadataOutcome",
        "dictionary DiagnosticsSnapshot",
        "string snapshot_path;",
        "i64 created_at;",
        "dictionary RepairReport",
        "string? diagnostics_snapshot_path;",
        "RepairMetadataOutcome outcome;",
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
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "Reindexes repository metadata from the current filesystem state.",
        "Reindexes repository metadata from the current filesystem state.",
        "Creates a diagnostics snapshot for metadata repair.",
        "Repairs AreaMatrix metadata without mutating user files.",
        "The only allowed side effects are writes under `.areamatrix/` metadata",
        "must never move, rename, delete, overwrite, trash, or download user",
        "failure must leave any diagnostics reference intact",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Options for metadata repair.",
        "Read-only repair observation",
        "Reference to an AreaMatrix-owned diagnostics snapshot.",
        "Metadata repair summary returned to Swift.",
        "Opaque token returned by the read-only repair preflight.",
        "Repository-relative path under `.areamatrix/`",
        "Optional diagnostics snapshot path preserved before repair mutation.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "只允许写 `.areamatrix/` metadata。",
        "不移动、不重命名、不删除、不覆盖、不 Trash 用户文件。",
        "不覆盖 `README.md`",
        "`preserve_diagnostics_snapshot = true`",
        "修复失败不得删除用户文件，也不得清空已生成的诊断信息。",
        "云端备份恢复和自动上传诊断不属于当前诊断合同。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}
