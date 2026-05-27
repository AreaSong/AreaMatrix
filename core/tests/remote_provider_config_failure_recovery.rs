#[path = "support/remote_provider_config_common.rs"]
mod common;

use std::{fs, path::Path};

use area_matrix_core::{
    disable_remote_ai_provider, enable_remote_ai_provider, load_ai_config,
    load_remote_ai_provider_config, map_core_error, test_remote_ai_provider, AiFeatureKind,
    CoreError, ErrorKind, ErrorRecoverability, ErrorSeverity, RemoteAiProviderKind,
    RemoteProviderDisableRequest, RemoteProviderTestRequest, RemoteProviderTestStatus,
};
use common::{
    enable_request_for_endpoint, initialized_repo, path_string, repo_config_rows,
    repo_config_value, test_key_reference, test_request_for_endpoint, ProbeRuntime, SECRET_VALUE,
    TEST_SECRET_ENV,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const REMOTE_CONFIG_KEY: &str = "remote_provider_config";
const PENDING_TEST_KEY: &str = "remote_provider_pending_verification";

fn assert_no_remote_provider_rows(repo: &Path) {
    assert!(repo_config_value(repo, REMOTE_CONFIG_KEY).is_none());
    assert!(repo_config_value(repo, PENDING_TEST_KEY).is_none());
}

fn successful_provider_test(repo: &Path, endpoint_url: &str) -> String {
    let runtime = ProbeRuntime::new("200");
    let result =
        test_remote_ai_provider(path_string(repo), test_request_for_endpoint(endpoint_url))
            .expect("test provider");
    let _ = runtime.captured_payload();
    result
        .verification_token
        .expect("successful test returns verification token")
}

fn assert_sanitized_error(error: CoreError, expected_kind: ErrorKind) {
    let text = error.to_string();
    let raw_context = error.raw_context().to_owned();
    let mapping = error.to_error_mapping();

    assert_eq!(error.kind(), expected_kind);
    assert_eq!(mapping.kind, expected_kind);
    assert_no_secret_material(&text);
    assert_no_secret_material(&raw_context);
    assert_no_secret_material(&mapping.raw_context);
    assert_no_secret_material(&mapping.user_message);
}

fn assert_no_secret_material(value: &str) {
    for secret_fragment in [SECRET_VALUE, TEST_SECRET_ENV, "sk-secret", "Bearer"] {
        assert!(
            !value.contains(secret_fragment),
            "unexpected secret fragment `{secret_fragment}` in `{value}`"
        );
    }
}

#[test]
fn remote_provider_config_failure_empty_state_keeps_remote_ai_disabled() {
    let repo = initialized_repo();
    let ai_config = load_ai_config(path_string(repo.path())).expect("load AI config");

    assert!(!ai_config.config.remote_ai_allowed);
    assert!(!ai_config.config.privacy_gate_enabled);
    assert_no_remote_provider_rows(repo.path());

    let result = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(
            "verify:remote-provider:not-tested".to_owned(),
            "https://provider.example.test/empty-state",
        ),
    );

    assert_sanitized_error(
        result.expect_err("enable without test must fail"),
        ErrorKind::Config,
    );
    assert_no_remote_provider_rows(repo.path());
}

#[test]
fn remote_provider_config_failure_invalid_inputs_do_not_write_partial_state() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());

    let invalid_tests = [
        RemoteProviderTestRequest {
            provider: RemoteAiProviderKind::Other,
            model_id: String::new(),
            endpoint_url: Some("https://provider.example.test/probe".to_owned()),
            key_reference: test_key_reference(),
        },
        RemoteProviderTestRequest {
            provider: RemoteAiProviderKind::OpenAi,
            model_id: "gpt-4.1-mini".to_owned(),
            endpoint_url: Some("https://provider.example.test/probe".to_owned()),
            key_reference: test_key_reference(),
        },
        RemoteProviderTestRequest {
            provider: RemoteAiProviderKind::Other,
            model_id: "gpt-4.1-mini".to_owned(),
            endpoint_url: Some("http://example.test/probe".to_owned()),
            key_reference: test_key_reference(),
        },
        RemoteProviderTestRequest {
            provider: RemoteAiProviderKind::Other,
            model_id: "gpt-4.1-mini".to_owned(),
            endpoint_url: Some("https://provider.example.test/probe".to_owned()),
            key_reference: "sk-secret-key-material".to_owned(),
        },
    ];

    for request in invalid_tests {
        let result = test_remote_ai_provider(path_string(repo.path()), request);
        assert_sanitized_error(
            result.expect_err("invalid provider test input must fail"),
            ErrorKind::Config,
        );
        assert_eq!(repo_config_rows(repo.path()), before_rows);
    }

    let token = successful_provider_test(repo.path(), "https://provider.example.test/probe");
    let pending_before =
        repo_config_value(repo.path(), PENDING_TEST_KEY).expect("pending test must exist");

    let mut invalid_scope =
        enable_request_for_endpoint(token.clone(), "https://provider.example.test/probe");
    invalid_scope.feature_scope.clear();
    let result = enable_remote_ai_provider(path_string(repo.path()), invalid_scope);
    assert_sanitized_error(
        result.expect_err("empty feature scope must fail"),
        ErrorKind::Config,
    );

    let mut duplicate_scope =
        enable_request_for_endpoint(token.clone(), "https://provider.example.test/probe");
    duplicate_scope
        .feature_scope
        .push(AiFeatureKind::AutoSummaries);
    let result = enable_remote_ai_provider(path_string(repo.path()), duplicate_scope);
    assert_sanitized_error(
        result.expect_err("duplicate feature scope must fail"),
        ErrorKind::Config,
    );

    let mut no_consent = enable_request_for_endpoint(token, "https://provider.example.test/probe");
    no_consent.data_flow_confirmed = false;
    let result = enable_remote_ai_provider(path_string(repo.path()), no_consent);
    assert_sanitized_error(
        result.expect_err("missing data-flow consent must fail"),
        ErrorKind::Config,
    );

    assert!(repo_config_value(repo.path(), REMOTE_CONFIG_KEY).is_none());
    assert_eq!(
        repo_config_value(repo.path(), PENDING_TEST_KEY),
        Some(pending_before)
    );
}

#[test]
fn remote_provider_config_failure_permission_denied_does_not_leak_key_or_write_state() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());
    let request = RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some("https://provider.example.test/probe".to_owned()),
        key_reference: "secure-storage:env:AREAMATRIX_MISSING_SECRET".to_owned(),
    };

    let result = test_remote_ai_provider(path_string(repo.path()), request);

    assert_sanitized_error(
        result.expect_err("missing credential must fail"),
        ErrorKind::PermissionDenied,
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_failure_provider_rejections_do_not_create_enable_tokens() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());

    for (runtime_status, expected_status) in [
        ("401", RemoteProviderTestStatus::ProviderRejected),
        ("503", RemoteProviderTestStatus::ConnectionFailed),
        ("404", RemoteProviderTestStatus::UnsupportedProvider),
    ] {
        let runtime = ProbeRuntime::new(runtime_status);
        let result = test_remote_ai_provider(
            path_string(repo.path()),
            test_request_for_endpoint("https://provider.example.test/probe"),
        )
        .expect("provider test returns sanitized failure status");
        let _ = runtime.captured_payload();

        assert_eq!(result.status, expected_status);
        assert!(!result.provider_verified);
        assert!(result.verification_token.is_none());
        assert_no_secret_material(&result.sanitized_message);
        assert_eq!(repo_config_rows(repo.path()), before_rows);
    }
}

#[test]
fn remote_provider_config_failure_runtime_or_db_errors_map_to_internal_without_partial_write() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());

    let runtime = ProbeRuntime::new("not-a-status");
    let result = test_remote_ai_provider(
        path_string(repo.path()),
        test_request_for_endpoint("https://provider.example.test/probe"),
    );
    let _ = runtime.captured_payload();
    assert_sanitized_error(
        result.expect_err("invalid probe runtime output must fail"),
        ErrorKind::Internal,
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    install_repo_config_insert_failure(repo.path(), PENDING_TEST_KEY);
    let runtime = ProbeRuntime::new("200");
    let result = test_remote_ai_provider(
        path_string(repo.path()),
        test_request_for_endpoint("https://provider.example.test/db-failure"),
    );
    let _ = runtime.captured_payload();
    assert_sanitized_error(
        result.expect_err("pending verification write failure must fail"),
        ErrorKind::Internal,
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_failure_enable_rollback_preserves_previous_successful_state() {
    let repo = initialized_repo();

    let first_endpoint = "https://provider.example.test/first";
    let first_token = successful_provider_test(repo.path(), first_endpoint);
    let first_snapshot = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(first_token, first_endpoint),
    )
    .expect("enable first provider");
    assert!(first_snapshot.remote_provider_enabled);
    let stored_before =
        repo_config_value(repo.path(), REMOTE_CONFIG_KEY).expect("first provider config stored");

    let second_endpoint = "https://provider.example.test/second";
    let second_token = successful_provider_test(repo.path(), second_endpoint);
    let pending_before =
        repo_config_value(repo.path(), PENDING_TEST_KEY).expect("second pending test stored");
    install_repo_config_update_failure(repo.path(), REMOTE_CONFIG_KEY);

    let result = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(second_token, second_endpoint),
    );

    assert_sanitized_error(
        result.expect_err("provider config update failure must fail"),
        ErrorKind::Internal,
    );
    assert_eq!(
        repo_config_value(repo.path(), REMOTE_CONFIG_KEY),
        Some(stored_before)
    );
    assert_eq!(
        repo_config_value(repo.path(), PENDING_TEST_KEY),
        Some(pending_before)
    );

    for user_file in ["README.md", "AREAMATRIX.md"] {
        let path = repo.path().join(user_file);
        fs::write(&path, format!("user-owned {user_file}\n")).expect("write user-owned file");
        assert_eq!(
            fs::read_to_string(&path).expect("read user-owned file"),
            format!("user-owned {user_file}\n")
        );
    }
}

#[test]
fn remote_provider_config_failure_disable_rollback_preserves_previous_successful_state() {
    let repo = initialized_repo();
    let endpoint = "https://provider.example.test/disable-rollback";
    let token = successful_provider_test(repo.path(), endpoint);
    let enabled = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(token, endpoint),
    )
    .expect("enable provider before disable rollback");
    assert!(enabled.remote_provider_enabled);
    let stored_before =
        repo_config_value(repo.path(), REMOTE_CONFIG_KEY).expect("provider config stored");

    install_repo_config_update_failure(repo.path(), REMOTE_CONFIG_KEY);
    let result = disable_remote_ai_provider(
        path_string(repo.path()),
        RemoteProviderDisableRequest {
            remove_stored_credential: true,
        },
    );

    assert_sanitized_error(
        result.expect_err("disable update failure must fail"),
        ErrorKind::Internal,
    );
    assert_eq!(
        repo_config_value(repo.path(), REMOTE_CONFIG_KEY),
        Some(stored_before)
    );

    let loaded = load_remote_ai_provider_config(path_string(repo.path()))
        .expect("load previous successful provider state");
    assert!(loaded.provider_configured);
    assert!(loaded.provider_verified);
    assert!(loaded.remote_provider_enabled);
    assert!(loaded.credential_configured);
}

#[test]
fn remote_provider_config_failure_error_mapping_is_structured_and_side_effect_free() {
    let repo = initialized_repo();
    let rows_before = repo_config_rows(repo.path());

    let config_mapping = map_core_error(area_matrix_core::ErrorMappingInput {
        kind: ErrorKind::Config,
        path: None,
        reason: Some("remote provider feature scope is required".to_owned()),
        message: None,
    });
    assert_eq!(config_mapping.severity, ErrorSeverity::Medium);
    assert_eq!(
        config_mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let permission_mapping = map_core_error(area_matrix_core::ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("remote provider credential".to_owned()),
        reason: None,
        message: None,
    });
    assert_eq!(permission_mapping.severity, ErrorSeverity::High);
    assert_eq!(
        permission_mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let internal_mapping = map_core_error(area_matrix_core::ErrorMappingInput {
        kind: ErrorKind::Internal,
        path: None,
        reason: None,
        message: Some("remote provider metadata persistence failed".to_owned()),
    });
    assert_eq!(internal_mapping.severity, ErrorSeverity::Critical);
    assert_eq!(internal_mapping.recoverability, ErrorRecoverability::Fatal);

    assert_eq!(repo_config_rows(repo.path()), rows_before);
}

fn install_repo_config_insert_failure(repo: &Path, key: &str) {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .execute_batch(&format!(
            "CREATE TRIGGER fail_remote_provider_insert
             BEFORE INSERT ON repo_config
             WHEN NEW.key = '{}'
             BEGIN
               SELECT RAISE(ABORT, 'forced remote provider insert failure');
             END;",
            key
        ))
        .expect("install insert failure trigger");
}

fn install_repo_config_update_failure(repo: &Path, key: &str) {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .execute_batch(&format!(
            "CREATE TRIGGER fail_remote_provider_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = '{}'
             BEGIN
               SELECT RAISE(ABORT, 'forced remote provider update failure');
             END;",
            key
        ))
        .expect("install update failure trigger");
}
