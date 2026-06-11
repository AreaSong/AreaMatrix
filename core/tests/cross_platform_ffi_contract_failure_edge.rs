use std::fs;

use area_matrix_core::{
    inspect_binding_contract, BindingApiContract, BindingContractReport, BindingContractRequest,
    BindingMissingCapability, BindingSupportStatus, BindingTargetPlatform, BindingTypeMapping,
    CoreError,
};
use pretty_assertions::assert_eq;

fn request(target_platform: BindingTargetPlatform, binding_version: i64) -> BindingContractRequest {
    BindingContractRequest {
        target_platform,
        binding_version,
    }
}

fn base_report() -> BindingContractReport {
    BindingContractReport {
        target_platform: BindingTargetPlatform::Swift,
        binding_version: 1,
        core_version: "0.1.0".to_owned(),
        supported_apis: vec![BindingApiContract {
            name: "inspect_binding_contract".to_owned(),
            capability: "C4-01".to_owned(),
            status: BindingSupportStatus::Supported,
            reason: None,
        }],
        type_mappings: vec![BindingTypeMapping {
            rust_type: "Result<T, CoreError>".to_owned(),
            udl_type: "[Throws=CoreError] T".to_owned(),
            target_type: "throws".to_owned(),
            status: BindingSupportStatus::Supported,
            reason: None,
        }],
        missing_capabilities: Vec::new(),
    }
}

#[test]
fn cross_platform_ffi_failure_edge_rejects_empty_or_out_of_range_binding_versions() {
    let repo = tempfile::tempdir().expect("create temporary user directory");
    let user_readme = repo.path().join("README.md");
    fs::write(&user_readme, b"user content").expect("write user file");
    let before = fs::read(&user_readme).expect("read user file before validation");

    for binding_version in [0, -1, 2, i64::MIN, i64::MAX] {
        let error =
            inspect_binding_contract(request(BindingTargetPlatform::Swift, binding_version))
                .expect_err("invalid binding version must fail");
        match error {
            CoreError::Config { reason } => {
                assert!(reason.contains("unsupported binding contract version"));
                assert!(reason.contains(&binding_version.to_string()));
                assert!(reason.contains("supported range"));
            }
            other => panic!("unexpected error shape: {other:?}"),
        }
        assert_eq!(
            fs::read(&user_readme).expect("read user file after failed binding check"),
            before
        );
        assert!(!repo.path().join(".areamatrix").exists());
    }
}

#[test]
fn cross_platform_ffi_failure_edge_rejects_incomplete_contract_reports_without_user_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary user directory");
    let user_readme = repo.path().join("README.md");
    fs::write(&user_readme, b"user content").expect("write user file");
    let before = fs::read(&user_readme).expect("read user file before validation");

    let mut report = base_report();
    report.supported_apis.clear();
    let error = report
        .validate()
        .expect_err("empty supported APIs must fail");
    assert!(matches!(error, CoreError::Internal { message } if message.contains("supported_apis")));
    assert_eq!(
        fs::read(&user_readme).expect("read user file after validation"),
        before
    );
    assert!(!repo.path().join(".areamatrix").exists());

    let mut report = base_report();
    report.type_mappings.clear();
    let error = report
        .validate()
        .expect_err("empty type mappings must fail");
    assert!(matches!(error, CoreError::Internal { message } if message.contains("type_mappings")));
    assert_eq!(
        fs::read(&user_readme).expect("read user file after validation"),
        before
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn cross_platform_ffi_failure_edge_rejects_fake_supported_missing_capabilities() {
    let repo = tempfile::tempdir().expect("create temporary user directory");
    let user_readme = repo.path().join("README.md");
    fs::write(&user_readme, b"user content").expect("write user file");
    let before = fs::read(&user_readme).expect("read user file before validation");
    let mut report = base_report();
    report.missing_capabilities.push(BindingMissingCapability {
        capability: "C4-01".to_owned(),
        label: "Generated Kotlin binding packaging".to_owned(),
        status: BindingSupportStatus::Supported,
        reason: "fake success".to_owned(),
    });

    let error = report
        .validate()
        .expect_err("supported missing capability must fail as incomplete");
    assert!(
        matches!(error, CoreError::Internal { message } if message.contains("missing_capabilities"))
    );
    assert_eq!(
        fs::read(&user_readme).expect("read user file after validation"),
        before
    );
    assert!(!repo.path().join(".areamatrix").exists());
}
