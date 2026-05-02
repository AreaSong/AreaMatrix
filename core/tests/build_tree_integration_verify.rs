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

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const S1_08_MAIN_EMPTY: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md");
const S1_09_MAIN_LIST: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md");
const S1_10_MAIN_LOADING: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md");
const TREE_RS: &str = include_str!("../src/tree/mod.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

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

fn initialized_repo(create_default_categories: bool) -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        repo_options(create_default_categories),
    )
    .expect("initialize repository for build-tree integration verify");
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
fn build_tree_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_15_capability_spec();
    assert_core_api_and_udl_contract();
    assert_stage_one_consumers();
    assert_rust_entry_points_are_real_tree_wiring();
}

fn assert_c1_15_capability_spec() {
    for fragment in [
        "C1-15 build-tree",
        "- S1-08 main-empty",
        "- S1-09 main-list",
        "- S1-10 main-loading",
        "- `list_tree_json(repo_path, locale) -> string`",
        "- 可被 Swift 解码的 Tree JSON。",
        "- 无写入。",
        "- 可读文件路径和分类配置。",
        "- 不写 generated overview。",
        "- `RepoNotInitialized`",
        "- `Db`",
        "- `Io`",
        "- 空资料库返回合法空树。",
        "- 大目录返回稳定排序、稳定 ID 或 path key。",
        "- JSON schema 与 Swift 模型兼容。",
        "- 虚拟智能列表、搜索结果树属于 Stage 2。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "string list_tree_json(string repo_path, string locale);",
        "| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / Io |",
        "### `list_tree_json(repoPath, locale) throws -> String`",
        "\"slug\": \"__root__\"",
        "\"display_name\": \"资料库\"",
        "\"kind\": \"RepositoryRoot\"",
        "\"relative_path\": \"\"",
        "\"file_count\": 0",
        "\"size_bytes\": 0",
        "\"depth\": 0",
        "\"children\": []",
        "`relative_path` 是稳定 path key",
        "`RepositoryRoot`、`SystemCategory`、`UserFolder` 或 `Subdir`",
        "`RepoNotInitialized`：资料库 metadata 缺失。",
        "`Db`：树构建需要读取 SQLite metadata 时失败。",
        "`Io`：资料库目录、文件路径、文件 metadata 或分类配置无法读取。",
        "不写 DB，不创建 generated",
        "Stage 2 tree projection 不属于本接口。",
    ] {
        assert_contains(CORE_API, fragment);
    }
    assert_contains(
        UDL,
        "string list_tree_json(string repo_path, string locale);",
    );
}

fn assert_stage_one_consumers() {
    for fragment in [
        "| S1-08 | main-empty | C1-11, C1-15 | `list_files`, `list_tree_json`",
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json`",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "显示默认分类树。",
        "Tree 为 ready，List 为 empty，Detail 为 empty。",
        "默认选中 `inbox`",
        "Core `list_tree_json` 结果",
    ] {
        assert_contains(S1_08_MAIN_EMPTY, fragment);
    }
    for fragment in [
        "浏览分类和目录树。",
        "Tree/List/Detail 联动必须稳定。",
        "Core `list_tree_json`，由 UI store 转成 sidebar tree。",
        "如果分类不匹配，只更新 Tree 计数。",
    ] {
        assert_contains(S1_09_MAIN_LIST, fragment);
    }
    for fragment in [
        "Tree loading：保留旧 Tree，未加载部分显示 skeleton。",
        "Tree loading 可保留上次树。",
        "用户可以切换已加载节点。",
        "DB locked 不阻断 Tree",
    ] {
        assert_contains(S1_10_MAIN_LOADING, fragment);
    }
}

fn assert_rust_entry_points_are_real_tree_wiring() {
    for fragment in [
        "C1-15 defines this as the read-only tree query",
        "stable path keys",
        "stable sibling ordering",
        "Swift-compatible `children`",
        "must not create generated overviews",
        "Virtual smart lists, search result trees",
        "Stage 2 tree projections remain",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "db::ensure_initialized_readable(repo)?",
        "WalkDir::new(repo)",
        "serde_json::to_string(&tree)",
        "BTreeMap<String, RawNode>",
        "GENERATED_DIR_PREFIX",
        "normalize_contract_error",
    ] {
        assert_contains(TREE_RS, fragment);
    }
}

#[test]
fn build_tree_integration_verify_real_tree_supports_empty_list_and_loading_consumers() {
    let repo = initialized_repo(true);
    let empty_tree = parse_tree(
        &list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list empty tree"),
    );
    assert_default_empty_tree(&empty_tree);

    write_file(repo.path(), "docs/contracts/2026Q1.pdf", b"contract");
    write_file(repo.path(), "docs/references/research.md", b"research");
    write_file(repo.path(), "code/rust/notes.txt", b"notes");

    let first_json = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect("list populated tree first time");
    let second_json = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect("list populated tree second time");
    assert_eq!(first_json, second_json);

    let tree = parse_tree(&first_json);
    assert_populated_main_tree(&tree);
}

fn assert_default_empty_tree(tree: &Value) {
    assert_eq!(tree["slug"], "__root__");
    assert_eq!(tree["display_name"], "资料库");
    assert_eq!(tree["kind"], "RepositoryRoot");
    assert_eq!(tree["relative_path"], "");
    assert_eq!(tree["file_count"], 0);
    assert_eq!(tree["size_bytes"], 0);
    assert_eq!(tree["depth"], 0);
    assert_eq!(
        child_slugs(tree),
        vec!["code", "design", "docs", "finance", "inbox", "media"]
    );
}

fn assert_populated_main_tree(tree: &Value) {
    assert_eq!(tree["display_name"], "Repository");
    assert_eq!(tree["file_count"], 3);
    assert_eq!(tree["size_bytes"], 21);
    assert_eq!(
        child_slugs(tree),
        vec!["code", "design", "docs", "finance", "inbox", "media"]
    );

    let docs = child_by_slug(tree, "docs");
    assert_eq!(docs["display_name"], "Documents");
    assert_eq!(docs["kind"], "SystemCategory");
    assert_eq!(docs["relative_path"], "docs");
    assert_eq!(docs["file_count"], 2);
    assert_eq!(
        child_by_slug(docs, "contracts")["relative_path"],
        "docs/contracts"
    );
    assert_eq!(
        child_by_slug(docs, "references")["relative_path"],
        "docs/references"
    );

    let code = child_by_slug(tree, "code");
    assert_eq!(code["display_name"], "Code");
    assert_eq!(child_by_slug(code, "rust")["kind"], "Subdir");
    assert_eq!(child_by_slug(code, "rust")["file_count"], 1);
}

#[test]
fn build_tree_integration_verify_error_scope_and_read_only_boundary_are_real() {
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        list_tree_json(path_string(uninitialized.path()), "en".to_owned()),
        Err(CoreError::RepoNotInitialized)
    );

    let repo = initialized_repo(false);
    write_file(repo.path(), "docs/specs/api.md", b"api");
    write_file(repo.path(), "AREAMATRIX.md", b"generated overview");
    write_file(
        repo.path(),
        ".areamatrix/generated/tree.json",
        b"generated tree",
    );
    let before = snapshot_tree(repo.path());

    let tree_json =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list read-only tree");
    let after = snapshot_tree(repo.path());
    assert_eq!(after, before);

    let tree = parse_tree(&tree_json);
    assert_eq!(child_slugs(&tree), vec!["docs"]);
    assert_eq!(tree["file_count"], 1);
    assert_eq!(tree["size_bytes"], 3);

    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("corrupt repository metadata");
    remove_if_exists(repo.path().join(".areamatrix/index.db-wal"));
    remove_if_exists(repo.path().join(".areamatrix/index.db-shm"));
    assert_eq!(
        list_tree_json(path_string(repo.path()), "en".to_owned()),
        Err(CoreError::Db)
    );
}

fn remove_if_exists(path: PathBuf) {
    if path.exists() {
        fs::remove_file(path).expect("remove sqlite sidecar");
    }
}
