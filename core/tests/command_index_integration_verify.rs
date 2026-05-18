use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_command_targets, CommandIndexContext, CommandTarget, CommandTargetAction,
    CommandTargetGroup, CommandTargetKind, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

#[derive(Debug, Eq, PartialEq)]
struct CommandIndexIntegrationSnapshot {
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

fn default_context() -> CommandIndexContext {
    CommandIndexContext {
        query: None,
        selected_file_ids: Vec::new(),
        current_path: None,
        include_file_candidates: false,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
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

fn snapshot(repo: &Path) -> CommandIndexIntegrationSnapshot {
    CommandIndexIntegrationSnapshot {
        recent_commands: recent_command_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        undo_action_count: table_count(repo, "undo_actions"),
        tag_count: table_count(repo, "tags"),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_file_bytes: user_file_bytes(repo),
    }
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

#[test]
fn command_index_integration_verify_reads_recent_metadata_without_writes() {
    let repo = initialized_repo();
    insert_recent_commands(
        repo.path(),
        &[
            ("command.open-classifier-rules", 400, 3),
            ("command.redo-latest-action", 300, 1),
            ("command.missing", 100, 9),
        ],
    );
    let before = snapshot(repo.path());

    let index = list_command_targets(path_string(repo.path()), default_context())
        .expect("list command index for recent metadata");

    assert_eq!(
        index
            .recent_targets
            .iter()
            .map(|target| (target.id.as_str(), target.route.as_deref()))
            .collect::<Vec<_>>(),
        vec![
            ("recent:command.open-classifier-rules", Some("S2-19")),
            ("recent:command.redo-latest-action", Some("S2-22")),
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
fn command_index_integration_verify_covers_s2_15_command_entries() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let index = list_command_targets(path_string(repo.path()), default_context())
        .expect("list command index for S2-15 entries");

    assert_route(
        &index.commands,
        "command.redo-latest-action",
        "S2-22",
        CommandTargetAction::Navigate,
        false,
    );
    assert_route(
        &index.commands,
        "command.review-import-conflicts",
        "S2-21",
        CommandTargetAction::OpenConfirmation,
        true,
    );
    assert_route(
        &index.commands,
        "command.review-tag-suggestions",
        "S2-23",
        CommandTargetAction::Navigate,
        false,
    );
    assert_route(
        &index.commands,
        "command.open-classifier-rules",
        "S2-19",
        CommandTargetAction::Navigate,
        false,
    );
    assert_route(
        &index.commands,
        "command.preview-classifier-rule-impact",
        "S2-18",
        CommandTargetAction::OpenConfirmation,
        true,
    );
    assert_route(
        &index.commands,
        "command.apply-classifier-rule",
        "S2-18",
        CommandTargetAction::OpenConfirmation,
        true,
    );

    let redo = find_target(&index.commands, "command.redo-latest-action");
    assert!(redo.disabled);
    assert_eq!(
        redo.disabled_reason.as_deref(),
        Some("Redo stack is unavailable.")
    );

    let apply = find_target(&index.commands, "command.apply-classifier-rule");
    assert!(apply.disabled);
    assert_eq!(
        apply.disabled_reason.as_deref(),
        Some("Open classifier rules first.")
    );
    assert_eq!(snapshot(repo.path()), before);
}

fn assert_route(
    targets: &[CommandTarget],
    id: &str,
    route: &str,
    action: CommandTargetAction,
    requires_confirmation: bool,
) {
    let target = find_target(targets, id);
    assert_eq!(target.route.as_deref(), Some(route));
    assert_eq!(target.action, action);
    assert_eq!(target.requires_confirmation, requires_confirmation);
}
