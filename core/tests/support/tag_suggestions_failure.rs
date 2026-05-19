use std::{fs, path::Path};

use area_matrix_core::{
    apply_tag_suggestions, init_repo, suggest_tags_for_file, ApplyTagSuggestionItem,
    ApplyTagSuggestionsRequest, CoreError, ErrorKind, ErrorRecoverability, OverviewOutput,
    RepoInitMode, RepoInitOptions, TagSuggestionRequest,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct TagSuggestionSnapshot {
    pub(crate) files: Vec<(i64, String, String)>,
    pub(crate) tags: Vec<(i64, String)>,
    pub(crate) change_logs: Vec<(i64, String, String)>,
    pub(crate) undo_actions: Vec<(String, String, String)>,
    pub(crate) staging_entries: Vec<String>,
    pub(crate) generated_entries: Vec<String>,
    pub(crate) user_visible_paths: Vec<String>,
}

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
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

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn insert_file(
    repo: &Path,
    relative_path: &str,
    status: &str,
    source_path: Option<&str>,
) -> i64 {
    let file_path = repo.join(relative_path);
    if status == "active" {
        fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
            .expect("create fixture directory");
        fs::write(&file_path, format!("fixture bytes for {relative_path}"))
            .expect("write fixture file");
    }

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
                ?1, ?2, ?2, 'docs', 13,
                ?3, 'copied', 'imported', ?4,
                100, 100, ?5
             )",
            params![
                relative_path,
                current_name,
                format!("{:064x}", relative_path.len()),
                source_path,
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

pub(crate) fn insert_tag(repo: &Path, file_id: i64, tag: &str, added_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, ?3)",
            params![file_id, tag, added_at],
        )
        .expect("insert tag row");
}

pub(crate) fn snapshot(repo: &Path) -> TagSuggestionSnapshot {
    TagSuggestionSnapshot {
        files: file_rows(repo),
        tags: tag_rows(repo),
        change_logs: change_log_rows(repo),
        undo_actions: undo_action_rows(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

pub(crate) fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tag rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

pub(crate) fn change_log_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change-log rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query change-log rows")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

pub(crate) fn undo_action_rows(repo: &Path) -> Vec<(String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT token, kind, status FROM undo_actions ORDER BY token")
        .expect("prepare undo rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query undo rows")
        .map(|row| row.expect("read undo row"))
        .collect()
}

pub(crate) fn relative_directory_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_relative_paths(repo, root, &mut entries);
    }
    entries.sort();
    entries
}

pub(crate) fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        paths.push(relative_path(repo, &path));
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = relative_path(repo, &path);
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path is inside repository")
        .to_string_lossy()
        .into_owned()
}

pub(crate) fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}

pub(crate) fn assert_file_not_found<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with FileNotFound");
    assert!(matches!(error, CoreError::FileNotFound { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::FileNotFound);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::RefreshRequired
    );
}

pub(crate) fn assert_validation<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Validation");
    assert!(matches!(error, CoreError::Validation { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Validation);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

pub(crate) fn assert_conflict<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Conflict");
    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Conflict);
}

pub(crate) fn request(file_id: i64) -> TagSuggestionRequest {
    TagSuggestionRequest {
        file_id,
        context: None,
        limit: 8,
    }
}

pub(crate) fn apply_request(file_id: i64, slug: &str) -> ApplyTagSuggestionsRequest {
    ApplyTagSuggestionsRequest {
        file_id,
        suggestions: vec![ApplyTagSuggestionItem {
            suggestion_id: format!("suggestion:test:{slug}"),
            slug: slug.to_owned(),
            display_name: slug.to_owned(),
        }],
    }
}

pub(crate) fn install_tag_suggestion_change_log_failure(repo: &Path, tag: &str) {
    let sql = format!(
        "CREATE TRIGGER fail_tag_suggestion_change_log
         BEFORE INSERT ON change_log
         WHEN NEW.action = 'external_modified'
          AND json_extract(NEW.detail_json, '$.kind') = 'tag_suggestion_applied'
          AND json_extract(NEW.detail_json, '$.tag') = '{tag}'
         BEGIN
           SELECT RAISE(ABORT, 'forced tag suggestion change_log failure');
         END;"
    );
    open_db(repo)
        .execute_batch(&sql)
        .expect("install tag suggestion change-log failure trigger");
}

pub(crate) fn install_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_tag_suggestion_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'batch_add_tags'
              AND json_extract(NEW.summary_json, '$.kind') = 'tag_suggestions'
             BEGIN
               SELECT RAISE(ABORT, 'forced tag suggestion undo failure');
             END;",
        )
        .expect("install undo action failure trigger");
}

pub(crate) fn suggest(
    repo: &Path,
    request: TagSuggestionRequest,
) -> Result<area_matrix_core::TagSuggestionReport, CoreError> {
    suggest_tags_for_file(path_string(repo), request)
}

pub(crate) fn apply(
    repo: &Path,
    request: ApplyTagSuggestionsRequest,
) -> Result<area_matrix_core::TagSuggestionApplyReport, CoreError> {
    apply_tag_suggestions(path_string(repo), request)
}
