use area_matrix_core::{
    validate_initialized_repo_path, validate_repo_path, CoreError, CoreResult, RepoInitMode,
    RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

#[test]
fn validate_repo_path_contract_exports_callable_signature() {
    fn assert_signature(_: fn(String) -> CoreResult<RepoPathValidation>) {}

    assert_signature(validate_repo_path);
    assert_signature(validate_initialized_repo_path);
}

#[test]
fn validate_repo_path_contract_exposes_structured_status_and_issues() {
    let create_empty_validation = RepoPathValidation {
        repo_path: "/tmp/area-matrix-empty".to_owned(),
        exists: true,
        is_directory: true,
        is_readable: true,
        is_writable: true,
        is_empty: true,
        is_initialized: false,
        is_inside_area_matrix: false,
        is_icloud_path: false,
        has_unfinished_scan_session: false,
        recommended_mode: Some(RepoInitMode::CreateEmpty),
        issues: vec![],
    };
    let adopt_existing_validation = RepoPathValidation {
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
        create_empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert!(create_empty_validation.issues.is_empty());
    assert_eq!(
        adopt_existing_validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        adopt_existing_validation.issues,
        vec![RepoPathIssue::NonEmptyDirectory]
    );
    assert!(!adopt_existing_validation.is_empty);
}

#[test]
fn validate_repo_path_contract_exposes_all_documented_issues() {
    let documented_issues = vec![
        RepoPathIssue::MissingPath,
        RepoPathIssue::NotDirectory,
        RepoPathIssue::NotReadable,
        RepoPathIssue::NotWritable,
        RepoPathIssue::NonEmptyDirectory,
        RepoPathIssue::AlreadyInitialized,
        RepoPathIssue::InsideAreaMatrix,
        RepoPathIssue::ICloudPath,
        RepoPathIssue::UnfinishedScanSession,
    ];

    let validation = RepoPathValidation {
        repo_path: "/tmp/area-matrix-risky".to_owned(),
        exists: false,
        is_directory: false,
        is_readable: false,
        is_writable: false,
        is_empty: false,
        is_initialized: false,
        is_inside_area_matrix: true,
        is_icloud_path: true,
        has_unfinished_scan_session: true,
        recommended_mode: None,
        issues: documented_issues.clone(),
    };

    assert_eq!(validation.issues, documented_issues);
    assert_eq!(validation.recommended_mode, None);
}

#[test]
fn validate_repo_path_contract_exposes_documented_error_codes() {
    let errors = [
        CoreError::InvalidPath,
        CoreError::PermissionDenied,
        CoreError::ICloudPlaceholder,
        CoreError::RepoNotInitialized,
    ];

    assert_eq!(errors.len(), 4);
}
