use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_tree_json, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

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

fn initialized_repo(create_default_categories: bool) -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        create_empty_options(create_default_categories),
    )
    .expect("initialize repository for build-tree validation");
    repo
}

fn write_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent directory");
    }
    fs::write(path, content).expect("write repository fixture file");
}

fn parse_tree(tree_json: &str) -> Value {
    serde_json::from_str(tree_json).expect("parse list_tree_json TreeNode JSON")
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

fn snapshot_tree(root: &Path) -> BTreeMap<PathBuf, Option<Vec<u8>>> {
    let mut snapshot = BTreeMap::new();
    collect_snapshot(root, root, &mut snapshot);
    snapshot
}

fn collect_snapshot(
    root: &Path,
    current: &Path,
    snapshot: &mut BTreeMap<PathBuf, Option<Vec<u8>>>,
) {
    for entry in fs::read_dir(current).expect("read snapshot directory") {
        let entry = entry.expect("read snapshot entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(root)
            .expect("snapshot path should stay under repository root")
            .to_path_buf();
        let file_type = entry.file_type().expect("read snapshot file type");
        if file_type.is_dir() {
            snapshot.insert(relative, None);
            collect_snapshot(root, &path, snapshot);
        } else if file_type.is_file() {
            snapshot.insert(relative, Some(fs::read(path).expect("read snapshot file")));
        }
    }
}

#[test]
fn build_tree_validation_empty_repo_returns_swift_compatible_root() {
    let repo = initialized_repo(false);

    let tree_json =
        list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list empty tree");
    let tree = parse_tree(&tree_json);

    assert_eq!(tree["slug"], "__root__");
    assert_eq!(tree["display_name"], "资料库");
    assert_eq!(tree["kind"], "RepositoryRoot");
    assert_eq!(tree["relative_path"], "");
    assert_eq!(tree["file_count"], 0);
    assert_eq!(tree["size_bytes"], 0);
    assert_eq!(tree["depth"], 0);
    assert!(children(&tree).is_empty());
}

#[test]
fn build_tree_validation_large_directory_stays_stable_sorted_and_read_only() {
    let repo = initialized_repo(false);
    write_file(repo.path(), "finance/2026/invoice.pdf", b"invoice");
    write_file(repo.path(), "docs/specs/api.md", b"api");
    write_file(repo.path(), "docs/specs/readme.md", b"readme");
    write_file(repo.path(), "media/screenshots/hero.png", b"image");
    write_file(repo.path(), "projects/rust/zeta.txt", b"zeta");
    write_file(repo.path(), "projects/rust/alpha.txt", b"alpha");
    write_file(repo.path(), "AREAMATRIX.md", b"generated root overview");
    write_file(
        repo.path(),
        ".areamatrix/generated/tree.json",
        b"generated tree",
    );
    let before = snapshot_tree(repo.path());

    let first = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect("list populated tree first time");
    let second = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect("list populated tree second time");
    let after = snapshot_tree(repo.path());

    assert_eq!(first, second);
    assert_eq!(after, before);

    let tree = parse_tree(&first);
    assert_eq!(
        child_slugs(&tree),
        vec!["docs", "finance", "media", "projects"]
    );
    assert_eq!(tree["file_count"], 6);
    assert_eq!(tree["size_bytes"], 30);

    let docs = child_by_slug(&tree, "docs");
    assert_eq!(docs["kind"], "SystemCategory");
    assert_eq!(docs["display_name"], "Documents");
    assert_eq!(docs["relative_path"], "docs");
    assert_eq!(docs["file_count"], 2);

    let specs = child_by_slug(docs, "specs");
    assert_eq!(specs["kind"], "Subdir");
    assert_eq!(specs["relative_path"], "docs/specs");
    assert_eq!(specs["file_count"], 2);
    assert_eq!(specs["children"], Value::Array(Vec::new()));

    let projects = child_by_slug(&tree, "projects");
    assert_eq!(projects["kind"], "UserFolder");
    assert_eq!(projects["relative_path"], "projects");
    assert_eq!(
        child_by_slug(projects, "rust")["relative_path"],
        "projects/rust"
    );
}

#[test]
fn build_tree_validation_returns_repo_not_initialized_and_db_errors() {
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        list_tree_json(path_string(uninitialized.path()), "en".to_owned()),
        Err(CoreError::RepoNotInitialized)
    );

    let repo = initialized_repo(false);
    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("corrupt repository metadata");
    remove_if_exists(repo.path().join(".areamatrix/index.db-wal"));
    remove_if_exists(repo.path().join(".areamatrix/index.db-shm"));

    assert_eq!(
        list_tree_json(path_string(repo.path()), "en".to_owned()),
        Err(CoreError::Db)
    );
}

#[test]
fn build_tree_validation_maps_unreadable_classifier_to_io_error() {
    let repo = initialized_repo(false);
    let classifier_path = repo.path().join(".areamatrix/classifier.yaml");
    fs::remove_file(&classifier_path).expect("remove classifier file fixture");
    fs::create_dir(&classifier_path).expect("replace classifier file with unreadable directory");

    assert_eq!(
        list_tree_json(path_string(repo.path()), "en".to_owned()),
        Err(CoreError::Io)
    );
}

fn remove_if_exists(path: PathBuf) {
    if path.exists() {
        fs::remove_file(path).expect("remove sqlite sidecar");
    }
}
