use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, list_changes, list_files, list_tree_json, move_to_category,
    preview_move_to_category, read_note, write_note, ChangeFilter, DuplicateStrategy, FileEntry,
    FileFilter, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const API_RS: &str = include_str!("../src/api.rs");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DB_MOVE_TO_CATEGORY_RS: &str = include_str!("../src/db/move_to_category.rs");
const S1_35_CHANGE_CATEGORY_SHEET: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md");
const STORAGE_MOVE_TO_CATEGORY_RS: &str = include_str!("../src/storage/move_to_category.rs");
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

fn initialized_repo() -> tempfile::TempDir {
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn import_options(mode: StorageMode, category: &str, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn file_filter(category: Option<&str>) -> FileFilter {
    FileFilter {
        category: category.map(str::to_owned),
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn moved_change_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: Some("docs".to_owned()),
        action: Some("moved".to_owned()),
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 11)",
            (file_id, tag),
        )
        .expect("insert tag metadata");
}

fn tag_value(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT tag FROM tags WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read tag value")
}

fn sidecar_path(repo: &Path, relative_path: &str) -> PathBuf {
    let path = repo.join(relative_path);
    let file_name = path.file_name().expect("relative path has file name");
    path.with_file_name(format!("{}.md", file_name.to_string_lossy()))
}

fn moved_change_detail(repo: &Path, file_id: i64) -> Value {
    let changes =
        list_changes(path_string(repo), moved_change_filter(file_id)).expect("list moved changes");
    assert_eq!(changes.len(), 1);
    serde_json::from_str(&changes[0].detail_json).expect("parse moved change detail JSON")
}

fn list_paths(repo: &Path, category: &str) -> Vec<String> {
    let mut paths: Vec<String> = list_files(path_string(repo), file_filter(Some(category)))
        .expect("list files by category")
        .into_iter()
        .map(|entry| entry.path)
        .collect();
    paths.sort();
    paths
}

fn parse_tree(repo: &Path) -> Value {
    let tree_json =
        list_tree_json(path_string(repo), "en".to_owned()).expect("list repository tree JSON");
    serde_json::from_str(&tree_json).expect("parse repository tree JSON")
}

fn child_by_slug<'a>(node: &'a Value, slug: &str) -> &'a Value {
    node["children"]
        .as_array()
        .expect("TreeNode children should be an array")
        .iter()
        .find(|child| child["slug"] == slug)
        .unwrap_or_else(|| panic!("expected child slug `{slug}`"))
}

fn sqlite_integrity_check(repo: &Path) -> String {
    open_db(repo)
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("run SQLite integrity_check")
}

fn foreign_key_violations(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("PRAGMA foreign_key_check")
        .expect("prepare foreign_key_check");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("run foreign_key_check");

    rows.map(|row| row.expect("read foreign_key_check row"))
        .collect()
}

fn assert_capability_spec_alignment() {
    for fragment in [
        "# C1-24 move-to-category",
        "- S1-35 change-category-sheet",
        "- S1-09 main-list",
        "- S1-12 detail-meta",
        "`preview_move_to_category(repo_path, file_id, new_category) -> MoveToCategoryPreview`",
        "`move_to_category(repo_path, file_id, new_category) -> FileEntry`",
        "preview 不移动文件",
        "更新 `files.category`、`files.path`、`updated_at`。",
        "写入 `change_log.moved`。",
        "目标同名时按 C1-10 生成安全名称，不覆盖。",
        "Indexed 文件只更新分类元数据，不移动源文件。",
        "批量改分类属于 Stage 2 的 C2-09。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_control_map_alignment() {
    for fragment in [
        "| S1-35 | change-category-sheet | C1-24, C1-10 | `preview_move_to_category`, `move_to_category`",
        "safe preview, safe move or index-only metadata",
        "Classify, Conflict, PermissionDenied",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

fn assert_consumer_alignment() {
    for fragment in [
        "入口：`S1-09 main-list`",
        "`S1-12 detail-meta` 操作菜单",
        "预览目标相对路径。",
        "目标同名且可安全自动编号时，必须预览最终名称。",
        "`Cancel` 关闭 sheet，不写文件、不写 DB。",
        "Index-only 文件只更新分类元数据和 change_log，不移动源文件",
        "成功后 Tree 计数更新，List 跳转到目标分类并高亮该文件。",
        "成功后新位置可见且 change_log 有记录。",
    ] {
        assert_contains(S1_35_CHANGE_CATEGORY_SHEET, fragment);
    }
}

fn assert_api_and_udl_alignment() {
    for fragment in [
        "MoveToCategoryPreview preview_move_to_category(",
        "FileEntry move_to_category(string repo_path, i64 file_id, string new_category);",
        "dictionary MoveToCategoryPreview",
        "string target_path;",
        "boolean name_conflict_resolved;",
        "boolean will_move_file;",
        "dictionary FileEntry",
        "string path;",
        "string current_name;",
        "string category;",
        "StorageMode storage_mode;",
        "Classify(string reason);",
        "Conflict(string path);",
        "PermissionDenied(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_behavior_docs() {
    for fragment in [
        "`preview_move_to_category` 是 C1-24 的确认前目标路径解析入口",
        "不得创建分类目录、移动文件、重命名文件、删除文件、更新",
        "`move_to_category` 是 C1-24 的单文件改分类入口",
        "`newCategory` 必须存在于",
        "Core\n不得隐式创建新分类",
        "目标分类目录不存在时可创建该分类目录",
        "同名目标按 C1-10 安全编号策略解析",
        "不移动、重命名或覆盖外部源文件",
        "`Classify`：目标分类不存在或 classifier 规则不可用。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_api_alignment() {
    for fragment in [
        "pub fn preview_move_to_category(",
        "storage::preview_move_to_category(repo_path, file_id, new_category)",
        "Previews the final destination for a C1-24 category move",
        "must not create category directories",
        "pub fn move_to_category(",
        "storage::move_to_category(repo_path, file_id, new_category)",
        "C1-24 owns the user-visible change-category contract",
        "not an arbitrary directory",
        "C1-10 conflict-free numbering",
        "Indexed rows are metadata-only",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_storage_implementation_alignment() {
    for fragment in [
        "preview_move_to_category",
        "preview_repo_owned_file",
        "MoveToCategoryPreview",
        "classify::ensure_category_exists",
        "move_repo_owned_file",
        "move_indexed_file",
        "dedup::resolve_rename_path",
        "move_recoverable_file",
        "NoteSidecarPlan",
        "db::move_repo_owned_file_to_category",
    ] {
        assert_contains(STORAGE_MOVE_TO_CATEGORY_RS, fragment);
    }
}

fn assert_db_implementation_alignment() {
    for fragment in [
        "transaction()",
        "UPDATE files",
        "SET path = ?2",
        "current_name = ?3",
        "category = ?4",
        "INSERT INTO change_log",
        "'moved'",
        "tx.commit()",
    ] {
        assert_contains(DB_MOVE_TO_CATEGORY_RS, fragment);
    }
}

struct RepoOwnedMoveFixture {
    repo: tempfile::TempDir,
    moving_source_root: tempfile::TempDir,
    moving_source: PathBuf,
    readme_path: PathBuf,
    existing: FileEntry,
    moving: FileEntry,
    moved: FileEntry,
}

fn repo_owned_move_fixture() -> RepoOwnedMoveFixture {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let (_existing_root, existing_source) = source_file("existing.pdf", b"existing bytes");
    let (moving_source_root, moving_source) = source_file("moving.pdf", b"moving bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "docs", "same.pdf"),
    )
    .expect("import existing docs file");
    let moving = import_file(
        path_string(repo.path()),
        path_string(&moving_source),
        import_options(StorageMode::Copied, "finance", "same.pdf"),
    )
    .expect("import copied file before category move");
    write_note(
        path_string(repo.path()),
        moving.id,
        "attached note".to_owned(),
    )
    .expect("write note before category move");
    insert_tag(repo.path(), moving.id, "keep-tag");
    let preview = preview_move_to_category(path_string(repo.path()), moving.id, "docs".to_owned())
        .expect("preview copied file category move");
    assert_eq!(preview.target_path, "docs/same_1.pdf");
    assert_eq!(preview.target_name, "same_1.pdf");
    assert!(preview.name_conflict_resolved);
    assert!(preview.will_move_file);
    assert!(repo.path().join("finance/same.pdf").exists());
    assert!(!repo.path().join("docs/same_1.pdf").exists());
    let moved = move_to_category(path_string(repo.path()), moving.id, "docs".to_owned())
        .expect("move copied file to docs category");

    RepoOwnedMoveFixture {
        repo,
        moving_source_root,
        moving_source,
        readme_path,
        existing,
        moving,
        moved,
    }
}

fn assert_repo_owned_identity(fixture: &RepoOwnedMoveFixture) {
    assert_eq!(fixture.moved.id, fixture.moving.id);
    assert_eq!(fixture.moved.path, "docs/same_1.pdf");
    assert_eq!(fixture.moved.current_name, "same_1.pdf");
    assert_eq!(fixture.moved.category, "docs");
    assert_eq!(fixture.moved.original_name, fixture.moving.original_name);
    assert_eq!(fixture.moved.hash_sha256, fixture.moving.hash_sha256);
    assert_eq!(fixture.moved.storage_mode, StorageMode::Copied);
    assert_eq!(fixture.moved.source_path, fixture.moving.source_path);
}

fn assert_repo_owned_consumers(fixture: &RepoOwnedMoveFixture) {
    let repo = fixture.repo.path();
    assert_eq!(
        get_file(path_string(repo), fixture.moving.id).expect("get moved file"),
        fixture.moved
    );
    assert_eq!(
        list_paths(repo, "docs"),
        vec!["docs/same.pdf", "docs/same_1.pdf"]
    );
    assert!(list_paths(repo, "finance").is_empty());
    let docs_tree_count = child_by_slug(&parse_tree(repo), "docs")["file_count"]
        .as_i64()
        .expect("docs tree file_count should be an integer");
    assert!(docs_tree_count >= 2);
    assert_eq!(sqlite_integrity_check(repo), "ok");
    assert!(foreign_key_violations(repo).is_empty());
}

fn assert_repo_owned_filesystem(fixture: &RepoOwnedMoveFixture) {
    let repo = fixture.repo.path();
    assert!(fixture.moving_source_root.path().exists());
    assert_eq!(
        fs::read(repo.join(&fixture.existing.path)).expect("read existing target after move"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.join("docs/same_1.pdf")).expect("read moved file"),
        b"moving bytes"
    );
    assert!(!repo.join("finance/same.pdf").exists());
    assert_eq!(
        fs::read(&fixture.moving_source).expect("read copied source after category move"),
        b"moving bytes"
    );
    assert_eq!(
        fs::read_to_string(&fixture.readme_path).expect("read user README after category move"),
        "user readme\n"
    );
}

fn assert_repo_owned_metadata(fixture: &RepoOwnedMoveFixture) {
    let repo = fixture.repo.path();
    assert_eq!(
        read_note(path_string(repo), fixture.moving.id).expect("read note after category move"),
        Some("attached note".to_owned())
    );
    assert_eq!(tag_value(repo, fixture.moving.id), "keep-tag");
    let detail = moved_change_detail(repo, fixture.moving.id);
    assert_eq!(detail["from_category"], "finance");
    assert_eq!(detail["to_category"], "docs");
    assert_eq!(detail["from_path"], "finance/same.pdf");
    assert_eq!(detail["to_path"], "docs/same_1.pdf");
    assert_eq!(detail["renamed_to"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(detail["index_only"], false);
    assert!(!sidecar_path(repo, "finance/same.pdf").exists());
    assert_eq!(
        fs::read_to_string(sidecar_path(repo, "docs/same_1.pdf")).expect("read moved note sidecar"),
        "attached note"
    );
}

#[test]
fn move_to_category_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_capability_spec_alignment();
    assert_control_map_alignment();
    assert_consumer_alignment();
    assert_api_and_udl_alignment();
    assert_core_api_behavior_docs();
    assert_rust_api_alignment();
    assert_storage_implementation_alignment();
    assert_db_implementation_alignment();
}

#[test]
fn move_to_category_integration_verify_repo_owned_flow_reaches_consuming_queries() {
    let fixture = repo_owned_move_fixture();

    assert_repo_owned_identity(&fixture);
    assert_repo_owned_consumers(&fixture);
    assert_repo_owned_filesystem(&fixture);
    assert_repo_owned_metadata(&fixture);
}

#[test]
fn move_to_category_integration_verify_indexed_flow_has_no_external_mutation() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read indexed source before move");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "finance", "shown.pdf"),
    )
    .expect("index external file before category move");

    let moved = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("move indexed metadata to docs category");

    assert_eq!(moved.id, entry.id);
    assert_eq!(moved.path, source_path);
    assert_eq!(moved.current_name, "shown.pdf");
    assert_eq!(moved.category, "docs");
    assert_eq!(moved.source_path, entry.source_path);
    assert_eq!(
        get_file(path_string(repo.path()), entry.id).expect("get indexed moved file"),
        moved
    );
    assert_eq!(list_paths(repo.path(), "docs"), vec![moved.path.clone()]);
    assert!(list_paths(repo.path(), "finance").is_empty());
    assert_eq!(
        fs::read(&source).expect("read indexed external source after move"),
        source_bytes
    );
    assert!(!repo.path().join("docs/shown.pdf").exists());

    let detail = moved_change_detail(repo.path(), entry.id);
    assert_eq!(detail["from_category"], "finance");
    assert_eq!(detail["to_category"], "docs");
    assert_eq!(detail["from_path"], entry.path);
    assert_eq!(detail["to_path"], moved.path);
    assert_eq!(detail["index_only"], true);
    assert_eq!(sqlite_integrity_check(repo.path()), "ok");
    assert!(foreign_key_violations(repo.path()).is_empty());
}
