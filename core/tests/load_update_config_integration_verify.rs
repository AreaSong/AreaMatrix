use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, update_config, OverviewOutput, RepoConfig, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const S1_26_SETTINGS_GENERAL: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md");
const S1_27_SETTINGS_REPOSITORY: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md");
const S1_28_SETTINGS_CLASSIFIER: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md");
const S1_30_SETTINGS_ADVANCED: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md");
const UDL: &str = include_str!("../area_matrix.udl");

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

fn settings_page_config(repo: &Path) -> RepoConfig {
    RepoConfig {
        repo_path: path_string(repo),
        default_mode: StorageMode::Indexed,
        overview_output: OverviewOutput::RootAreaMatrixFile,
        ai_enabled: true,
        locale: "en".to_owned(),
        icloud_warn: false,
        enable_extension_rules: false,
        enable_keyword_rules: false,
        fallback_to_inbox: false,
        allow_replace_during_import: true,
    }
}

#[test]
fn load_update_config_integration_verify_docs_api_and_udl_stay_aligned() {
    for fragment in [
        "RepoConfig load_config(string repo_path);",
        "void update_config(string repo_path, RepoConfig new_config);",
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

    assert_contains(CAPABILITY_SPEC, "分类规则");
    assert_contains(CAPABILITY_SPEC, "危险 Replace 开关可读写");
}

#[test]
fn load_update_config_integration_verify_control_map_matches_settings_consumers() {
    for fragment in [
        "| S1-26 | settings-general | C1-04, C1-07 | `load_config`, `update_config`",
        "| S1-27 | settings-repository | C1-04, C1-08, C1-20 | `load_config`, `update_config`",
        "| S1-28 | settings-classifier | C1-04, C1-05 | `load_config`, `predict_category`",
        "| S1-30 | settings-advanced | C1-04, C1-16, C1-20 |",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "- S1-26 settings-general",
        "- S1-27 settings-repository",
        "- S1-28 settings-classifier",
        "- S1-30 settings-advanced",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    assert_contains(S1_26_SETTINGS_GENERAL, "defaultStorageMode=Copy");
    assert_contains(S1_26_SETTINGS_GENERAL, "overviewOutput=GeneratedOnly");
    assert_contains(
        S1_27_SETTINGS_REPOSITORY,
        "新 repo 未成功打开前，当前 repo 配置保持不变",
    );
    assert_contains(S1_28_SETTINGS_CLASSIFIER, "`enableExtensionRules`");
    assert_contains(S1_28_SETTINGS_CLASSIFIER, "`enableKeywordRules`");
    assert_contains(S1_28_SETTINGS_CLASSIFIER, "`fallbackToInbox`");
    assert_contains(S1_30_SETTINGS_ADVANCED, "`allowReplaceDuringImport=false`");
}

#[test]
fn load_update_config_integration_verify_real_core_supports_settings_state() {
    let repo = initialized_repo();
    let initial = load_config(path_string(repo.path())).expect("load initial config");
    assert_eq!(initial.default_mode, StorageMode::Copied);
    assert_eq!(initial.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!initial.ai_enabled);
    assert_eq!(initial.locale, "zh-Hans");
    assert!(initial.icloud_warn);
    assert!(initial.enable_extension_rules);
    assert!(initial.enable_keyword_rules);
    assert!(initial.fallback_to_inbox);
    assert!(!initial.allow_replace_during_import);

    let expected = settings_page_config(repo.path());
    update_config(path_string(repo.path()), expected.clone()).expect("persist settings config");

    assert_eq!(load_config(path_string(repo.path())), Ok(expected));
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
    let config_before = load_config(path_string(repo.path())).expect("load initial config");
    let mut invalid = settings_page_config(repo.path());
    invalid.repo_path = "/tmp/other-area-matrix".to_owned();

    let result = update_config(path_string(repo.path()), invalid);

    assert_eq!(result, Err(area_matrix_core::CoreError::Config));
    assert_eq!(load_config(path_string(repo.path())), Ok(config_before));
    assert_eq!(
        file_snapshot(&[&readme_path, &overview_path, &classifier_path]),
        file_before
    );
}
