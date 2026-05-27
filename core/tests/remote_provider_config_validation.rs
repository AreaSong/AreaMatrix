#[path = "support/remote_provider_config_validation.rs"]
mod validation_support;

use area_matrix_core::{
    enable_remote_ai_provider, test_remote_ai_provider, AiFeatureKind, CoreResult, ErrorKind,
    RemoteAiProviderKind, RemoteProviderConfigSnapshot, RemoteProviderEnableRequest,
    RemoteProviderTestRequest, RemoteProviderTestResult, RemoteProviderTestStatus,
};
use pretty_assertions::assert_eq;
use validation_support::{
    assert_consumer_gate_alignment, assert_contains, assert_core_api_and_udl_alignment,
    assert_no_api_key_material, assert_not_contains, assert_rust_contract_alignment,
    assert_sanitized_error, assert_validation_docs_alignment, enable_request, initialized_repo,
    path_string, repo_config_rows, repo_config_value, repo_snapshot, test_key_reference,
    test_request, ProbeRuntime, PENDING_TEST_KEY, REMOTE_CONFIG_KEY,
};

#[test]
fn remote_provider_config_validation_covers_ui_ready_success_without_secret_persistence() {
    let repo = initialized_repo();
    let before = repo_snapshot(repo.path());
    let endpoint_url = "https://provider.example.test/probe";
    let runtime = ProbeRuntime::new("Succeeded");

    let test_result = test_remote_ai_provider(path_string(repo.path()), test_request(endpoint_url))
        .expect("test provider succeeds");
    let verification_token = test_result
        .verification_token
        .clone()
        .expect("successful test returns verification token");
    let captured_payload = runtime.captured_payload();

    assert_eq!(test_result.status, RemoteProviderTestStatus::Succeeded);
    assert!(test_result.provider_verified);
    assert_eq!(
        test_result.sanitized_message,
        "Remote provider metadata verified"
    );
    assert_no_api_key_material(&test_result.sanitized_message);
    assert_no_api_key_material(&verification_token);
    assert_contains(&captured_payload, "provider.example.test/probe");
    assert_contains(&captured_payload, "gpt-4.1-mini");
    assert_not_contains(&captured_payload, "user readme");
    assert_not_contains(&captured_payload, "user overview");

    let snapshot = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request(verification_token.clone(), endpoint_url),
    )
    .expect("enable tested provider succeeds");

    assert!(snapshot.provider_configured);
    assert!(snapshot.provider_verified);
    assert!(snapshot.remote_provider_enabled);
    assert!(snapshot.credential_configured);
    assert_eq!(snapshot.provider, Some(RemoteAiProviderKind::Other));
    assert_eq!(snapshot.model_id.as_deref(), Some("gpt-4.1-mini"));
    assert_eq!(snapshot.endpoint_url.as_deref(), Some(endpoint_url));
    assert_eq!(snapshot.disabled_reason, None);
    assert_eq!(
        snapshot.feature_scope,
        enable_request(String::new(), endpoint_url).feature_scope
    );

    let stored =
        repo_config_value(repo.path(), REMOTE_CONFIG_KEY).expect("remote provider config stored");
    assert_contains(&stored, &test_key_reference());
    assert_not_contains(&stored, &verification_token);
    assert_no_api_key_material(&stored);
    assert!(repo_config_value(repo.path(), PENDING_TEST_KEY).is_none());

    let after = repo_snapshot(repo.path());
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.user_overview, before.user_overview);
    assert!(after.forbidden_remote_paths.is_empty());
}

#[test]
fn remote_provider_config_validation_covers_failure_paths_and_rollback() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());

    let missing_credential = RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some("https://provider.example.test/probe".to_owned()),
        key_reference: "secure-storage:env:AREAMATRIX_REMOTE_PROVIDER_VALIDATION_MISSING_KEY"
            .to_owned(),
    };
    let result = test_remote_ai_provider(path_string(repo.path()), missing_credential);
    assert_sanitized_error(
        result.expect_err("missing credential must fail"),
        ErrorKind::PermissionDenied,
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let mut invalid_endpoint = test_request("http://example.test/probe");
    invalid_endpoint.key_reference = test_key_reference();
    let result = test_remote_ai_provider(path_string(repo.path()), invalid_endpoint);
    assert_sanitized_error(
        result.expect_err("non-loopback HTTP endpoint must fail"),
        ErrorKind::Config,
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let rejected_runtime = ProbeRuntime::new("ProviderRejected");
    let rejected = test_remote_ai_provider(
        path_string(repo.path()),
        test_request("https://provider.example.test/rejected"),
    )
    .expect("provider rejection returns sanitized status");
    let _ = rejected_runtime.captured_payload();
    assert_eq!(rejected.status, RemoteProviderTestStatus::ProviderRejected);
    assert!(!rejected.provider_verified);
    assert!(rejected.verification_token.is_none());
    assert_no_api_key_material(&rejected.sanitized_message);
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let success_runtime = ProbeRuntime::new("Succeeded");
    let test_result = test_remote_ai_provider(
        path_string(repo.path()),
        test_request("https://provider.example.test/probe"),
    )
    .expect("test provider before invalid enable attempts");
    let _ = success_runtime.captured_payload();
    let pending_before =
        repo_config_value(repo.path(), PENDING_TEST_KEY).expect("pending verification stored");

    let mut no_consent = enable_request(
        test_result
            .verification_token
            .clone()
            .expect("successful test returns verification token"),
        "https://provider.example.test/probe",
    );
    no_consent.data_flow_confirmed = false;
    let result = enable_remote_ai_provider(path_string(repo.path()), no_consent);
    assert_sanitized_error(
        result.expect_err("missing consent must fail"),
        ErrorKind::Config,
    );

    let mut duplicate_scope = enable_request(
        test_result
            .verification_token
            .expect("successful test returns verification token"),
        "https://provider.example.test/probe",
    );
    duplicate_scope
        .feature_scope
        .push(AiFeatureKind::AutoSummaries);
    let result = enable_remote_ai_provider(path_string(repo.path()), duplicate_scope);
    assert_sanitized_error(
        result.expect_err("duplicate feature scope must fail"),
        ErrorKind::Config,
    );

    assert!(repo_config_value(repo.path(), REMOTE_CONFIG_KEY).is_none());
    assert_eq!(
        repo_config_value(repo.path(), PENDING_TEST_KEY),
        Some(pending_before)
    );
    assert!(repo_snapshot(repo.path()).forbidden_remote_paths.is_empty());
}

#[test]
fn remote_provider_config_validation_locks_core_api_udl_and_rust_contract() {
    fn assert_test_signature(
        _: fn(String, RemoteProviderTestRequest) -> CoreResult<RemoteProviderTestResult>,
    ) {
    }
    fn assert_enable_signature(
        _: fn(String, RemoteProviderEnableRequest) -> CoreResult<RemoteProviderConfigSnapshot>,
    ) {
    }

    assert_test_signature(test_remote_ai_provider);
    assert_enable_signature(enable_remote_ai_provider);
    assert_validation_docs_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_contract_alignment();
    assert_consumer_gate_alignment();
}
