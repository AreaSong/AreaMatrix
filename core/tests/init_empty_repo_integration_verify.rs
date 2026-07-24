use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_files, list_tree_json, load_repo_config, CoreError, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options(create_default_categories: bool) -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories,
        overview_output: OverviewOutput::GeneratedOnly,
        locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

fn tree_child_names(tree_json: &str) -> Vec<String> {
    let tree: Value = serde_json::from_str(tree_json).expect("parse list_tree_json output");
    let children = tree["children"]
        .as_array()
        .expect("tree children should be an array");
    children
        .iter()
        .map(|child| {
            child["slug"]
                .as_str()
                .expect("tree child should expose a slug")
                .to_owned()
        })
        .collect()
}

#[test]
fn init_empty_repo_integration_verify_docs_udl_and_public_api_stay_aligned() {
    for api_fragment in [
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfigSnapshot load_repo_config(string repo_path);",
        "string list_tree_json(string repo_path, string locale);",
        "dictionary RepoInitOptions",
        "RepoInitMode mode;",
        "boolean create_default_categories;",
        "OverviewOutput overview_output;",
        "enum RepoInitMode { \"CreateEmpty\", \"AdoptExisting\" };",
        "enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };",
    ] {
        assert_contains(CORE_API, api_fragment);
        assert_contains(UDL, api_fragment);
    }
}
#[test]
fn init_empty_repo_integration_verify_real_create_empty_flow_supports_ux_consumption() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    init_repo(path_string(repo.path()), create_empty_options(true))
        .expect("initialize empty repo with default categories");

    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(repo.path().join(".areamatrix/staging").is_dir());
    assert!(repo.path().join(".areamatrix/archives").is_dir());
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());
    assert!(repo.path().join(".areamatrix/classifier.yaml").is_file());
    assert!(repo.path().join(".areamatrix/ignore.yaml").is_file());
    assert!(!repo.path().join("README.md").exists());

    let config = load_repo_config(path_string(repo.path())).expect("load initialized config");
    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list empty repo");
    assert!(files.is_empty());

    let tree_json =
        list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list tree");
    assert_eq!(
        tree_child_names(&tree_json),
        vec!["code", "design", "docs", "finance", "inbox", "media"]
    );
}

#[test]
fn init_empty_repo_integration_verify_rejects_scope_creep_and_preserves_user_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# user content\n").expect("write user README");

    let result = init_repo(path_string(repo.path()), create_empty_options(true));

    assert!(matches!(result, Err(CoreError::Config { .. })));

    assert_eq!(
        fs::read_to_string(&readme).expect("read preserved README"),
        "# user content\n"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}
