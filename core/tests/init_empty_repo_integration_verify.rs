use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_files, list_tree_json, load_config, CoreError, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const S1_04_CONFIRM_INIT: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md");
const S1_05_INITIALIZING: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md");
const S1_07_INIT_DONE: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md");
const S1_08_MAIN_EMPTY: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options(create_default_categories: bool) -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories,
        overview_output: OverviewOutput::GeneratedOnly,
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
        "RepoConfig load_config(string repo_path);",
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

    assert_contains(
        CAPABILITY_SPEC,
        "`init_repo(repo_path, RepoInitOptions { mode: CreateEmpty, ... })`",
    );
    assert_contains(CAPABILITY_SPEC, "`load_config(repo_path)`");
    assert_contains(CAPABILITY_SPEC, "`list_tree_json(repo_path, locale)`");
}

#[test]
fn init_empty_repo_integration_verify_control_map_matches_c1_02_consumers() {
    for fragment in [
        "| S1-04 | confirm-init | C1-02, C1-03 | `init_repo`",
        "| S1-05 | initializing | C1-02, C1-03, C1-16 | `init_repo`",
        "| S1-07 | init-done | C1-02, C1-03 | `load_config`, `list_tree_json`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    assert_contains(CAPABILITY_SPEC, "- S1-04 confirm-init");
    assert_contains(CAPABILITY_SPEC, "- S1-05 initializing");
    assert_contains(CAPABILITY_SPEC, "- S1-07 init-done");
    assert_contains(CAPABILITY_SPEC, "- S1-08 main-empty");

    assert_contains(
        S1_04_CONFIRM_INIT,
        "点击主按钮前不得创建、移动、重命名、删除或覆盖任何文件",
    );
    assert_contains(S1_05_INITIALIZING, "不得删除用户原文件");
    assert_contains(S1_07_INIT_DONE, "初始化结果摘要");
    assert_contains(S1_08_MAIN_EMPTY, "Core `list_tree_json` 结果");
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

    let config = load_config(path_string(repo.path())).expect("load initialized config");
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

    assert_eq!(result, Err(CoreError::Config));
    assert_eq!(
        fs::read_to_string(&readme).expect("read preserved README"),
        "# user content\n"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}
