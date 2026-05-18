use std::{fs, path::Path};

use area_matrix_core::{
    create_saved_search, init_repo, list_command_targets, CommandIndexContext, CommandTargetAction,
    CommandTargetGroup, CommandTargetKind, CoreError, CreateSavedSearchRequest, OverviewOutput,
    RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchFilter, SearchScope, SearchSort,
    SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct CommandIndexSnapshot {
    files: Vec<(i64, String, String, String, i64)>,
    saved_searches: Vec<(i64, String, String)>,
    recent_commands: Vec<(String, i64, i64)>,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
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

fn insert_file(repo: &Path, relative_path: &str, category: &str, updated_at: i64) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create parent directory");
    fs::write(&file_path, format!("fixture bytes for {relative_path}"))
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
                ?1, ?2, ?2, ?3, 13,
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

fn insert_deleted_file(repo: &Path) -> i64 {
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, deleted_at, status
             ) VALUES (
                'archive/deleted.txt', 'deleted.txt', 'deleted.txt', 'archive', 13,
                ?1, 'copied', 'imported', NULL,
                1, 1, 2, 'deleted'
             )",
            [format!("{:064x}", 10_000)],
        )
        .expect("insert deleted file row");
    connection.last_insert_rowid()
}

fn insert_recent_commands(repo: &Path, rows: &[(&str, i64, i64)]) {
    let payload = rows
        .iter()
        .map(|(target_id, used_at, use_count)| {
            format!(r#"{{"target_id":"{target_id}","used_at":{used_at},"use_count":{use_count}}}"#)
        })
        .collect::<Vec<_>>()
        .join(",");
    open_db(repo)
        .execute(
            "INSERT OR REPLACE INTO repo_config (key, value, updated_at)
             VALUES ('recent_commands', ?1, strftime('%s', 'now'))",
            [format!("[{payload}]")],
        )
        .expect("insert recent command metadata");
}

fn snapshot(repo: &Path) -> CommandIndexSnapshot {
    CommandIndexSnapshot {
        files: file_rows(repo),
        saved_searches: saved_search_rows(repo),
        recent_commands: recent_command_rows(repo),
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

fn saved_search_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, name, query_json FROM saved_searches ORDER BY id")
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query saved search rows")
        .map(|row| row.expect("read saved search row"))
        .collect()
}

fn recent_command_rows(repo: &Path) -> Vec<(String, i64, i64)> {
    let connection = open_db(repo);
    let value = connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'recent_commands'",
            [],
            |row| row.get::<_, String>(0),
        )
        .unwrap_or_default();
    vec![("recent_commands".to_owned(), value.len() as i64, 1)]
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
        let entry = entry.expect("read repository entry");
        let path = entry.path();
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

fn find_target<'a>(
    targets: &'a [area_matrix_core::CommandTarget],
    id: &str,
) -> &'a area_matrix_core::CommandTarget {
    targets
        .iter()
        .find(|target| target.id == id)
        .expect("target should be present")
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    assert!(matches!(
        result.expect_err("operation should fail with Db"),
        CoreError::Db { .. }
    ));
}

#[test]
fn command_index_implementation_lists_contextual_targets_without_side_effects() {
    let repo = initialized_repo();
    let report_id = insert_file(repo.path(), "finance/report.pdf", "finance", 200);
    insert_file(repo.path(), "finance/invoice.txt", "finance", 100);
    insert_file(repo.path(), "docs/report-notes.md", "docs", 300);
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Report Review", true),
    )
    .expect("create saved search");
    let before = snapshot(repo.path());

    let unfiltered = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            selected_file_ids: vec![report_id],
            include_file_candidates: true,
            ..default_context()
        },
    )
    .expect("list unfiltered command targets");
    let index = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            query: Some("report".to_owned()),
            selected_file_ids: vec![report_id],
            current_path: Some("finance".to_owned()),
            include_file_candidates: true,
        },
    )
    .expect("list command targets");

    let rename = find_target(&unfiltered.current_selection_targets, "selection.rename");
    assert_eq!(rename.action, CommandTargetAction::OpenConfirmation);
    assert_eq!(rename.route.as_deref(), Some("S2-14"));
    assert!(rename.requires_confirmation);
    assert!(!rename.disabled);

    let delete = find_target(&unfiltered.current_selection_targets, "selection.delete");
    assert_eq!(delete.route.as_deref(), Some("S2-13"));
    assert!(delete.requires_confirmation);
    assert_eq!(delete.action, CommandTargetAction::OpenConfirmation);

    assert!(index.generated_at > 0);
    assert!(index
        .commands
        .iter()
        .all(|target| target.title.to_lowercase().contains("report")
            || target.id.to_lowercase().contains("report")
            || target
                .subtitle
                .as_deref()
                .is_some_and(|subtitle| subtitle.to_lowercase().contains("report"))));
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
        vec![Some(report_id)]
    );
    assert!(index.recent_targets.is_empty());

    let smart = &index.smart_lists[0];
    assert_eq!(smart.group, CommandTargetGroup::SmartLists);
    assert_eq!(smart.kind, CommandTargetKind::SmartList);
    assert_eq!(smart.action, CommandTargetAction::RunSmartList);
    assert!(!smart.requires_confirmation);

    let file = &index.file_candidates[0];
    assert_eq!(file.group, CommandTargetGroup::FileCandidates);
    assert_eq!(file.kind, CommandTargetKind::FileCandidate);
    assert_eq!(file.action, CommandTargetAction::FocusFile);
    assert!(!file.requires_confirmation);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn command_index_implementation_reads_recent_metadata_without_writing_history() {
    let repo = initialized_repo();
    insert_recent_commands(
        repo.path(),
        &[
            ("nav.settings", 300, 4),
            ("command.import-files", 200, 2),
            ("command.missing", 100, 9),
        ],
    );
    let before = snapshot(repo.path());

    let index = list_command_targets(path_string(repo.path()), default_context())
        .expect("list command targets with recent metadata");

    assert_eq!(
        index
            .recent_targets
            .iter()
            .map(|target| (target.id.as_str(), target.route.as_deref()))
            .collect::<Vec<_>>(),
        vec![
            ("recent:nav.settings", Some("settings")),
            ("recent:command.import-files", Some("import")),
        ]
    );
    assert!(index
        .recent_targets
        .iter()
        .all(|target| target.group == CommandTargetGroup::Recent
            && target.kind == CommandTargetKind::RecentCommand));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn command_index_implementation_disables_selection_when_context_is_empty_or_stale() {
    let repo = initialized_repo();
    let active_id = insert_file(repo.path(), "docs/active.txt", "docs", 10);
    let deleted_id = insert_deleted_file(repo.path());

    let empty = list_command_targets(path_string(repo.path()), default_context())
        .expect("list default command targets");
    let add_tags = find_target(&empty.current_selection_targets, "selection.add-tags");
    assert!(add_tags.disabled);
    assert_eq!(
        add_tags.disabled_reason.as_deref(),
        Some("Select files first.")
    );
    assert!(!add_tags.requires_confirmation);

    let stale = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            selected_file_ids: vec![active_id, deleted_id],
            ..default_context()
        },
    )
    .expect("list stale selection command targets");
    let stale_delete = find_target(&stale.current_selection_targets, "selection.delete");
    assert!(stale_delete.disabled);
    assert_eq!(
        stale_delete.disabled_reason.as_deref(),
        Some("Selected files are unavailable.")
    );
    assert!(stale_delete.requires_confirmation);
}

#[test]
fn command_index_implementation_omits_file_candidates_unless_requested() {
    let repo = initialized_repo();
    insert_file(repo.path(), "finance/report.pdf", "finance", 100);

    let index = list_command_targets(path_string(repo.path()), default_context())
        .expect("list command targets without file candidates");

    assert!(index.file_candidates.is_empty());
    assert!(!index.commands.is_empty());
    assert!(!index.navigation_targets.is_empty());
}

#[test]
fn command_index_implementation_db_failures_preserve_user_files() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("finance/report.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create user dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    let metadata = repo.path().join(".areamatrix");
    fs::create_dir(&metadata).expect("create metadata directory");
    fs::create_dir(metadata.join("staging")).expect("create staging directory");
    fs::create_dir(metadata.join("generated")).expect("create generated directory");
    fs::write(metadata.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database fixture");

    assert_db_error(list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            query: Some("report".to_owned()),
            include_file_candidates: true,
            ..default_context()
        },
    ));

    assert_eq!(
        fs::read(&user_file).expect("read user file after failure"),
        b"user file bytes"
    );
    assert!(relative_directory_entries(repo.path(), &metadata.join("staging")).is_empty());
    assert!(relative_directory_entries(repo.path(), &metadata.join("generated")).is_empty());
}
