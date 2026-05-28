#![allow(dead_code)]

use std::{fs, path::Path};

use area_matrix_core::{
    enable_remote_ai_provider, import_file, init_repo, test_remote_ai_provider, update_ai_config,
    AiConfig, AiFeatureConfig, AiFeatureKind, AiProviderPreference, AiTagSuggestionRequest,
    ApplyAiTagSuggestionItem, ApplyAiTagSuggestionsRequest, CoreError, DuplicateStrategy,
    ErrorKind, ImportDestination, ImportOptions, OverviewOutput, RemoteAiProviderKind,
    RemoteProviderEnableRequest, RemoteProviderTestRequest, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

pub(crate) fn import_fixture(repo: &Path, name: &str, content: &str) -> i64 {
    let source_dir = repo.join("fixtures");
    fs::create_dir_all(&source_dir).expect("create fixture source directory");
    let source = source_dir.join(name);
    fs::write(&source, content).expect("write fixture source");
    import_file(path_string(repo), path_string(&source), import_options())
        .expect("import fixture file")
        .id
}

fn import_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

pub(crate) fn enable_local_tags(repo: &Path) {
    let repo_path = path_string(repo);
    update_ai_config(repo_path.clone(), ai_config(repo_path, false)).expect("enable local AI tags");
}

fn ai_config(repo_path: String, remote: bool) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: if remote {
            AiProviderPreference::RemoteFirst
        } else {
            AiProviderPreference::LocalFirst
        },
        local_ai_enabled: !remote,
        remote_ai_allowed: remote,
        privacy_gate_enabled: true,
        privacy_policy_ref: None,
        feature_toggles: vec![
            AiFeatureConfig {
                feature: AiFeatureKind::ClassificationSuggestions,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoSummaries,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoTags,
                enabled: true,
                allow_remote: remote,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::SemanticSearch,
                enabled: false,
                allow_remote: false,
            },
        ],
    }
}

pub(crate) fn request(file_id: i64) -> AiTagSuggestionRequest {
    AiTagSuggestionRequest {
        file_id,
        candidate_tags: vec!["finance".to_owned(), "invoice".to_owned()],
        privacy_policy_ref: None,
    }
}

pub(crate) fn apply_request(file_id: i64, slug: &str) -> ApplyAiTagSuggestionsRequest {
    ApplyAiTagSuggestionsRequest {
        file_id,
        suggestions: vec![ApplyAiTagSuggestionItem {
            suggestion_id: format!("ai-tag:{slug}"),
            slug: slug.to_owned(),
            display_name: slug.to_owned(),
            confidence: 0.91,
            edited_by_user: false,
            merge_target_slug: None,
        }],
        call_log_id: None,
        privacy_rule_id: None,
        confirmed: true,
    }
}

pub(crate) fn ai_call_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master
             WHERE type = 'table' AND name = 'ai_call_log'",
            [],
            |row| row.get(0),
        )
        .expect("query AI call log table presence")
}

pub(crate) fn tag_rows(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tag query");
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

pub(crate) fn change_log_kinds(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT detail_json FROM change_log ORDER BY id")
        .expect("prepare change log query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(0)?;
            let value: serde_json::Value =
                serde_json::from_str(&detail).expect("parse change detail");
            Ok(value["kind"].as_str().unwrap_or_default().to_owned())
        })
        .expect("query change log")
        .map(|row| row.expect("read change log row"))
        .collect()
}

pub(crate) fn undo_action_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM undo_actions", [], |row| row.get(0))
        .expect("count undo actions")
}

pub(crate) fn snapshot(repo: &Path) -> Snapshot {
    Snapshot {
        tags: tag_rows(repo),
        change_log_kinds: change_log_kinds(repo),
        undo_actions: undo_action_count(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct Snapshot {
    pub(crate) tags: Vec<String>,
    change_log_kinds: Vec<String>,
    undo_actions: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    pub(crate) user_visible_paths: Vec<String>,
}

pub(crate) fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn relative_directory_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_relative_paths(repo, root, &mut entries);
    }
    entries.sort();
    entries
}

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        paths.push(relative_path(repo, &path));
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = relative_path(repo, &path);
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path is inside repository")
        .to_string_lossy()
        .into_owned()
}

pub(crate) fn assert_kind<T: std::fmt::Debug>(
    result: Result<T, CoreError>,
    kind: ErrorKind,
) -> CoreError {
    let error = result.expect_err("operation should fail");
    assert_eq!(error.kind(), kind);
    assert_eq!(error.to_error_mapping().kind, kind);
    assert_no_secret_material(&error.to_string());
    assert_no_secret_material(error.raw_context());
    error
}

pub(crate) fn assert_no_secret_material(value: &str) {
    for fragment in [
        "sk-secret",
        "secret-key",
        "api_key",
        "apikey",
        "bearer",
        "token=hidden",
        "remote-provider-secret",
        "secure-storage:",
    ] {
        assert!(
            !value.to_ascii_lowercase().contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

pub(crate) fn ai_call_log_text(repo: &Path) -> String {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(route, ''), COALESCE(provider, ''), COALESCE(model, ''),
                    sent_fields_json, COALESCE(privacy_rule_id, ''), result_summary,
                    COALESCE(error_code, '')
               FROM ai_call_log
              ORDER BY id",
        )
        .expect("prepare AI call log text query");
    statement
        .query_map([], |row| {
            Ok(format!(
                "{} {} {} {} {} {} {}",
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, String>(6)?,
            ))
        })
        .expect("query AI call log text")
        .map(|row| row.expect("read AI call log text"))
        .collect::<Vec<_>>()
        .join("\n")
}

pub(crate) fn enable_remote_tags(repo: &Path) {
    let repo_path = path_string(repo);
    let probe_runtime = RemoteProbeRuntime::new();
    let test = test_remote_ai_provider(repo_path.clone(), remote_test_request())
        .expect("test remote provider");
    let token = test.verification_token.expect("verification token");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable remote AI tags");
    enable_remote_ai_provider(repo_path, remote_enable_request(token))
        .expect("enable remote provider");
    drop(probe_runtime);
}

fn remote_test_request() -> RemoteProviderTestRequest {
    RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "tag-model".to_owned(),
        endpoint_url: Some("https://provider.example.test/tags".to_owned()),
        key_reference: remote_key_reference(),
    }
}

fn remote_enable_request(verification_token: String) -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "tag-model".to_owned(),
        endpoint_url: Some("https://provider.example.test/tags".to_owned()),
        key_reference: remote_key_reference(),
        feature_scope: vec![AiFeatureKind::AutoTags],
        verification_token,
        data_flow_confirmed: true,
    }
}

fn remote_key_reference() -> String {
    std::env::set_var("AREAMATRIX_AI_TAGS_TEST_KEY", "remote-provider-secret");
    "secure-storage:env:AREAMATRIX_AI_TAGS_TEST_KEY".to_owned()
}

pub(crate) fn install_ai_tag_change_log_failure(repo: &Path, tag: &str) {
    let sql = format!(
        "CREATE TRIGGER fail_ai_tag_change_log
         BEFORE INSERT ON change_log
         WHEN NEW.action = 'external_modified'
          AND json_extract(NEW.detail_json, '$.kind') = 'ai_tag_suggestion_applied'
          AND json_extract(NEW.detail_json, '$.tag') = '{tag}'
         BEGIN
           SELECT RAISE(ABORT, 'forced AI tag change_log failure');
         END;"
    );
    open_db(repo)
        .execute_batch(&sql)
        .expect("install AI tag change-log failure trigger");
}

pub(crate) fn install_ai_tag_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_ai_tag_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'batch_add_tags'
              AND json_extract(NEW.summary_json, '$.kind') = 'ai_tag_suggestions'
             BEGIN
               SELECT RAISE(ABORT, 'forced AI tag undo failure');
             END;",
        )
        .expect("install AI tag undo failure trigger");
}

pub(crate) fn install_ai_tag_apply_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS ai_call_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                feature TEXT NOT NULL,
                file_id INTEGER,
                batch_id TEXT,
                scope TEXT,
                route TEXT,
                provider TEXT,
                model TEXT,
                status TEXT NOT NULL CHECK (status IN ('success','failed','skipped','unavailable')),
                duration_ms INTEGER,
                sent_fields_json TEXT NOT NULL,
                privacy_rules_checked INTEGER NOT NULL DEFAULT 0 CHECK (privacy_rules_checked IN (0, 1)),
                privacy_rule_id TEXT,
                privacy_rule_name TEXT,
                matched_field_type TEXT,
                result_summary TEXT NOT NULL,
                error_code TEXT,
                occurred_at INTEGER NOT NULL
             );
             CREATE TRIGGER fail_ai_tag_apply_log
             BEFORE INSERT ON ai_call_log
             BEGIN
               SELECT RAISE(ABORT, 'forced AI tag apply log failure');
             END;",
        )
        .expect("install AI tag apply log failure trigger");
}

struct RemoteProbeRuntime {
    output: tempfile::TempDir,
}

impl RemoteProbeRuntime {
    fn new() -> Self {
        let output = tempfile::tempdir().expect("create remote probe runtime directory");
        let script = output.path().join("probe.sh");
        fs::write(
            &script,
            "#!/bin/sh\ncat >/dev/null\nprintf 'Succeeded\\n'\n",
        )
        .expect("write remote probe runtime");
        make_executable(&script);
        std::env::set_var(
            "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME",
            script.to_string_lossy().into_owned(),
        );
        Self { output }
    }
}

impl Drop for RemoteProbeRuntime {
    fn drop(&mut self) {
        std::env::remove_var("AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME");
        std::env::remove_var("AREAMATRIX_AI_TAGS_TEST_KEY");
        let _ = self.output.path();
    }
}

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

#[cfg(unix)]
fn make_executable(path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = fs::metadata(path)
        .expect("read script metadata")
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(path, permissions).expect("mark script executable");
}

#[cfg(not(unix))]
fn make_executable(_path: &Path) {}

#[cfg(unix)]
pub(crate) struct ReadOnlyGuard {
    path: std::path::PathBuf,
    original_mode: u32,
}

#[cfg(unix)]
impl ReadOnlyGuard {
    pub(crate) fn new(path: &Path) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let metadata = fs::metadata(path).expect("read DB metadata");
        let original_mode = metadata.permissions().mode();
        let mut permissions = metadata.permissions();
        permissions.set_mode(0o444);
        fs::set_permissions(path, permissions).expect("make DB readonly");
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
            .expect("read DB metadata")
            .permissions();
        permissions.set_mode(self.original_mode);
        fs::set_permissions(&self.path, permissions).expect("restore DB permissions");
    }
}
