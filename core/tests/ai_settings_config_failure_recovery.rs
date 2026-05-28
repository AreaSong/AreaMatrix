use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_ai_config, update_ai_config, AiConfig, AiFeatureConfig, AiFeatureKind,
    AiProviderPreference, CoreError, ErrorKind, ErrorRecoverability, ErrorSeverity, OverviewOutput,
    RepoInitMode, RepoInitOptions,
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
            enabled: true,
            allow_remote: false,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::SemanticSearch,
            enabled: false,
            allow_remote: false,
        },
    ]
}

fn ai_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: AiProviderPreference::LocalFirst,
        local_ai_enabled: true,
        remote_ai_allowed: false,
        privacy_gate_enabled: false,
        privacy_policy_ref: Some("policy:default".to_owned()),
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

fn assert_no_remote_ai_side_effects(repo: &Path) {
    for path in [
        repo.join(".areamatrix/remote"),
        repo.join(".areamatrix/secrets"),
        repo.join(".areamatrix/ai_call_log"),
        repo.join(".areamatrix/generated/ai_config.json"),
    ] {
        assert!(!path.exists(), "C3-01 must not create {}", path.display());
    }
}

#[test]
fn ai_settings_failure_recovery_default_off_is_empty_state_without_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    let snapshot = load_ai_config(path_string(repo.path())).expect("load default AI config");

    assert!(!snapshot.config.ai_enabled);
    assert!(!snapshot.config.remote_ai_allowed);
    assert!(snapshot.config.privacy_policy_ref.is_none());
    assert!(snapshot.capabilities.iter().all(|state| !state.enabled));
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read user README"),
        "user readme\n"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn ai_settings_failure_recovery_rejects_invalid_paths_and_secrets_without_leaking() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let baseline = ai_config(repo_path.clone());
    update_ai_config(repo_path.clone(), baseline.clone()).expect("persist baseline AI config");
    let before_rows = repo_config_rows(repo.path());

    let metadata_path = repo.path().join(".areamatrix");
    let result = load_ai_config(path_string(&metadata_path));
    assert!(matches!(result, Err(CoreError::Config { .. })));

    let mut secret_payload = baseline;
    secret_payload.privacy_policy_ref = Some("sk-secret-value-that-must-not-leak".to_owned());
    let error = update_ai_config(repo_path.clone(), secret_payload)
        .expect_err("secret-like privacy reference must fail");

    assert_eq!(error.kind(), ErrorKind::Config);
    assert!(!error.raw_context().contains("sk-secret-value"));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Config);
    assert_eq!(repo_config_rows(repo.path()), before_rows);
    assert_eq!(
        load_ai_config(repo_path).expect("reload baseline after rejected secret"),
        load_ai_config(path_string(repo.path())).expect("reload baseline for comparison")
    );
    assert_no_remote_ai_side_effects(repo.path());
}

#[test]
fn ai_settings_failure_recovery_corrupt_persisted_payload_is_not_silently_downgraded() {
    let repo = initialized_repo();
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute(
            "INSERT INTO repo_config (key, value, updated_at)
             VALUES ('ai_config', 'not-json', strftime('%s', 'now'))",
            [],
        )
        .expect("insert corrupt persisted AI config");

    let error = load_ai_config(path_string(repo.path()))
        .expect_err("corrupt persisted AI config must not fall back to defaults");

    assert_eq!(error.kind(), ErrorKind::Config);
    assert_eq!(error.raw_context(), "AI config metadata is invalid");
    assert_eq!(error.to_error_mapping().severity, ErrorSeverity::Medium);
}

#[test]
fn ai_settings_failure_recovery_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone()))
        .expect("persist baseline AI config");
    let before_rows = repo_config_rows(repo.path());

    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o555);
    fs::set_permissions(&metadata_dir, blocked_permissions).expect("make metadata read-only");
    let update_error = update_ai_config(repo_path.clone(), ai_config(repo_path.clone()))
        .expect_err("read-only metadata must reject AI config update");
    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");

    let db_path = repo.path().join(".areamatrix/index.db");
    let original_db_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    let mut unreadable_permissions = original_db_permissions.clone();
    unreadable_permissions.set_mode(0o200);
    fs::set_permissions(&db_path, unreadable_permissions).expect("make database unreadable");
    let load_error =
        load_ai_config(repo_path.clone()).expect_err("unreadable metadata must reject load");
    fs::set_permissions(&db_path, original_db_permissions).expect("restore database permissions");

    for error in [update_error, load_error] {
        assert_eq!(error.kind(), ErrorKind::PermissionDenied);
        let mapping = error.to_error_mapping();
        assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
        assert_eq!(
            mapping.recoverability,
            ErrorRecoverability::UserActionRequired
        );
    }
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn ai_settings_failure_recovery_io_error_preserves_user_files_and_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let repo_path = path_string(repo.path());
    let readme_path = repo.path().join("README.md");
    let metadata_path = repo.path().join(".areamatrix");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&metadata_path, "not a metadata directory\n").expect("write malformed metadata");

    let error = update_ai_config(repo_path.clone(), ai_config(repo_path))
        .expect_err("malformed metadata path must fail");

    assert_eq!(error.kind(), ErrorKind::Io);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Retryable
    );
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read user README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&metadata_path).expect("read malformed metadata marker"),
        "not a metadata directory\n"
    );
    assert_no_remote_ai_side_effects(repo.path());
}

#[test]
fn ai_settings_failure_recovery_db_abort_rolls_back_partial_config_rows() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
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
        .expect("install failing AI settings trigger");

    let error = update_ai_config(repo_path, ai_config(path_string(repo.path())))
        .expect_err("late database write failure must roll back the transaction");

    assert_eq!(error.kind(), ErrorKind::Config);
    assert_eq!(error.raw_context(), "AI config metadata persistence failed");
    assert_eq!(repo_config_rows(repo.path()), before_rows);
    assert_no_remote_ai_side_effects(repo.path());
}
