use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_tree_json, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde_json::Value;
use tempfile::TempDir;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn repo_options(create_default_categories: bool) -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo(create_default_categories: bool) -> TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        repo_options(create_default_categories),
    )
    .expect("initialize repository for build-tree implementation test");
    repo
}

fn write_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent directory");
    }
    fs::write(path, content).expect("write test file");
}

fn tree_for(repo: &Path, locale: &str) -> Value {
    let tree_json =
        list_tree_json(path_string(repo), locale.to_owned()).expect("list repository tree JSON");
    serde_json::from_str(&tree_json).expect("parse tree JSON")
}

fn children(node: &Value) -> &[Value] {
    node["children"]
        .as_array()
        .expect("TreeNode children should be an array")
}

fn child_by_slug<'a>(node: &'a Value, slug: &str) -> &'a Value {
    children(node)
        .iter()
        .find(|child| child["slug"] == slug)
        .unwrap_or_else(|| panic!("expected child slug `{slug}`"))
}

fn child_slugs(node: &Value) -> Vec<&str> {
    children(node)
        .iter()
        .map(|child| child["slug"].as_str().expect("child slug should be string"))
        .collect()
}

#[test]
fn build_tree_implementation_lists_empty_default_category_directories_sorted() {
    let repo = initialized_repo(true);
    let tree = tree_for(repo.path(), "en");

    assert_eq!(tree["slug"], "__root__");
    assert_eq!(tree["display_name"], "Repository");
    assert_eq!(tree["file_count"], 0);
    assert_eq!(tree["size_bytes"], 0);
    assert_eq!(
        child_slugs(&tree),
        vec!["code", "design", "docs", "finance", "inbox", "media"]
    );

    let docs = child_by_slug(&tree, "docs");
    assert_eq!(docs["display_name"], "Documents");
    assert_eq!(docs["kind"], "SystemCategory");
    assert_eq!(docs["relative_path"], "docs");
    assert_eq!(docs["file_count"], 0);
}

#[test]
fn build_tree_implementation_counts_files_recursively_with_stable_path_keys() {
    let repo = initialized_repo(false);
    write_file(repo.path(), "docs/a/readme.md", b"hello");
    write_file(repo.path(), "finance/invoice.pdf", b"invoice");
    write_file(repo.path(), "projects/rust/notes.txt", b"notes");

    let first_json = list_tree_json(path_string(repo.path()), "zh-Hans".to_owned())
        .expect("list tree first time");
    let second_json = list_tree_json(path_string(repo.path()), "zh-Hans".to_owned())
        .expect("list tree second time");
    assert_eq!(first_json, second_json);

    let tree: Value = serde_json::from_str(&first_json).expect("parse tree JSON");
    assert_eq!(child_slugs(&tree), vec!["docs", "finance", "projects"]);
    assert_eq!(tree["file_count"], 3);
    assert_eq!(tree["size_bytes"], 17);

    let docs = child_by_slug(&tree, "docs");
    assert_eq!(docs["display_name"], "文档");
    assert_eq!(docs["file_count"], 1);
    assert_eq!(child_by_slug(docs, "a")["kind"], "Subdir");
    assert_eq!(child_by_slug(docs, "a")["relative_path"], "docs/a");

    let projects = child_by_slug(&tree, "projects");
    assert_eq!(projects["kind"], "UserFolder");
    assert_eq!(child_by_slug(projects, "rust")["file_count"], 1);
}

#[test]
fn build_tree_implementation_skips_generated_outputs_and_honors_ignore_config() {
    let repo = initialized_repo(false);
    fs::write(
        repo.path().join(".areamatrix/ignore.yaml"),
        "version: 1\nignore:\n  - \"private/\"\n",
    )
    .expect("write ignore config");

    write_file(repo.path(), "README.md", b"readme");
    write_file(repo.path(), "AREAMATRIX.md", b"root");
    write_file(
        repo.path(),
        ".areamatrix/generated/internal.md",
        b"generated",
    );
    write_file(repo.path(), "docs/AREAMATRIX.md", b"node");
    write_file(repo.path(), "docs/README.md", b"guide!");
    write_file(repo.path(), "docs/draft.tmp", b"x");
    write_file(repo.path(), "private/secret.pdf", b"secret!");

    let tree = tree_for(repo.path(), "en");
    assert_eq!(child_slugs(&tree), vec!["docs"]);
    assert_eq!(tree["file_count"], 3);
    assert_eq!(tree["size_bytes"], 16);

    let docs = child_by_slug(&tree, "docs");
    assert_eq!(docs["file_count"], 2);
    assert_eq!(docs["size_bytes"], 10);
}

#[test]
fn build_tree_implementation_falls_back_to_default_classifier_when_yaml_is_invalid() {
    let repo = initialized_repo(false);
    fs::write(
        repo.path().join(".areamatrix/classifier.yaml"),
        "not: [valid",
    )
    .expect("write invalid classifier config");
    write_file(repo.path(), "docs/a.pdf", b"x");

    let tree = tree_for(repo.path(), "en");
    let docs = child_by_slug(&tree, "docs");
    assert_eq!(docs["display_name"], "Documents");
    assert_eq!(docs["kind"], "SystemCategory");
}

#[test]
fn build_tree_implementation_requires_initialized_readable_metadata() {
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    assert_eq!(
        list_tree_json(path_string(uninitialized.path()), "en".to_owned()),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );

    let repo = initialized_repo(false);
    let metadata = repo.path().join(".areamatrix");
    fs::write(metadata.join("index.db"), b"not sqlite").expect("corrupt index db");
    remove_if_exists(metadata.join("index.db-wal"));
    remove_if_exists(metadata.join("index.db-shm"));

    assert!(matches!(
        list_tree_json(path_string(repo.path()), "en".to_owned()),
        Err(CoreError::Db { .. })
    ));
}

fn remove_if_exists(path: PathBuf) {
    if path.exists() {
        fs::remove_file(path).expect("remove sqlite sidecar");
    }
}
