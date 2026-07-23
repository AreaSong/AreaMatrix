#![allow(dead_code)]

use std::path::Path;

use area_matrix_core::{
    complete_remote_ai_provider_probe, init_repo, prepare_remote_ai_provider_probe, AiFeatureKind,
    CoreResult, OverviewOutput, RemoteAiProviderKind, RemoteProviderEnableRequest,
    RemoteProviderProbeObservation, RemoteProviderProbeOutcome, RemoteProviderTestRequest,
    RemoteProviderTestResult, RepoInitMode, RepoInitOptions,
};
use rusqlite::{params, Connection, OptionalExtension};

pub const SECRET_VALUE: &str = "test-provider-secret";

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

pub fn test_request() -> RemoteProviderTestRequest {
    test_request_for_endpoint("https://provider.example.test/probe")
}

pub fn test_request_for_endpoint(endpoint_url: &str) -> RemoteProviderTestRequest {
    test_request_with_key_reference(endpoint_url, test_key_reference())
}

pub fn test_request_with_key_reference(
    endpoint_url: &str,
    key_reference: String,
) -> RemoteProviderTestRequest {
    RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference,
    }
}

pub fn enable_request(verification_token: String) -> RemoteProviderEnableRequest {
    enable_request_for_endpoint(verification_token, "https://provider.example.test/probe")
}

pub fn enable_request_for_endpoint(
    verification_token: String,
    endpoint_url: &str,
) -> RemoteProviderEnableRequest {
    enable_request_with_key_reference(verification_token, endpoint_url, test_key_reference())
}

pub fn enable_request_with_key_reference(
    verification_token: String,
    endpoint_url: &str,
    key_reference: String,
) -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference,
        feature_scope: vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags],
        verification_token,
        data_flow_confirmed: true,
    }
}

pub fn test_key_reference() -> String {
    "keychain:areamatrix-remote-openai".to_owned()
}

pub fn keychain_reference() -> String {
    "keychain:areamatrix-remote-openai".to_owned()
}

pub fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

pub fn repo_config_rows(repo: &Path) -> Vec<(String, String)> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key, value FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .expect("query repo_config rows");

    rows.map(|row| row.expect("read repo_config row")).collect()
}

pub fn complete_provider_test(
    repo_path: String,
    request: RemoteProviderTestRequest,
    outcome: RemoteProviderProbeOutcome,
    http_status: Option<u32>,
) -> CoreResult<RemoteProviderTestResult> {
    let plan = prepare_remote_ai_provider_probe(repo_path.clone(), request)?;
    complete_remote_ai_provider_probe(
        repo_path,
        RemoteProviderProbeObservation {
            probe_token: plan.probe_token,
            outcome,
            http_status,
        },
    )
}

pub fn successful_provider_test(
    repo_path: String,
    request: RemoteProviderTestRequest,
) -> CoreResult<RemoteProviderTestResult> {
    complete_provider_test(
        repo_path,
        request,
        RemoteProviderProbeOutcome::HttpResponse,
        Some(200),
    )
}
