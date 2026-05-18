use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_command_targets, CommandIndexContext, CommandTarget, CommandTargetAction,
    CoreError, ErrorKind, ErrorRecoverability, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct CommandIndexFailureSnapshot {
    files: Vec<(i64, String, String, String, i64)>,
    saved_search_count: i64,
    change_log_count: i64,
    undo_action_count: i64,
    tag_count: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_file_bytes: Vec<(String, Vec<u8>)>,
    recent_commands_table_exists: bool,
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

fn snapshot(repo: &Path) -> CommandIndexFailureSnapshot {
    CommandIndexFailureSnapshot {
        files: file_rows(repo),
        saved_search_count: table_count(repo, "saved_searches"),
        change_log_count: table_count(repo, "change_log"),
        undo_action_count: table_count(repo, "undo_actions"),
        tag_count: table_count(repo, "tags"),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_file_bytes: user_file_bytes(repo),
        recent_commands_table_exists: table_exists(repo, "recent_commands"),
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

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count metadata rows")
}

fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1
             )",
            [table],
            |row| row.get::<_, i64>(0),
        )
        .expect("query table existence")
        == 1
}

fn relative_directory_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_relative_paths(repo, root, &mut entries);
    }
    entries.sort();
    entries
}

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let path = entry.expect("read directory entry").path();
        paths.push(
            path.strip_prefix(repo)
                .expect("path is inside repository")
                .to_string_lossy()
                .into_owned(),
        );
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
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

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}

fn assert_no_private_or_remote_state(repo: &Path) {
    for name in ["ai", "remote", "secrets"] {
        assert!(
            !repo.join(".areamatrix").join(name).exists(),
            "command index must not create .areamatrix/{name}"
        );
    }
}

#[test]
fn command_index_failure_recovery_empty_repo_returns_empty_groups_without_writes() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let index = list_command_targets(path_string(repo.path()), default_context())
        .expect("list empty command index");

    assert!(!index.commands.is_empty());
    assert!(!index.navigation_targets.is_empty());
    assert!(index.smart_lists.is_empty());
    assert!(index.file_candidates.is_empty());
    assert!(index.recent_targets.is_empty());
    assert!(index.generated_at > 0);
    let add_tags = find_target(&index.current_selection_targets, "selection.add-tags");
    assert!(add_tags.disabled);
    assert_eq!(
        add_tags.disabled_reason.as_deref(),
        Some("Select files first.")
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn command_index_failure_recovery_invalid_inputs_are_db_and_non_mutating() {
    let repo = initialized_repo();
    insert_file(repo.path(), "finance/report.pdf", "finance", 100);
    let before = snapshot(repo.path());
    let repo_path = path_string(repo.path());

    assert_db_error(list_command_targets(String::new(), default_context()));
    assert_db_error(list_command_targets(
        path_string(&repo.path().join(".areamatrix")),
        default_context(),
    ));

    for file_ids in [vec![0], vec![-1]] {
        assert_db_error(list_command_targets(
            repo_path.clone(),
            CommandIndexContext {
                selected_file_ids: file_ids,
                ..default_context()
            },
        ));
    }

    for current_path in [
        "",
        "../outside",
        "/tmp/outside",
        ".areamatrix",
        "docs/.areamatrix/private",
        "docs/has\0nul",
    ] {
        assert_db_error(list_command_targets(
            repo_path.clone(),
            CommandIndexContext {
                current_path: Some(current_path.to_owned()),
                ..default_context()
            },
        ));
    }

    assert_db_error(list_command_targets(
        repo_path,
        CommandIndexContext {
            query: Some("bad\0query".to_owned()),
            ..default_context()
        },
    ));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn command_index_failure_recovery_selection_and_file_candidate_db_failures_preserve_files() {
    let repo = initialized_repo();
    let user_file = repo.path().join("finance/report.pdf");
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance", 100);
    open_db(repo.path())
        .execute_batch("DROP TABLE saved_searches;")
        .expect("simulate command registry metadata corruption");
    let staging_before =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    let generated_before =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated"));

    let error = assert_db_error(list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            selected_file_ids: vec![file_id],
            include_file_candidates: true,
            ..default_context()
        },
    ));

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert!(!error.to_error_mapping().raw_context.is_empty());
    assert_eq!(
        fs::read(user_file).expect("read user file after db failure"),
        b"fixture bytes for finance/report.pdf"
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        staging_before
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        generated_before
    );
    assert_no_private_or_remote_state(repo.path());
}

#[test]
fn command_index_failure_recovery_uninitialized_repo_does_not_create_metadata_or_user_files() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    let user_file = repo.path().join("finance/report.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create user dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");

    let error = assert_db_error(list_command_targets(
        path_string(repo.path()),
        default_context(),
    ));

    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    assert_eq!(
        fs::read(&user_file).expect("read user file after failure"),
        b"user file bytes"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn command_index_failure_recovery_corrupted_db_is_fatal_and_preserves_side_effect_boundaries() {
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

    let error = assert_db_error(list_command_targets(
        path_string(repo.path()),
        default_context(),
    ));

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(
        fs::read(user_file).expect("read user file after corrupted db failure"),
        b"user file bytes"
    );
    assert!(relative_directory_entries(repo.path(), &metadata.join("staging")).is_empty());
    assert!(relative_directory_entries(repo.path(), &metadata.join("generated")).is_empty());
    assert_no_private_or_remote_state(repo.path());
}

#[test]
fn command_index_failure_recovery_read_only_index_never_writes_recent_or_risky_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/local-report.txt", "docs", 200);
    let before = snapshot(repo.path());

    let index = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            selected_file_ids: vec![file_id],
            include_file_candidates: true,
            ..default_context()
        },
    )
    .expect("list command index");

    let delete = find_target(&index.current_selection_targets, "selection.delete");
    assert_eq!(delete.action, CommandTargetAction::OpenConfirmation);
    assert!(delete.requires_confirmation);
    assert!(index.recent_targets.is_empty());
    assert_no_private_or_remote_state(repo.path());
    assert_eq!(snapshot(repo.path()), before);
    assert!(!repo.path().join("AREAMATRIX.md").exists());
    assert!(!repo.path().join("README.md").exists());
}

#[cfg(unix)]
#[test]
fn command_index_failure_recovery_permission_denied_maps_to_db_without_mutation() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    insert_file(repo.path(), "finance/report.pdf", "finance", 100);
    let before = snapshot(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&db_path, denied_permissions).expect("remove database permissions");

    if fs::File::open(&db_path).is_ok() {
        fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");
        return;
    }

    let result = list_command_targets(
        path_string(repo.path()),
        CommandIndexContext {
            include_file_candidates: true,
            ..default_context()
        },
    );

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_eq!(snapshot(repo.path()), before);
}
