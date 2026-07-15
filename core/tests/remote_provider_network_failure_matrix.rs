#[path = "support/remote_provider_config_common.rs"]
mod common;

use area_matrix_core::{
    complete_remote_ai_provider_probe, prepare_remote_ai_provider_probe, CoreError, ErrorKind,
    RemoteProviderProbeObservation, RemoteProviderProbeOutcome, RemoteProviderTestStatus,
};
use common::{complete_provider_test, initialized_repo, path_string, test_request_for_endpoint};

#[test]
fn sanitized_http_statuses_map_to_public_probe_states() {
    for (http_status, expected_status) in [
        (200, RemoteProviderTestStatus::Succeeded),
        (401, RemoteProviderTestStatus::ProviderRejected),
        (503, RemoteProviderTestStatus::ConnectionFailed),
        (404, RemoteProviderTestStatus::UnsupportedProvider),
        (302, RemoteProviderTestStatus::UnsupportedProvider),
    ] {
        let repo = initialized_repo();
        let result = complete_provider_test(
            path_string(repo.path()),
            test_request_for_endpoint("https://provider.example.test/probe"),
            RemoteProviderProbeOutcome::HttpResponse,
            Some(http_status),
        )
        .expect("sanitized HTTP status should return a probe result");

        assert_eq!(result.status, expected_status);
        assert_eq!(
            result.provider_verified,
            expected_status == RemoteProviderTestStatus::Succeeded
        );
    }
}

#[test]
fn platform_transport_failure_maps_to_connection_failed() {
    let repo = initialized_repo();
    let result = complete_provider_test(
        path_string(repo.path()),
        test_request_for_endpoint("https://provider.example.test/probe"),
        RemoteProviderProbeOutcome::ConnectionFailed,
        None,
    )
    .expect("transport failure should return a sanitized result");

    assert_eq!(result.status, RemoteProviderTestStatus::ConnectionFailed);
    assert!(!result.provider_verified);
    assert!(result.verification_token.is_none());
}

#[test]
fn unavailable_platform_credential_maps_to_permission_denied() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let plan = prepare_remote_ai_provider_probe(
        repo_path.clone(),
        test_request_for_endpoint("https://provider.example.test/probe"),
    )
    .expect("prepare provider probe");

    let error = complete_remote_ai_provider_probe(
        repo_path,
        RemoteProviderProbeObservation {
            probe_token: plan.probe_token,
            outcome: RemoteProviderProbeOutcome::CredentialUnavailable,
            http_status: None,
        },
    )
    .expect_err("unavailable credential should fail");

    assert_eq!(error.kind(), ErrorKind::PermissionDenied);
    assert!(!error.to_string().contains("keychain:"));
}

#[test]
fn malformed_platform_observation_is_rejected_without_verification() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let plan = prepare_remote_ai_provider_probe(
        repo_path.clone(),
        test_request_for_endpoint("https://provider.example.test/probe"),
    )
    .expect("prepare provider probe");

    let error = complete_remote_ai_provider_probe(
        repo_path,
        RemoteProviderProbeObservation {
            probe_token: plan.probe_token,
            outcome: RemoteProviderProbeOutcome::HttpResponse,
            http_status: None,
        },
    )
    .expect_err("HTTP response without status should fail");

    assert!(matches!(error, CoreError::Config { .. }));
}
