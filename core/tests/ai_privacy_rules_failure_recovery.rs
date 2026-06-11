#[path = "support/remote_provider_config_common.rs"]
mod remote_provider_common;

use std::{fs, path::Path};

use area_matrix_core::{
    enable_remote_ai_provider, evaluate_ai_privacy, list_ai_privacy_rules, map_core_error,
    test_remote_ai_provider, update_ai_privacy_rules, AiFeatureKind, AiPrivacyDecision,
    AiPrivacyEvaluationContext, AiPrivacyEvaluationRequest, AiPrivacyEvaluationRoute,
    AiPrivacyFieldRule, AiPrivacyInputField, AiPrivacyProviderGateReason,
    AiPrivacyProviderScopeSnapshot, AiPrivacyRuleAppliesTo, AiPrivacyRuleInput, AiPrivacyRuleKind,
    AiPrivacyRulesUpdateRequest, AiPrivacySkippedReason, CoreError, ErrorKind, ErrorMappingInput,
    ErrorRecoverability, ErrorSeverity,
};
use pretty_assertions::assert_eq;
use remote_provider_common::{
    enable_request_for_endpoint, initialized_repo, path_string, test_request_for_endpoint,
    ProbeRuntime, SECRET_VALUE, TEST_SECRET_ENV,
};
use rusqlite::{params, Connection, OptionalExtension};

const AI_PRIVACY_RULES_KEY: &str = "ai_privacy_rules";

#[derive(Debug, Eq, PartialEq)]
struct PrivacyFailureSnapshot {
    repo_config_rows: Vec<(String, String)>,
    user_visible_paths: Vec<String>,
}

fn input_fields() -> Vec<AiPrivacyInputField> {
    vec![
        AiPrivacyInputField::FileName,
        AiPrivacyInputField::RepoRelativePath,
        AiPrivacyInputField::Extension,
        AiPrivacyInputField::ExtractedTextExcerpt,
        AiPrivacyInputField::AiSummary,
        AiPrivacyInputField::NoteSummary,
        AiPrivacyInputField::TagCategoryContext,
    ]
}

fn field_rules(allowed: &[AiPrivacyInputField]) -> Vec<AiPrivacyFieldRule> {
    input_fields()
        .into_iter()
        .map(|field| AiPrivacyFieldRule {
            allow_remote: allowed.contains(&field),
            field,
        })
        .collect()
}

fn disabled_provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: false,
        provider_verified: false,
        remote_provider_enabled: false,
        feature_scope: Vec::new(),
    }
}

fn folder_rule() -> AiPrivacyRuleInput {
    AiPrivacyRuleInput {
        rule_id: Some("rule:private-folder".to_owned()),
        name: "Private folder".to_owned(),
        kind: AiPrivacyRuleKind::Folder,
        pattern: "finance/private/".to_owned(),
        applies_to: AiPrivacyRuleAppliesTo::RemoteAi,
        enabled: true,
        description: Some("Keep private files out of AI".to_owned()),
    }
}

fn baseline_request() -> AiPrivacyRulesUpdateRequest {
    AiPrivacyRulesUpdateRequest {
        privacy_gate_enabled: false,
        rules: vec![folder_rule()],
        remote_allowed_fields: field_rules(&[AiPrivacyInputField::FileName]),
        provider_scope: disabled_provider_scope(),
        confirmed: true,
    }
}

fn evaluation_request() -> AiPrivacyEvaluationRequest {
    AiPrivacyEvaluationRequest {
        feature: AiFeatureKind::AutoSummaries,
        route: AiPrivacyEvaluationRoute::Remote,
        requested_fields: vec![
            AiPrivacyInputField::FileName,
            AiPrivacyInputField::ExtractedTextExcerpt,
        ],
        privacy_gate_enabled: false,
        provider_scope: disabled_provider_scope(),
        rules: Vec::new(),
        remote_allowed_fields: field_rules(&[AiPrivacyInputField::FileName]),
        context: AiPrivacyEvaluationContext {
            file_id: Some(42),
            repo_relative_path: Some("finance/private/report.pdf".to_owned()),
            file_name: Some("report.pdf".to_owned()),
            category: Some("finance".to_owned()),
            extension: Some(".pdf".to_owned()),
            tags: vec!["client-private".to_owned()],
        },
    }
}

fn snapshot(repo: &Path) -> PrivacyFailureSnapshot {
    PrivacyFailureSnapshot {
        repo_config_rows: repo_config_rows(repo),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn repo_config_rows(repo: &Path) -> Vec<(String, String)> {
    let db_path = repo.join(".areamatrix/index.db");
    if !db_path.exists() {
        return Vec::new();
    }
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT key, value FROM repo_config ORDER BY key")
        .expect("prepare repo_config rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query repo_config rows")
        .map(|row| row.expect("read repo_config row"))
        .collect()
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    let db_path = repo.join(".areamatrix/index.db");
    if !db_path.exists() {
        return None;
    }
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn assert_no_secret_material(value: &str) {
    for fragment in [
        SECRET_VALUE,
        TEST_SECRET_ENV,
        "sk-secret",
        "api_key",
        "token=",
        "Bearer",
        "secure-storage:",
        "keychain:",
    ] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

fn assert_error_kind(error: CoreError, kind: ErrorKind) -> CoreError {
    assert_eq!(error.kind(), kind);
    assert_eq!(error.to_error_mapping().kind, kind);
    assert_no_secret_material(&error.to_string());
    assert_no_secret_material(error.raw_context());
    error
}

fn install_privacy_update_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_ai_privacy_rules_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = 'ai_privacy_rules'
             BEGIN
               SELECT RAISE(ABORT, 'database is locked');
             END;",
        )
        .expect("install privacy rules update failure trigger");
}

#[test]
fn ai_privacy_rules_failure_empty_state_is_default_off_and_side_effect_free() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let before = snapshot(repo.path());

    let listed = list_ai_privacy_rules(path_string(repo.path())).expect("load empty privacy rules");
    let evaluated =
        evaluate_ai_privacy(path_string(repo.path()), evaluation_request()).expect("evaluate gate");

    assert!(!listed.privacy_gate_enabled);
    assert!(listed.remote_blocked_by_default);
    assert!(listed.rules.is_empty());
    assert!(listed
        .remote_allowed_fields
        .iter()
        .all(|field| { !field.allow_remote && field.last_matched_count == 0 }));
    assert!(!listed.provider_scope.provider_configured);
    assert_eq!(evaluated.decision, AiPrivacyDecision::Skipped);
    assert_eq!(
        evaluated.provider_gate_reason,
        Some(AiPrivacyProviderGateReason::PrivacyGateDisabled)
    );
    assert_eq!(
        evaluated.skipped_reason,
        Some(AiPrivacySkippedReason::PrivacyGateDisabled)
    );
    assert!(evaluated.sent_fields.is_empty());
    assert!(!repo.path().join(".areamatrix").exists());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_privacy_rules_failure_invalid_inputs_are_config_and_non_mutating() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    update_ai_privacy_rules(path_string(repo.path()), baseline_request())
        .expect("persist baseline privacy rules");
    let before = snapshot(repo.path());

    assert_error_kind(
        list_ai_privacy_rules(String::new()).expect_err("empty path must fail"),
        ErrorKind::Config,
    );

    let mut unconfirmed = baseline_request();
    unconfirmed.confirmed = false;
    assert_error_kind(
        update_ai_privacy_rules(path_string(repo.path()), unconfirmed)
            .expect_err("missing confirmation must fail"),
        ErrorKind::Config,
    );

    let mut missing_field = baseline_request();
    missing_field.remote_allowed_fields.pop();
    assert_error_kind(
        update_ai_privacy_rules(path_string(repo.path()), missing_field)
            .expect_err("missing field rule must fail"),
        ErrorKind::Config,
    );

    let mut invalid_context = evaluation_request();
    invalid_context.context.repo_relative_path = Some("../private/sk-secret.txt".to_owned());
    assert_error_kind(
        evaluate_ai_privacy(path_string(repo.path()), invalid_context)
            .expect_err("unsafe relative path must fail"),
        ErrorKind::Config,
    );

    assert_eq!(snapshot(repo.path()), before);
}

#[cfg(unix)]
#[test]
fn ai_privacy_rules_failure_permission_denied_is_structured_and_non_mutating() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    update_ai_privacy_rules(path_string(repo.path()), baseline_request())
        .expect("persist baseline privacy rules");
    let before = snapshot(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let update_error = {
        let _guard = ReadOnlyGuard::new(&db_path, 0o444);
        update_ai_privacy_rules(path_string(repo.path()), baseline_request())
            .expect_err("readonly metadata must fail")
    };

    let error = assert_error_kind(update_error, ErrorKind::PermissionDenied);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_privacy_rules_failure_io_error_preserves_user_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(
        repo.path().join(".areamatrix"),
        "not a metadata directory\n",
    )
    .expect("write malformed metadata marker");
    let before = snapshot(repo.path());

    let error = list_ai_privacy_rules(path_string(repo.path()))
        .expect_err("malformed metadata path must fail");

    assert_error_kind(error, ErrorKind::Io);
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
        "user readme\n"
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_privacy_rules_failure_db_abort_rolls_back_to_previous_snapshot() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    update_ai_privacy_rules(path_string(repo.path()), baseline_request())
        .expect("persist baseline privacy rules");
    let before = snapshot(repo.path());
    let before_payload =
        repo_config_value(repo.path(), AI_PRIVACY_RULES_KEY).expect("baseline payload");
    install_privacy_update_failure(repo.path());

    let mut changed = baseline_request();
    changed.rules = Vec::new();
    let error = update_ai_privacy_rules(path_string(repo.path()), changed)
        .expect_err("database abort must fail");

    assert_error_kind(error, ErrorKind::Db);
    assert_eq!(
        repo_config_value(repo.path(), AI_PRIVACY_RULES_KEY).expect("payload after abort"),
        before_payload
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_privacy_rules_failure_corrupt_payload_is_not_silent_default() {
    let repo = initialized_repo();
    update_ai_privacy_rules(path_string(repo.path()), baseline_request())
        .expect("persist baseline privacy rules");
    let before_paths = user_visible_paths(repo.path());
    open_db(repo.path())
        .execute(
            "UPDATE repo_config SET value = 'not-json' WHERE key = ?1",
            params![AI_PRIVACY_RULES_KEY],
        )
        .expect("corrupt privacy metadata");

    let error =
        list_ai_privacy_rules(path_string(repo.path())).expect_err("corrupt metadata must fail");

    assert_error_kind(error, ErrorKind::Config);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn ai_privacy_rules_failure_error_mapping_matches_documented_codes() {
    for (kind, severity, recoverability) in [
        (
            ErrorKind::Config,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::Db,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::Io,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
    ] {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("repository metadata".to_owned()),
            reason: Some("AI privacy failure edge".to_owned()),
            message: Some("AI privacy metadata unavailable".to_owned()),
        });
        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
    }

    let locked = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Db,
        path: None,
        reason: None,
        message: Some("database is locked".to_owned()),
    });
    assert_eq!(locked.recoverability, ErrorRecoverability::Retryable);
}

#[test]
fn ai_privacy_rules_failure_provider_keys_never_surface_through_c3_09() {
    let repo = initialized_repo();
    let endpoint = "https://provider.example.test/privacy";
    let runtime = ProbeRuntime::new("200");
    let tested = test_remote_ai_provider(
        path_string(repo.path()),
        test_request_for_endpoint(endpoint),
    )
    .expect("test remote provider");
    let _ = runtime.captured_payload();
    enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(
            tested
                .verification_token
                .expect("successful test returns token"),
            endpoint,
        ),
    )
    .expect("enable remote provider");

    let snapshot =
        list_ai_privacy_rules(path_string(repo.path())).expect("load provider privacy scope");
    assert!(snapshot.provider_scope.provider_configured);
    assert!(snapshot.provider_scope.provider_verified);
    assert!(snapshot.provider_scope.remote_provider_enabled);
    assert_no_secret_material(
        &serde_json::to_string(&snapshot).expect("serialize privacy snapshot"),
    );

    let mut request = baseline_request();
    request.privacy_gate_enabled = true;
    request.provider_scope = snapshot.provider_scope.clone();
    let updated = update_ai_privacy_rules(path_string(repo.path()), request)
        .expect("enable privacy gate without exposing provider key");
    assert_no_secret_material(
        &serde_json::to_string(&updated).expect("serialize updated privacy snapshot"),
    );
}

#[cfg(unix)]
struct ReadOnlyGuard {
    path: std::path::PathBuf,
    original_mode: u32,
}

#[cfg(unix)]
impl ReadOnlyGuard {
    fn new(path: &Path, mode: u32) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let metadata = fs::metadata(path).expect("read metadata permissions");
        let original_mode = metadata.permissions().mode();
        let mut permissions = metadata.permissions();
        permissions.set_mode(mode);
        fs::set_permissions(path, permissions).expect("set readonly permissions");
        Self {
            path: path.to_path_buf(),
            original_mode,
        }
    }
}

#[cfg(unix)]
impl Drop for ReadOnlyGuard {
    fn drop(&mut self) {
        use std::os::unix::fs::PermissionsExt;

        let mut permissions = fs::metadata(&self.path)
            .expect("read metadata permissions")
            .permissions();
        permissions.set_mode(self.original_mode);
        fs::set_permissions(&self.path, permissions).expect("restore permissions");
    }
}
