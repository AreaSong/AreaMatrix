#[path = "support/remote_provider_config_common.rs"]
mod common;

use std::{fs, path::Path};

use area_matrix_core::{
    disable_remote_ai_provider, enable_remote_ai_provider, load_remote_ai_provider_config,
    test_remote_ai_provider, AiFeatureKind, CoreError, RemoteAiProviderKind,
    RemoteProviderDisableRequest, RemoteProviderTestRequest, RemoteProviderTestStatus,
};
use common::{
    enable_request, enable_request_for_endpoint, enable_request_with_key_reference,
    initialized_repo, keychain_reference, path_string, repo_config_rows, repo_config_value,
    test_key_reference, test_request, test_request_for_endpoint, test_request_with_key_reference,
    ProbeRuntime,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

#[test]
fn remote_provider_config_implementation_tests_then_enables_persisted_snapshot() {
    let repo = initialized_repo();
    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let request = test_request_for_endpoint(endpoint_url);
    let expected_key_reference = request.key_reference.clone();
    let test_result =
        test_remote_ai_provider(path_string(repo.path()), request).expect("test provider");
    let verification_token = test_result
        .verification_token
        .clone()
        .expect("successful test returns verification token");
    let captured_request = runtime.captured_payload();

    assert_eq!(test_result.status, RemoteProviderTestStatus::Succeeded);
    assert!(test_result.provider_verified);
    assert_eq!(
        test_result.sanitized_message,
        "Remote provider metadata verified"
    );
    assert!(!verification_token.contains("keychain"));
    assert!(captured_request.contains("\"url\":\"https://provider.example.test/probe?model_id=gpt-4.1-mini&probe=provider_metadata\""));
    assert!(captured_request.contains("\"name\":\"Authorization\""));
    assert!(captured_request.contains("\"value\":\"Bearer test-provider-secret\""));
    assert!(!captured_request.contains("README"));
    assert!(!captured_request.contains("AREAMATRIX"));
    assert!(!captured_request.contains("note"));

    let snapshot = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(verification_token.clone(), endpoint_url),
    )
    .expect("enable tested provider");

    assert!(snapshot.provider_configured);
    assert!(snapshot.provider_verified);
    assert!(snapshot.remote_provider_enabled);
    assert!(snapshot.credential_configured);
    assert_eq!(snapshot.provider, Some(RemoteAiProviderKind::Other));
    assert_eq!(snapshot.model_id.as_deref(), Some("gpt-4.1-mini"));
    assert_eq!(snapshot.endpoint_url.as_deref(), Some(endpoint_url));
    assert_eq!(
        snapshot.feature_scope,
        vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags]
    );
    assert!(snapshot.updated_at.is_some());
    assert_eq!(snapshot.disabled_reason, None);

    let stored = repo_config_value(repo.path(), "remote_provider_config")
        .expect("remote provider config persisted");
    assert!(stored.contains("gpt-4.1-mini"));
    assert!(stored.contains(&expected_key_reference));
    assert!(!stored.contains(&verification_token));
    assert!(!stored.contains("test-provider-secret"));
    assert!(repo_config_value(repo.path(), "remote_provider_pending_verification").is_none());

    let loaded =
        load_remote_ai_provider_config(path_string(repo.path())).expect("load provider snapshot");
    assert_eq!(loaded, snapshot);

    let disabled = disable_remote_ai_provider(
        path_string(repo.path()),
        RemoteProviderDisableRequest {
            remove_stored_credential: false,
        },
    )
    .expect("disable remote provider");
    assert!(disabled.provider_configured);
    assert!(disabled.provider_verified);
    assert!(!disabled.remote_provider_enabled);
    assert!(disabled.credential_configured);
    assert_eq!(
        disabled.feature_scope,
        vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags]
    );
    assert_eq!(
        disabled.disabled_reason.as_deref(),
        Some("Remote provider is disabled")
    );

    let loaded_disabled =
        load_remote_ai_provider_config(path_string(repo.path())).expect("reload disabled snapshot");
    assert_eq!(loaded_disabled, disabled);
}

#[test]
fn remote_provider_config_implementation_loads_empty_and_removes_credential_on_disable() {
    let repo = initialized_repo();
    let empty =
        load_remote_ai_provider_config(path_string(repo.path())).expect("load empty snapshot");
    assert!(!empty.provider_configured);
    assert!(!empty.provider_verified);
    assert!(!empty.remote_provider_enabled);
    assert!(!empty.credential_configured);
    assert!(empty.feature_scope.is_empty());

    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/remove-credential";
    let test_result = test_remote_ai_provider(
        path_string(repo.path()),
        test_request_for_endpoint(endpoint_url),
    )
    .expect("test provider");
    let _ = runtime.captured_payload();
    enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(
            test_result
                .verification_token
                .expect("successful test returns verification token"),
            endpoint_url,
        ),
    )
    .expect("enable provider");

    let disabled = disable_remote_ai_provider(
        path_string(repo.path()),
        RemoteProviderDisableRequest {
            remove_stored_credential: true,
        },
    )
    .expect("disable and forget credential reference");

    assert!(!disabled.provider_configured);
    assert!(!disabled.provider_verified);
    assert!(!disabled.remote_provider_enabled);
    assert!(!disabled.credential_configured);
    assert_eq!(disabled.provider, Some(RemoteAiProviderKind::Other));
    assert_eq!(disabled.model_id.as_deref(), Some("gpt-4.1-mini"));
    assert_eq!(disabled.endpoint_url.as_deref(), Some(endpoint_url));
    assert_eq!(
        disabled.disabled_reason.as_deref(),
        Some("Remote provider is not configured")
    );

    let stored = repo_config_value(repo.path(), "remote_provider_config")
        .expect("disabled config remains persisted");
    assert!(stored.contains("\"key_reference\":\"\""));
    assert!(!stored.contains(&test_key_reference()));
    assert!(!stored.contains("test-provider-secret"));
}

#[test]
fn remote_provider_config_implementation_requires_matching_successful_test() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());

    let without_test = enable_remote_ai_provider(
        repo_path.clone(),
        enable_request("verify:remote-provider:not-tested".to_owned()),
    );
    assert!(matches!(without_test, Err(CoreError::Config { .. })));
    assert!(repo_config_value(repo.path(), "remote_provider_config").is_none());

    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let test_result =
        test_remote_ai_provider(repo_path.clone(), test_request_for_endpoint(endpoint_url))
            .expect("test provider before enable");
    let _ = runtime.captured_payload();
    let mut changed_model = enable_request(
        test_result
            .verification_token
            .expect("successful test returns verification token"),
    );
    changed_model.model_id = "gpt-4.1".to_owned();

    let result = enable_remote_ai_provider(repo_path, changed_model);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert!(repo_config_value(repo.path(), "remote_provider_config").is_none());
}

#[test]
fn remote_provider_config_implementation_rejects_secret_like_key_without_partial_write() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());
    let mut request = test_request();
    request.key_reference = "sk-secret-key-material".to_owned();

    let result = test_remote_ai_provider(path_string(repo.path()), request);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let mut hidden_secret = test_request();
    hidden_secret.key_reference = "keychain:sk-secret-key-material".to_owned();
    let result = test_remote_ai_provider(path_string(repo.path()), hidden_secret);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let mut plain_reference = test_request();
    plain_reference.key_reference = "remote-openai".to_owned();
    let result = test_remote_ai_provider(path_string(repo.path()), plain_reference);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_implementation_maps_provider_test_failures_without_verification() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());

    let rejected_runtime = ProbeRuntime::new(401);
    let rejected = test_request_for_endpoint("https://provider.example.test/rejected");
    assert_unverified_test_status(
        repo.path(),
        rejected,
        RemoteProviderTestStatus::ProviderRejected,
    );
    let _ = rejected_runtime.captured_payload();

    let connection_failed_runtime = ProbeRuntime::new(503);
    let connection_failed = test_request_for_endpoint("https://provider.example.test/unavailable");
    assert_unverified_test_status(
        repo.path(),
        connection_failed,
        RemoteProviderTestStatus::ConnectionFailed,
    );
    let _ = connection_failed_runtime.captured_payload();

    let unsupported_runtime = ProbeRuntime::new(404);
    let unsupported = test_request_for_endpoint("https://provider.example.test/unsupported");
    assert_unverified_test_status(
        repo.path(),
        unsupported,
        RemoteProviderTestStatus::UnsupportedProvider,
    );
    let _ = unsupported_runtime.captured_payload();

    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_implementation_accepts_keychain_reference_via_platform_runtime() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());
    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/keychain";
    let key_reference = keychain_reference();
    let request = test_request_with_key_reference(endpoint_url, key_reference.clone());

    let result = test_remote_ai_provider(path_string(repo.path()), request).expect("test provider");
    let captured_request = runtime.captured_payload();
    let verification_token = result
        .verification_token
        .clone()
        .expect("successful keychain test returns verification token");

    assert_eq!(result.status, RemoteProviderTestStatus::Succeeded);
    assert!(result.provider_verified);
    assert!(!captured_request.contains("Authorization"));
    assert!(!captured_request.contains("Bearer"));
    assert!(captured_request.contains("\"key_reference\":\"keychain:areamatrix-remote-openai\""));

    let snapshot = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_with_key_reference(verification_token, endpoint_url, key_reference.clone()),
    )
    .expect("enable keychain-backed provider");
    assert!(snapshot.remote_provider_enabled);
    assert!(snapshot.credential_configured);

    let stored = repo_config_value(repo.path(), "remote_provider_config")
        .expect("keychain-backed provider config persisted");
    assert!(stored.contains(&key_reference));
    assert_eq!(before_rows.len() + 1, repo_config_rows(repo.path()).len());
}

#[test]
fn remote_provider_config_implementation_rolls_back_when_enable_write_fails() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let test_result =
        test_remote_ai_provider(repo_path.clone(), test_request_for_endpoint(endpoint_url))
            .expect("test provider");
    let _ = runtime.captured_payload();
    let pending_before = repo_config_value(repo.path(), "remote_provider_pending_verification")
        .expect("pending verification persisted");
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute_batch(
            "CREATE TRIGGER fail_remote_provider_config_insert
             BEFORE INSERT ON repo_config
             WHEN NEW.key = 'remote_provider_config'
             BEGIN
               SELECT RAISE(ABORT, 'forced remote provider config write failure');
             END;",
        )
        .expect("install failing remote provider trigger");
    drop(connection);

    let result = enable_remote_ai_provider(
        repo_path,
        enable_request_for_endpoint(
            test_result
                .verification_token
                .expect("successful test returns verification token"),
            endpoint_url,
        ),
    );

    assert!(matches!(result, Err(CoreError::Internal { .. })));
    assert!(repo_config_value(repo.path(), "remote_provider_config").is_none());
    assert_eq!(
        repo_config_value(repo.path(), "remote_provider_pending_verification"),
        Some(pending_before)
    );
}

#[test]
fn remote_provider_config_implementation_preserves_user_files_and_ai_boundaries() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");

    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let test_result = test_remote_ai_provider(
        path_string(repo.path()),
        test_request_for_endpoint(endpoint_url),
    )
    .expect("test remote provider");
    let captured_request = runtime.captured_payload();
    assert!(!captured_request.contains("user readme"));
    assert!(!captured_request.contains("user overview"));
    enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(
            test_result
                .verification_token
                .expect("successful test returns verification token"),
            endpoint_url,
        ),
    )
    .expect("enable remote provider");

    assert_eq!(
        fs::read_to_string(&readme_path).expect("read README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&overview_path).expect("read AREAMATRIX"),
        "user overview\n"
    );
    for path in [
        repo.path().join(".areamatrix/secrets"),
        repo.path().join(".areamatrix/ai_call_log"),
        repo.path()
            .join(".areamatrix/generated/remote_provider.json"),
    ] {
        assert!(!path.exists(), "C3-03 must not create {}", path.display());
    }
}

fn assert_unverified_test_status(
    repo: &Path,
    request: RemoteProviderTestRequest,
    expected_status: RemoteProviderTestStatus,
) {
    let result =
        test_remote_ai_provider(path_string(repo), request).expect("test provider returns status");

    assert_eq!(result.status, expected_status);
    assert!(!result.provider_verified);
    assert!(result.verification_token.is_none());
    assert!(!result.sanitized_message.contains("keychain"));
    assert!(repo_config_value(repo, "remote_provider_pending_verification").is_none());
}
