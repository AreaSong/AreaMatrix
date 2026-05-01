use area_matrix_core::{
    validate_repo_path, CoreResult, RepoInitMode, RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

#[test]
fn validate_repo_path_contract_exports_callable_signature() {
    fn assert_signature(_: fn(String) -> CoreResult<RepoPathValidation>) {}

    assert_signature(validate_repo_path);
}

#[test]
fn validate_repo_path_contract_exposes_structured_status_and_issues() {
    let validation = RepoPathValidation {
        repo_path: "/tmp/area-matrix".to_owned(),
        exists: true,
        is_directory: true,
        is_readable: true,
        is_writable: true,
        is_empty: false,
        is_initialized: false,
        is_inside_area_matrix: false,
        is_icloud_path: false,
        has_unfinished_scan_session: false,
        recommended_mode: Some(RepoInitMode::AdoptExisting),
        issues: vec![RepoPathIssue::NonEmptyDirectory],
    };

    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(validation.issues, vec![RepoPathIssue::NonEmptyDirectory]);
    assert!(!validation.is_empty);
}
