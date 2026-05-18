use std::{fs, path::Path};

use area_matrix_core::{
    create_saved_search, init_repo, list_command_targets, CommandIndex, CommandIndexContext,
    CommandTarget, CommandTargetAction, CoreError, CoreResult, CreateSavedSearchRequest, ErrorKind,
    OverviewOutput, RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchFilter, SearchScope,
    SearchSort, SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-11-command-index.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const LIB_RS: &str = include_str!("../src/lib.rs");
const COMMAND_INDEX_RS: &str = include_str!("../src/command_index.rs");
const COMMAND_INDEX_REGISTRY_RS: &str = include_str!("../src/command_index/registry.rs");

#[derive(Debug, Eq, PartialEq)]
struct CommandIndexValidationSnapshot {
    files: Vec<(i64, String, String, String, i64)>,
    saved_searches: Vec<(i64, String, String, i64)>,
    change_log_count: i64,
    undo_action_count: i64,
    tag_count: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_file_bytes: Vec<(String, Vec<u8>)>,
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

fn default_context() -> CommandIndexContext {
    CommandIndexContext {
        query: None,
        selected_file_ids: Vec::new(),
        current_path: None,
        include_file_candidates: false,
    }
}

fn saved_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "report".to_owned(),
        filter: SearchFilter {
            scope: SearchScope::AllRepo,
            current_path: None,
            category: None,
            file_kind: None,
            tags: Vec::new(),
            tag_match_mode: SearchTagMatchMode::Any,
            imported_after: None,
            imported_before: None,
            modified_after: None,
            modified_before: None,
            storage_mode: None,
            include_deleted: Some(false),
        },
        sort: SearchSort::NewestImported,
    }
}

fn create_request(name: &str, pinned: bool) -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_active_file(repo: &Path, relative_path: &str, category: &str, updated_at: i64) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(
        &file_path,
        format!("command index fixture for {relative_path}"),
    )
    .expect("write fixture file");
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 37,
                ?4, 'copied', 'imported', NULL,
                ?5, ?5, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", updated_at),
                updated_at,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn snapshot(repo: &Path) -> CommandIndexValidationSnapshot {
    CommandIndexValidationSnapshot {
        files: file_rows(repo),
        saved_searches: saved_search_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        undo_action_count: table_count(repo, "undo_actions"),
        tag_count: table_count(repo, "tags"),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_file_bytes: user_file_bytes(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String, i64)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status, updated_at FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
            ))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn saved_search_rows(repo: &Path) -> Vec<(i64, String, String, i64)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, name, query_json, pinned FROM saved_searches ORDER BY id")
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query saved search rows")
        .map(|row| row.expect("read saved search row"))
        .collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count metadata rows")
}

fn relative_directory_entries(repo: &Path, path: &Path) -> Vec<String> {
    let mut entries: Vec<String> = fs::read_dir(path)
        .expect("read metadata directory")
        .map(|entry| {
            entry
                .expect("read metadata entry")
                .path()
                .strip_prefix(repo)
                .expect("metadata path is inside repository")
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    entries.sort();
    entries
}

fn user_file_bytes(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_file_bytes(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn collect_user_file_bytes(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let path = entry.expect("read repository entry").path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        if path.is_dir() {
            collect_user_file_bytes(repo, &path, files);
        } else {
            files.push((relative, fs::read(&path).expect("read user fixture file")));
        }
    }
}

fn find_target<'a>(targets: &'a [CommandTarget], id: &str) -> &'a CommandTarget {
    targets
        .iter()
        .find(|target| target.id == id)
        .expect("target should be present")
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn command_index_validation_covers_ui_ready_success_without_side_effects() {
    let repo = initialized_repo();
    let selected_id = insert_active_file(repo.path(), "finance/report.pdf", "finance", 200);
    insert_active_file(repo.path(), "finance/invoice.txt", "finance", 100);
    insert_active_file(repo.path(), "docs/report-notes.md", "docs", 300);
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Report Review", true),
    )
    .expect("create saved search fixture");
    let before = snapshot(repo.path());

    let index = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            query: Some("report".to_owned()),
            selected_file_ids: vec![selected_id],
            current_path: Some("finance".to_owned()),
            include_file_candidates: true,
        },
    )
    .expect("list C2-11 command targets");

    assert!(index.generated_at > 0);
    assert!(index.recent_targets.is_empty());
    assert!(index
        .commands
        .iter()
        .all(|target| matches_query(target, "report")));
    assert_eq!(
        index
            .smart_lists
            .iter()
            .map(|target| target.saved_search_id)
            .collect::<Vec<_>>(),
        vec![Some(saved.id)]
    );
    assert_eq!(
        index
            .file_candidates
            .iter()
            .map(|target| target.file_id)
            .collect::<Vec<_>>(),
        vec![Some(selected_id)]
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn command_index_validation_locks_confirmation_boundaries_for_selection_commands() {
    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "docs/local-report.txt", "docs", 100);

    let index = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            selected_file_ids: vec![file_id],
            ..default_context()
        },
    )
    .expect("list selection command targets");

    let add_tags = find_target(&index.current_selection_targets, "selection.add-tags");
    assert_eq!(add_tags.action, CommandTargetAction::OpenSheet);
    assert!(!add_tags.requires_confirmation);
    assert_eq!(add_tags.route.as_deref(), Some("S2-09"));

    for (id, route) in [
        ("selection.change-category", "S2-12"),
        ("selection.delete", "S2-13"),
        ("selection.rename", "S2-14"),
    ] {
        let target = find_target(&index.current_selection_targets, id);
        assert_eq!(target.action, CommandTargetAction::OpenConfirmation);
        assert!(target.requires_confirmation);
        assert_eq!(target.route.as_deref(), Some(route));
        assert!(!target.disabled);
    }
}

#[test]
fn command_index_validation_covers_failure_paths_without_writes() {
    let repo = initialized_repo();
    insert_active_file(repo.path(), "finance/report.pdf", "finance", 100);
    let before = snapshot(repo.path());

    for context in [
        CommandIndexContext {
            selected_file_ids: vec![0],
            ..default_context()
        },
        CommandIndexContext {
            current_path: Some("../outside".to_owned()),
            ..default_context()
        },
        CommandIndexContext {
            query: Some("bad\0query".to_owned()),
            ..default_context()
        },
    ] {
        assert_db_error(list_command_targets(path_string(repo.path()), context));
    }
    assert_db_error(list_command_targets(String::new(), default_context()));
    assert_eq!(snapshot(repo.path()), before);

    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    assert_db_error(list_command_targets(
        path_string(uninitialized.path()),
        default_context(),
    ));
    assert!(!uninitialized.path().join(".areamatrix").exists());
}

#[test]
fn command_index_validation_locks_core_api_udl_rust_and_docs_alignment() {
    fn assert_signature(_: fn(String, CommandIndexContext) -> CoreResult<CommandIndex>) {}
    assert_signature(list_command_targets);

    for fragment in [
        "# C2-11 command-index",
        "- S2-15 command-palette",
        "计划新增：`list_command_targets(repo_path) -> CommandIndex`",
        "命令面板只列出当前上下文允许的动作。",
        "危险动作仍必须跳转确认页。",
        "不绕过权限或高风险确认。",
        "- `Db`",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    assert_contains(
        CONTROL_MAP,
        "| S2-15 | command-palette | C2-04, C2-11 | command index | 只读 / recent command",
    );
    assert_contains(
        CORE_API,
        "CommandIndex list_command_targets(string repo_path, CommandIndexContext context);",
    );
    assert_contains(
        CORE_API,
        "危险命令只返回跳转确认或预览页的目标，必须设置 `requires_confirmation`",
    );
    assert_contains(
        CORE_API,
        "该 API 不移动、删除、重命名、retag、reclassify、redo",
    );

    for fragment in [
        "CommandIndex list_command_targets(string repo_path, CommandIndexContext context);",
        "dictionary CommandIndexContext",
        "sequence<i64> selected_file_ids;",
        "dictionary CommandTarget",
        "boolean requires_confirmation;",
        "dictionary CommandIndex",
        "sequence<CommandTarget> file_candidates;",
        "enum CommandTargetAction",
        "\"OpenConfirmation\"",
    ] {
        assert_contains(UDL, fragment);
    }

    assert_contains(
        LIB_RS,
        "list_command_targets, CommandIndex, CommandIndexContext, CommandTarget",
    );
    assert_contains(COMMAND_INDEX_RS, "pub fn list_command_targets(");
    assert_contains(COMMAND_INDEX_RS, "CoreError::Db");
    assert_contains(COMMAND_INDEX_RS, "must never execute destructive actions");
    assert_contains(COMMAND_INDEX_RS, "registry::recent_targets");
    assert_contains(COMMAND_INDEX_REGISTRY_RS, "command.redo-latest-action");
    assert_contains(COMMAND_INDEX_REGISTRY_RS, "command.review-import-conflicts");
    assert_contains(COMMAND_INDEX_REGISTRY_RS, "command.review-tag-suggestions");
    assert_contains(COMMAND_INDEX_REGISTRY_RS, "command.open-classifier-rules");
    assert_contains(
        COMMAND_INDEX_REGISTRY_RS,
        "command.preview-classifier-rule-impact",
    );
    assert_contains(COMMAND_INDEX_REGISTRY_RS, "command.apply-classifier-rule");
    assert_contains(COMMAND_INDEX_REGISTRY_RS, "selection.delete");
    assert_contains(
        COMMAND_INDEX_REGISTRY_RS,
        "CommandTargetAction::OpenConfirmation",
    );
}

fn matches_query(target: &CommandTarget, query: &str) -> bool {
    let query = query.to_lowercase();
    target.id.to_lowercase().contains(&query)
        || target.title.to_lowercase().contains(&query)
        || target
            .subtitle
            .as_deref()
            .is_some_and(|subtitle| subtitle.to_lowercase().contains(&query))
        || target
            .route
            .as_deref()
            .is_some_and(|route| route.to_lowercase().contains(&query))
}
