use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_repo_config, update_repo_config, OverviewOutput, RepoConfigPatch, RepoInitMode,
    RepoInitOptions, RepositoryLocalePolicy, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
        locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

fn config_keys(repo: &Path) -> Vec<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key FROM repo_config ORDER BY key")
        .expect("prepare repo_config key query");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query repo_config keys");

    rows.map(|row| row.expect("read repo_config key")).collect()
}

fn file_snapshot(paths: &[&Path]) -> Vec<(String, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path_string(path),
                fs::read(path).expect("read file snapshot bytes"),
            )
        })
        .collect()
}

fn settings_page_patch(expected_revision: i64) -> RepoConfigPatch {
    RepoConfigPatch {
        expected_revision,
        repo_path: None,
        default_mode: Some(StorageMode::Indexed),
        overview_output: Some(OverviewOutput::RootAreaMatrixFile),
        ai_enabled: Some(true),
        locale_policy: Some(RepositoryLocalePolicy::En),
        icloud_warn: Some(false),
        enable_extension_rules: Some(false),
        enable_keyword_rules: Some(false),
        fallback_to_inbox: Some(false),
        allow_replace_during_import: Some(true),
    }
}

#[test]
fn load_update_config_integration_verify_docs_api_and_udl_stay_aligned() {
    for fragment in [
        "RepoConfigSnapshot load_repo_config(string repo_path);",
        "RepoConfigSnapshot update_repo_config(string repo_path, RepoConfigPatch patch);",
        "string? repo_path;",
        "boolean enable_extension_rules;",
        "boolean enable_keyword_rules;",
        "boolean fallback_to_inbox;",
        "boolean allow_replace_during_import;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "`enable_extension_rules`",
        "`enable_keyword_rules`",
        "`fallback_to_inbox`",
        "`allow_replace_during_import`",
        "它们只保存设置状态，不执行分类、导入或",
    ] {
        assert_contains(CORE_API, fragment);
    }
}
#[test]
fn load_update_config_integration_verify_real_core_supports_settings_state() {
    let repo = initialized_repo();
    let initial = load_repo_config(path_string(repo.path())).expect("load initial config");
    assert_eq!(initial.default_mode, StorageMode::Copied);
    assert_eq!(initial.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!initial.ai_enabled);
    assert_eq!(initial.locale_policy.raw_value, "system");
    assert!(initial.icloud_warn);
    assert!(initial.enable_extension_rules);
    assert!(initial.enable_keyword_rules);
    assert!(initial.fallback_to_inbox);
    assert!(!initial.allow_replace_during_import);

    let expected = settings_page_patch(initial.revision);
    let updated =
        update_repo_config(path_string(repo.path()), expected).expect("persist settings config");

    assert_eq!(updated.revision, initial.revision + 1);
    assert_eq!(updated.default_mode, StorageMode::Indexed);
    assert_eq!(updated.overview_output, OverviewOutput::RootAreaMatrixFile);
    assert!(updated.ai_enabled);
    assert_eq!(updated.locale_policy.raw_value, "en");
    assert_eq!(
        config_keys(repo.path()),
        vec![
            "ai_enabled",
            "allow_replace_during_import",
            "default_mode",
            "enable_extension_rules",
            "enable_keyword_rules",
            "fallback_to_inbox",
            "icloud_warn",
            "locale",
            "overview_output",
            "repo_path",
        ]
    );
    assert!(!repo.path().join("README.md").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn load_update_config_integration_verify_failures_preserve_config_and_files() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    let classifier_path = repo.path().join(".areamatrix/classifier.yaml");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");
    let file_before = file_snapshot(&[&readme_path, &overview_path, &classifier_path]);
    let config_before = load_repo_config(path_string(repo.path())).expect("load initial config");

    let result = update_repo_config(
        path_string(repo.path()),
        settings_page_patch(config_before.revision + 1),
    );

    assert!(matches!(
        result,
        Err(area_matrix_core::CoreError::RevisionConflict { .. })
    ));

    assert_eq!(
        load_repo_config(path_string(repo.path())),
        Ok(config_before)
    );
    assert_eq!(
        file_snapshot(&[&readme_path, &overview_path, &classifier_path]),
        file_before
    );
}
