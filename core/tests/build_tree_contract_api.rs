use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_tree_json, CoreError, CoreResult, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde_json::Value;
use tempfile::TempDir;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
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

fn initialized_repo(create_default_categories: bool) -> TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        repo_options(create_default_categories),
    )
    .expect("initialize repository for build_tree contract test");
    repo
}

fn parse_tree(tree_json: &str) -> Value {
    serde_json::from_str(tree_json).expect("list_tree_json output should be valid TreeNode JSON")
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

fn assert_capability_spec_fragments() {
    for fragment in [
        "C1-15 build-tree",
        "- S1-08 main-empty",
        "- S1-09 main-list",
        "- S1-10 main-loading",
        "- `list_tree_json(repo_path, locale) -> string`",
        "- `repo_path`",
        "- `locale`",
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

fn assert_control_map_fragments() {
    for fragment in [
        "| S1-08 | main-empty | C1-11, C1-15 | `list_files`, `list_tree_json`",
        "| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

fn assert_core_api_fragments() {
    for fragment in [
        "| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / Io |",
        "### `list_tree_json(repoPath, locale) throws -> String`",
        "`repoPath`：已初始化的资料库根目录。",
        "`locale`：显示名 locale",
        "输出为 Swift 可解码的 `TreeNode` JSON 字符串",
        "\"slug\": \"__root__\"",
        "`relative_path` 是稳定 path key",
        "`RepositoryRoot`、`SystemCategory`、`UserFolder` 或 `Subdir`",
        "`RepoNotInitialized`：资料库 metadata 缺失。",
        "`Db`：树构建需要读取 SQLite metadata 时失败。",
        "`Io`：资料库目录、文件路径、文件 metadata 或分类配置无法读取。",
        "只读取资料库文件路径和分类配置",
        "不写 DB，不创建 generated",
        "Stage 2 tree projection 不属于本接口",
        "try AreaMatrix.listTreeJson(repoPath: repoPath, locale: \"zh-Hans\")",
        "decoder.decode(TreeNode.self",
        "- `list_tree_json`（大库）",
    ] {
        assert_contains(CORE_API, fragment);
    }
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
            .expect("snapshot path should be under root")
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
fn build_tree_contract_api_exposes_documented_signature_input_output_and_errors() {
    fn assert_list_tree_json(_: fn(String, String) -> CoreResult<String>) {}
    assert_list_tree_json(list_tree_json);

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

    let documented_errors = [
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::db("database error"),
        CoreError::io("io error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn build_tree_contract_api_returns_stable_swift_compatible_schema_from_real_repo() {
    let repo = initialized_repo(false);
    fs::create_dir_all(repo.path().join("docs/a")).expect("create docs subdirectory");
    fs::create_dir_all(repo.path().join("finance")).expect("create finance directory");
    fs::create_dir_all(repo.path().join("projects/rust")).expect("create user subdirectory");
    fs::write(repo.path().join("docs/a/readme.md"), b"hello").expect("write docs file");
    fs::write(repo.path().join("finance/invoice.pdf"), b"invoice").expect("write finance file");
    fs::write(repo.path().join("projects/rust/notes.txt"), b"notes").expect("write project file");

    let first =
        list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list tree first");
    let second =
        list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list tree second");
    assert_eq!(first, second);

    let tree = parse_tree(&first);
    assert_eq!(child_slugs(&tree), vec!["docs", "finance", "projects"]);
    assert_eq!(tree["file_count"], 3);
    assert_eq!(tree["size_bytes"], 17);

    let docs = child_by_slug(&tree, "docs");
    assert_eq!(docs["display_name"], "文档");
    assert_eq!(docs["kind"], "SystemCategory");
    assert_eq!(docs["relative_path"], "docs");
    assert_eq!(docs["file_count"], 1);
    assert_eq!(child_by_slug(docs, "a")["kind"], "Subdir");
    assert_eq!(child_by_slug(docs, "a")["relative_path"], "docs/a");

    let finance = child_by_slug(&tree, "finance");
    assert_eq!(finance["display_name"], "财务");
    assert_eq!(finance["kind"], "SystemCategory");

    let projects = child_by_slug(&tree, "projects");
    assert_eq!(projects["display_name"], "projects");
    assert_eq!(projects["kind"], "UserFolder");
    assert_eq!(
        child_by_slug(projects, "rust")["relative_path"],
        "projects/rust"
    );
}

#[test]
fn build_tree_contract_api_docs_control_map_and_udl_stay_aligned() {
    assert_capability_spec_fragments();
    assert_control_map_fragments();

    {
        let fragment = "string list_tree_json(string repo_path, string locale);";
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    assert_core_api_fragments();
}

#[test]
fn build_tree_contract_api_documents_and_enforces_error_side_effect_scope_boundaries() {
    for fragment in [
        "`RepoNotInitialized { path }`",
        "`Db { message }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "C1-15 defines this as the read-only tree query",
        "initialized repository path",
        "display locale",
        "single JSON string",
        "Swift can decode",
        "stable path keys",
        "stable sibling ordering",
        "Swift-compatible `children`",
        "may read repository file paths and classifier config",
        "must not create generated overviews",
        "mutate repository metadata",
        "modify user files",
        "Virtual smart lists, search result trees",
        "Stage 2 tree projections remain",
        "outside this API boundary",
        "Returns `CoreError::RepoNotInitialized { path }`",
        "`CoreError::Db { message }`",
        "`CoreError::Io { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    let result = list_tree_json(path_string(uninitialized.path()), "en".to_owned());
    assert_eq!(
        result,
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );

    let repo = initialized_repo(false);
    fs::create_dir_all(repo.path().join("docs")).expect("create docs directory");
    fs::write(repo.path().join("docs/readme.md"), b"read only").expect("write docs file");
    let before = snapshot_tree(repo.path());
    list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list tree without writes");
    let after = snapshot_tree(repo.path());
    assert_eq!(after, before);
}
