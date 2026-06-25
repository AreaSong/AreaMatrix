use area_matrix_core::{
    get_latest_scan_session, preview_manual_rescan, reindex_from_filesystem, resume_scan_session,
    CoreError, CoreResult, ManualRescanPreviewItem, ManualRescanPreviewItemKind,
    ManualRescanPreviewReport, ReindexReport, ScanSession, ScanSessionKind, ScanSessionStatus,
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

fn assert_contains_normalized(haystack: &str, needle: &str) {
    let normalized_haystack = normalize_text(haystack);
    let normalized_needle = needle.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        normalized_haystack.contains(&normalized_needle),
        "expected normalized text to contain `{needle}`"
    );
}

fn normalize_text(text: &str) -> String {
    text.lines()
        .map(|line| {
            line.trim_start()
                .strip_prefix("///")
                .or_else(|| line.trim_start().strip_prefix("//"))
                .unwrap_or(line.trim_start())
                .trim_start()
        })
        .collect::<Vec<_>>()
        .join(" ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn manual_rescan_contract_exports_documented_signatures_outputs_and_errors() {
    fn assert_preview(_: fn(String) -> CoreResult<ManualRescanPreviewReport>) {}
    fn assert_reindex(_: fn(String) -> CoreResult<ReindexReport>) {}
    fn assert_latest(_: fn(String) -> CoreResult<Option<ScanSession>>) {}
    fn assert_resume(_: fn(String, i64) -> CoreResult<ReindexReport>) {}

    assert_preview(preview_manual_rescan);
    assert_reindex(reindex_from_filesystem);
    assert_latest(get_latest_scan_session);
    assert_resume(resume_scan_session);

    let report = ReindexReport {
        scan_session_id: Some(419),
        inserted: 3,
        updated: 2,
        missing: 1,
        conflicts: 1,
        unreadable: 1,
        unknown: 1,
        skipped: 1,
        errors: vec!["docs/unreadable.pdf: permission denied".to_owned()],
    };
    assert_eq!(report.scan_session_id, Some(419));
    assert_eq!(report.inserted + report.updated + report.skipped, 6);

    let session = ScanSession {
        id: 419,
        kind: ScanSessionKind::Reindex,
        status: ScanSessionStatus::Completed,
        last_path: Some("docs/report.pdf".to_owned()),
        inserted: report.inserted,
        updated: report.updated,
        missing: report.missing,
        conflicts: report.conflicts,
        unreadable: report.unreadable,
        unknown: report.unknown,
        skipped: report.skipped,
        started_at: 1_777_800_000,
        updated_at: 1_777_800_060,
        finished_at: Some(1_777_800_060),
        errors: report.errors.clone(),
    };
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.finished_at, Some(1_777_800_060));
    assert_eq!(session.errors, report.errors);

    let preview = ManualRescanPreviewReport {
        added: 1,
        updated: 1,
        missing_or_deleted_from_fs: 1,
        renamed_candidates: 1,
        conflicts: 1,
        unreadable: 1,
        unknown: 1,
        skipped: 1,
        snapshot_id: "manual-rescan:1:1:1:1:1".to_owned(),
        created_at: 1_777_799_990,
        is_stale: false,
        items: vec![ManualRescanPreviewItem {
            kind: ManualRescanPreviewItemKind::Missing,
            relative_path: "docs/missing.pdf".to_owned(),
            reason: "metadata row has no backing file at the expected path".to_owned(),
            suggested_action: "Open Needs Review".to_owned(),
        }],
    };
    assert_eq!(preview.items[0].kind, ManualRescanPreviewItemKind::Missing);
    assert_eq!(preview.missing_or_deleted_from_fs, 1);

    let documented_errors = [
        CoreError::permission_denied("permission denied"),
        CoreError::db("database error"),
        CoreError::io("io error"),
        CoreError::conflict("manual rescan already running"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn manual_rescan_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "ManualRescanPreviewReport preview_manual_rescan(string repo_path);",
        "ReindexReport reindex_from_filesystem(string repo_path);",
        "ScanSession? get_latest_scan_session(string repo_path);",
        "ReindexReport resume_scan_session(string repo_path, i64 scan_session_id);",
        "dictionary ManualRescanPreviewReport",
        "i64 missing_or_deleted_from_fs;",
        "sequence<ManualRescanPreviewItem> items;",
        "enum ManualRescanPreviewItemKind",
        "dictionary ReindexReport",
        "i64? scan_session_id;",
        "i64 inserted;",
        "i64 updated;",
        "i64 missing;",
        "i64 conflicts;",
        "i64 unreadable;",
        "i64 unknown;",
        "i64 skipped;",
        "sequence<string> errors;",
        "dictionary ScanSession",
        "ScanSessionKind kind;",
        "ScanSessionStatus status;",
        "string? last_path;",
        "i64 started_at;",
        "i64 updated_at;",
        "i64? finished_at;",
        "enum ScanSessionKind { \"Adopt\", \"Reindex\" };",
        "enum ScanSessionStatus { \"Running\", \"Completed\", \"Paused\", \"Failed\", \"Interrupted\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `preview_manual_rescan(repoPath: String) throws -> ManualRescanPreviewReport`",
        "| `preview_manual_rescan(repo)` | repo | √ | Io / Db / PermissionDenied / Conflict |",
        "| `reindex_from_filesystem(repo)` | repo | √ | Io / Db / PermissionDenied / Conflict |",
        "| `get_latest_scan_session(repo)` | repo | √ | Db |",
        "| `resume_scan_session(repo, id)` | repo | √ | Io / Db |",
        "### `reindex_from_filesystem(repoPath: String) throws -> ReindexReport`",
        "### `get_latest_scan_session(repoPath: String) throws -> ScanSession?`",
        "### `resume_scan_session(repoPath: String, scanSessionId: Int64) throws -> ReindexReport`",
        "只允许写 `.areamatrix/index.db` 与 scan session metadata。",
        "不移动、不重命名、不删除、不覆盖、不 Trash 用户文件。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn manual_rescan_documents_consumers_scope_and_side_effect_boundaries() {
    for fragment in [
        "manual rescan also uses this entry point for Windows/Linux manual rescan after",
        "rescan confirmation has shown [`preview_manual_rescan`] and the high-risk confirmation",
        "The manual rescan scope is the entire repository",
        "partial subtree rescan is not exposed",
        "Consumers combine the returned [`ReindexReport`] with",
        "[`get_latest_scan_session`] to render the rescan summary",
        "manual rescan consumers use the same read-only session contract",
        "display manual rescan progress, completion, failure, interruption, and retry state",
        "resumes an interrupted or failed entire-repository manual rescan",
        "must not bypass confirmation, start a concurrent rescan, or expose",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }

    for fragment in [
        "manual rescan consumers use this as the post-confirmation summary",
        "ManualRescanPreviewReport",
        "Core does not silently delete or merge those items",
        "manual rescan consumers use `kind`, `status`, counters, timestamps",
        "without parsing logs or inspecting user files",
    ] {
        assert_contains_normalized(DOMAIN_RS, fragment);
    }

    for fragment in [
        "manual rescan reuses the full repository reindex entry point",
        "rescan confirmation has shown preview and the high-risk confirmation",
        "partial subtree rescan is not exposed",
        "must not",
        "move, delete, rename, overwrite, trash, or download user files",
        "manual rescan consumers read the latest scan session",
        "manual rescan resumes an interrupted or failed whole-repository manual rescan",
    ] {
        assert_contains_normalized(UDL, fragment);
    }

    for error_name in ["PermissionDenied", "Db", "Io", "Conflict"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(API_RS, error_name);
        assert_contains(UDL, error_name);
    }
}
