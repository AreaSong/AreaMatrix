use area_matrix_core::{
    list_icloud_conflicts, CoreError, CoreResult, ICloudConflictPair, ICloudConflictStatus,
};
use pretty_assertions::assert_eq;
use std::fs;

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
        "expected document to contain `{needle}`"
    );
}

#[test]
fn list_icloud_conflicts_contract_api_exposes_documented_signature_and_output() {
    fn assert_list(_: fn(String) -> CoreResult<Vec<ICloudConflictPair>>) {}

    assert_list(list_icloud_conflicts);

    let pair = ICloudConflictPair {
        conflict_id: "docs/report.pdf::conflicted-copy".to_owned(),
        original_path: Some("docs/report.pdf".to_owned()),
        conflicted_copy_path: "docs/report (Alice's conflicted copy).pdf".to_owned(),
        original_modified_at: Some(100),
        conflicted_modified_at: 200,
        status: ICloudConflictStatus::NeedsReview,
        uncertainty_reason: Some("multiple candidates".to_owned()),
    };

    assert_eq!(pair.original_path.as_deref(), Some("docs/report.pdf"));
    assert_eq!(
        pair.conflicted_copy_path,
        "docs/report (Alice's conflicted copy).pdf"
    );
    assert_eq!(pair.status, ICloudConflictStatus::NeedsReview);
    assert!(matches!(
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::ICloudPlaceholder { .. }
    ));
}

#[test]
fn list_icloud_conflicts_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "sequence<ICloudConflictPair> list_icloud_conflicts(string repo_path);",
        "dictionary ICloudConflictPair",
        "string conflict_id;",
        "string? original_path;",
        "string conflicted_copy_path;",
        "i64? original_modified_at;",
        "i64 conflicted_modified_at;",
        "ICloudConflictStatus status;",
        "string? uncertainty_reason;",
        "enum ICloudConflictStatus { \"NeedsReview\", \"Resolved\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn list_icloud_conflicts_contract_documents_errors_and_side_effect_boundaries() {
    let documented_errors = [
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_errors.len(), 4);

    for error_name in ["ICloudPlaceholder", "PermissionDenied", "Io", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "Lists iCloud conflicted copy pairs without resolving them.",
        "iCloud conflict listing owns the read-only contract for iCloud conflict list",
        "Ambiguous pairings must be returned as",
        "`ICloudConflictStatus::NeedsReview`",
        "must not delete, move, rename, overwrite, merge, or download",
        "Single-item resolution remains a later explicit action",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Lifecycle state for an iCloud conflicted copy pair.",
        "Read-only iCloud conflicted copy pair returned to Swift.",
        "Stable identifier for later single-item resolution.",
        "Repository-relative conflicted copy path.",
        "Reason shown when pairing is uncertain and needs user review.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "不删除、不移动、不重命名、不覆盖、不合并任何原始文件或冲突副本。",
        "不触发 iCloud placeholder 下载",
        "不写 `files` 记录",
        "空态返回空数组",
        "`status = NeedsReview`",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn list_icloud_conflicts_empty_repository_returns_empty_list() {
    let repo = tempfile::tempdir().expect("create temp repository");

    let conflicts = list_icloud_conflicts(repo.path().to_string_lossy().into_owned())
        .expect("list empty iCloud conflicts");

    assert!(conflicts.is_empty());
}

#[test]
fn list_icloud_conflicts_detects_conflicted_copy_without_mutating_files() {
    let repo = tempfile::tempdir().expect("create temp repository");
    let docs = repo.path().join("docs");
    fs::create_dir(&docs).expect("create docs directory");

    let original = docs.join("report.pdf");
    let conflicted = docs.join("report (Alice's conflicted copy).pdf");
    fs::write(&original, b"original").expect("write original file");
    fs::write(&conflicted, b"conflicted").expect("write conflicted copy");

    let conflicts = list_icloud_conflicts(repo.path().to_string_lossy().into_owned())
        .expect("list iCloud conflicts");

    assert_eq!(conflicts.len(), 1);
    assert_eq!(
        conflicts[0].original_path.as_deref(),
        Some("docs/report.pdf")
    );
    assert_eq!(
        conflicts[0].conflicted_copy_path,
        "docs/report (Alice's conflicted copy).pdf"
    );
    assert_eq!(conflicts[0].status, ICloudConflictStatus::NeedsReview);
    assert_eq!(
        fs::read(&original).expect("read original file after list"),
        b"original"
    );
    assert_eq!(
        fs::read(&conflicted).expect("read conflicted copy after list"),
        b"conflicted"
    );
}
