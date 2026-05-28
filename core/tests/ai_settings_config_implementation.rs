use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_ai_config, load_config, update_ai_config, AiConfig, AiFeatureConfig,
    AiFeatureKind, AiProviderPreference, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn feature_toggles() -> Vec<AiFeatureConfig> {
    vec![
        AiFeatureConfig {
            feature: AiFeatureKind::ClassificationSuggestions,
            enabled: true,
            allow_remote: false,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::AutoSummaries,
            enabled: true,
            allow_remote: true,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::AutoTags,
            enabled: false,
            allow_remote: true,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::SemanticSearch,
            enabled: true,
            allow_remote: true,
        },
    ]
}

fn ai_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: AiProviderPreference::RemoteFirst,
        local_ai_enabled: true,
        remote_ai_allowed: true,
        privacy_gate_enabled: true,
        privacy_policy_ref: Some("default-remote-gate".to_owned()),
        feature_toggles: feature_toggles(),
    }
}

fn repo_config_rows(repo: &Path) -> Vec<(String, String, i64)> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key, value, updated_at FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .expect("query repo_config rows");

    rows.map(|row| row.expect("read repo_config row")).collect()
}

#[test]
fn ai_settings_config_implementation_persists_and_reloads_config_snapshot() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let config = ai_config(repo_path.clone());

    let updated =
        update_ai_config(repo_path.clone(), config.clone()).expect("persist AI configuration");
    let reloaded = load_ai_config(repo_path.clone()).expect("reload AI configuration");

    assert_eq!(updated, reloaded);
    assert_eq!(reloaded.config, config);
    assert!(reloaded.updated_at.is_some());
    let summaries = reloaded
        .capabilities
        .iter()
        .find(|state| state.feature == AiFeatureKind::AutoSummaries)
        .expect("auto summaries capability exists");
    assert!(summaries.enabled);
    assert!(summaries.local_allowed);
    assert!(summaries.remote_allowed);

    let repo_config = load_config(repo_path).expect("load repository config");
    assert!(repo_config.ai_enabled);
}

#[test]
fn ai_settings_config_implementation_requires_initialized_metadata_for_update_only() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let repo_path = path_string(repo.path());

    let default_snapshot =
        load_ai_config(repo_path.clone()).expect("load default AI config without metadata");
    assert!(!default_snapshot.config.ai_enabled);
    assert!(!repo.path().join(".areamatrix").exists());

    let result = update_ai_config(repo_path.clone(), ai_config(repo_path));

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn ai_settings_config_implementation_rejects_invalid_payload_without_partial_write() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let before = load_ai_config(repo_path.clone()).expect("load initial AI config");
    let before_rows = repo_config_rows(repo.path());

    let mut invalid = ai_config(repo_path.clone());
    invalid.privacy_policy_ref = Some("  ".to_owned());
    let result = update_ai_config(repo_path.clone(), invalid);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(
        load_ai_config(repo_path).expect("reload after rejected payload"),
        before
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn ai_settings_config_implementation_rolls_back_when_late_write_fails() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let before = load_ai_config(repo_path.clone()).expect("load initial AI config");
    let before_rows = repo_config_rows(repo.path());
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute_batch(
            "CREATE TRIGGER fail_ai_enabled_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = 'ai_enabled'
             BEGIN
               SELECT RAISE(ABORT, 'forced AI enabled write failure');
             END;",
        )
        .expect("install failing AI config trigger");
    drop(connection);

    let result = update_ai_config(repo_path.clone(), ai_config(repo_path.clone()));

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(
        load_ai_config(repo_path).expect("reload after rollback"),
        before
    );
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn ai_settings_config_implementation_preserves_user_files_and_remote_secret_boundaries() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");

    update_ai_config(
        path_string(repo.path()),
        ai_config(path_string(repo.path())),
    )
    .expect("persist AI configuration");

    assert_eq!(
        fs::read_to_string(&readme_path).expect("read README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&overview_path).expect("read AREAMATRIX"),
        "user overview\n"
    );
    for path in [
        repo.path().join(".areamatrix/remote"),
        repo.path().join(".areamatrix/secrets"),
        repo.path().join(".areamatrix/ai_call_log"),
        repo.path().join(".areamatrix/generated/ai_config.json"),
    ] {
        assert!(!path.exists(), "C3-01 must not create {}", path.display());
    }
}
