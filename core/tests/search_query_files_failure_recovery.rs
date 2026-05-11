use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, search_files, write_note, CoreError, ErrorKind, OverviewOutput, RepoInitMode,
    RepoInitOptions, SearchDiagnosticKind, SearchFilter, SearchIndexStatus, SearchPagination,
    SearchScope, SearchSort,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

fn default_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: Vec::new(),
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        include_deleted: Some(false),
    }
}

fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

fn insert_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    imported_at: i64,
    updated_at: i64,
) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"search fixture bytes").expect("write file fixture");

    let current_name = relative_path.rsplit('/').next().expect("path has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 20,
                ?4, 'copied', 'imported', NULL,
                ?5, ?6, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
                imported_at,
                updated_at,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, detail: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, 200)",
            params![file_id, action, detail],
        )
        .expect("insert change-log row");
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repo")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect();
    entries.sort();
    entries
}

fn generated_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/generated"))
        .expect("read generated directory")
        .map(|entry| entry.expect("read generated entry").path())
        .collect()
}

fn assert_search_left_repo_unchanged(
    repo: &Path,
    before_files: &[(i64, String, String, String)],
    before_changes: i64,
    before_visible_paths: &[String],
) {
    assert_eq!(file_rows(repo), before_files);
    assert_eq!(change_log_count(repo), before_changes);
    assert_eq!(user_visible_paths(repo), before_visible_paths);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

#[test]
fn search_query_files_failure_recovery_empty_repo_returns_empty_page() {
    let repo = initialized_repo();

    let page = search_files(
        path_string(repo.path()),
        "anything".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search empty repository");

    assert_eq!(page.query, "anything");
    assert_eq!(page.total_count, 0);
    assert!(page.results.is_empty());
    assert!(page.diagnostics.is_empty());
    assert_eq!(page.index_status, SearchIndexStatus::Ready);
    assert_eq!(
        file_rows(repo.path()),
        Vec::<(i64, String, String, String)>::new()
    );
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn search_query_files_failure_recovery_invalid_inputs_are_structured_config_errors() {
    let repo = initialized_repo();
    let mut invalid_category = default_filter();
    invalid_category.category = Some("   ".to_owned());
    let mut invalid_kind = default_filter();
    invalid_kind.file_kind = Some("../pdf".to_owned());
    let mut invalid_tag = default_filter();
    invalid_tag.tags = vec!["finance".to_owned(), " ".to_owned()];
    let mut invalid_range = default_filter();
    invalid_range.imported_after = Some(200);
    invalid_range.imported_before = Some(100);

    for (filter, pagination) in [
        (invalid_category, first_page()),
        (invalid_kind, first_page()),
        (invalid_tag, first_page()),
        (invalid_range, first_page()),
        (
            default_filter(),
            SearchPagination {
                limit: 0,
                offset: 0,
            },
        ),
        (
            default_filter(),
            SearchPagination {
                limit: 1001,
                offset: 0,
            },
        ),
        (
            default_filter(),
            SearchPagination {
                limit: 50,
                offset: -1,
            },
        ),
    ] {
        let result = search_files(
            path_string(repo.path()),
            "report".to_owned(),
            filter,
            SearchSort::Relevance,
            pagination,
        );

        assert!(
            matches!(result, Err(CoreError::Config { .. })),
            "expected Config error, got {result:?}"
        );
    }
}

#[test]
fn search_query_files_failure_recovery_parse_errors_do_not_execute_or_mutate() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/report.pdf", "docs", 100, 100);
    insert_change(
        repo.path(),
        file_id,
        "renamed",
        r#"{"from":"draft","to":"report"}"#,
    );
    let before_files = file_rows(repo.path());
    let before_changes = change_log_count(repo.path());
    let before_visible_paths = user_visible_paths(repo.path());

    let page = search_files(
        path_string(repo.path()),
        "kindd:pdf after:2026-13-01 (".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("parse diagnostics are returned without repository mutation");

    assert_eq!(page.total_count, 0);
    assert!(page.results.is_empty());
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::UnknownField));
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::InvalidDate));
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::UnbalancedParentheses));
    assert_search_left_repo_unchanged(
        repo.path(),
        &before_files,
        before_changes,
        &before_visible_paths,
    );
}

#[test]
fn search_query_files_failure_recovery_escaped_and_quoted_colons_are_plain_keywords() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/foo-bar.txt", "docs", 100, 100);
    write_note(
        path_string(repo.path()),
        file_id,
        "contains foo:bar literal".to_owned(),
    )
    .expect("write searchable note");

    let escaped = search_files(
        path_string(repo.path()),
        r"foo\:bar".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("escaped colon stays a keyword");
    let quoted = search_files(
        path_string(repo.path()),
        r#""foo:bar""#.to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("quoted colon stays a keyword");

    assert_eq!(escaped.total_count, 1);
    assert_eq!(escaped.results[0].entry.id, file_id);
    assert!(escaped.diagnostics.is_empty());
    assert_eq!(quoted.total_count, 1);
    assert_eq!(quoted.results[0].entry.id, file_id);
    assert!(quoted.diagnostics.is_empty());
}

#[test]
fn search_query_files_failure_recovery_metadata_errors_map_to_declared_db_error() {
    let repo = initialized_repo();
    open_db(repo.path())
        .execute_batch("DROP TABLE files;")
        .expect("simulate database metadata corruption");

    let result = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
}

#[test]
fn search_query_files_failure_recovery_only_reads_metadata_and_user_files() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/report.pdf", "docs", 100, 100);
    write_note(
        path_string(repo.path()),
        file_id,
        "searchable note".to_owned(),
    )
    .expect("write searchable note");
    let before_files = file_rows(repo.path());
    let before_changes = change_log_count(repo.path());
    let before_visible_paths = user_visible_paths(repo.path());
    let before_generated = generated_entries(repo.path());

    let page = search_files(
        path_string(repo.path()),
        "searchable".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search note without mutating state");

    assert_eq!(page.total_count, 1);
    assert_eq!(page.results[0].entry.id, file_id);
    assert_search_left_repo_unchanged(
        repo.path(),
        &before_files,
        before_changes,
        &before_visible_paths,
    );
    assert_eq!(generated_entries(repo.path()), before_generated);
}

#[test]
fn search_query_files_failure_recovery_error_mapping_is_structured_for_ui_retry() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    let result = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    );
    let error = result.expect_err("uninitialized search maps to declared Db error");
    let mapping = error.to_error_mapping();

    assert_eq!(mapping.kind, ErrorKind::Db);
    assert!(!mapping.user_message.is_empty());
    assert!(!mapping.suggested_action.is_empty());
    assert!(!mapping.raw_context.is_empty());
}

#[test]
fn search_query_files_failure_recovery_has_no_remote_ai_or_secret_side_effects() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/local-only.txt", "docs", 100, 100);
    let before_files = file_rows(repo.path());
    let before_changes = change_log_count(repo.path());
    let before_visible_paths = user_visible_paths(repo.path());

    let page = search_files(
        path_string(repo.path()),
        "local".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("local-only search succeeds");

    assert_eq!(page.total_count, 1);
    assert_eq!(page.index_status, SearchIndexStatus::Ready);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_search_left_repo_unchanged(
        repo.path(),
        &before_files,
        before_changes,
        &before_visible_paths,
    );
}

#[test]
fn search_query_files_failure_recovery_udl_keeps_declared_error_boundary() {
    let udl = include_str!("../area_matrix.udl");
    let search_rs = include_str!("../src/search.rs");
    let core_api = include_str!("../../docs/api/core-api.md");

    for fragment in [
        "[Throws=CoreError]",
        "SearchResultPage search_files(",
        "PermissionDenied(string path);",
        "Config(string reason);",
        "Db(string message);",
        "InvalidPath(string path);",
    ] {
        assert!(udl.contains(fragment), "UDL missing `{fragment}`");
    }
    for fragment in [
        "This contract does not include C2-02 facet counts",
        "remote AI",
        "must not modify tags, categories, notes, change log",
        "`CoreError::Config { reason }`",
        "`CoreError::Db { message }`",
        "`CoreError::InvalidPath { path }`",
    ] {
        assert!(
            search_rs.contains(fragment),
            "search rustdoc missing `{fragment}`"
        );
    }
    for fragment in [
        "`InvalidPath`",
        "`Config`",
        "`Db`",
        "该 API 只读，不写 DB，不写 `change_log`",
        "OCR、文件内容全文、语义搜索和远程 AI 属于 Stage 3",
    ] {
        assert!(
            core_api.contains(fragment),
            "Core API docs missing `{fragment}`"
        );
    }
}

#[cfg(unix)]
#[test]
fn search_query_files_failure_recovery_db_permission_denied_maps_to_declared_db_error() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    insert_file(repo.path(), "docs/locked-db.pdf", "docs", 100, 100);
    let before_files = file_rows(repo.path());
    let before_changes = change_log_count(repo.path());
    let before_visible_paths = user_visible_paths(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read db permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&db_path, denied_permissions).expect("remove db read permissions");

    if fs::File::open(&db_path).is_ok() {
        fs::set_permissions(&db_path, original_permissions).expect("restore db permissions");
        return;
    }

    let result = search_files(
        path_string(repo.path()),
        "locked".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    );

    fs::set_permissions(&db_path, original_permissions).expect("restore db permissions");

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(file_rows(repo.path()), before_files);
    assert_eq!(change_log_count(repo.path()), before_changes);
    assert_eq!(user_visible_paths(repo.path()), before_visible_paths);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[cfg(unix)]
#[test]
fn search_query_files_failure_recovery_permission_denied_keeps_state() {
    use std::{io, os::unix::fs::PermissionsExt};

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "blocked/secret.pdf", "docs", 100, 100);
    let blocked_dir = repo.path().join("blocked");
    let blocked_path = blocked_dir.join("secret.pdf");
    let before_files = file_rows(repo.path());
    let before_changes = change_log_count(repo.path());
    let before_visible_paths = user_visible_paths(repo.path());
    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked directory permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, denied_permissions).expect("remove directory permissions");

    let metadata_error = match fs::symlink_metadata(&blocked_path) {
        Ok(_) => {
            fs::set_permissions(&blocked_dir, original_permissions)
                .expect("restore directory permissions");
            return;
        }
        Err(error) => error,
    };
    if metadata_error.kind() != io::ErrorKind::PermissionDenied {
        fs::set_permissions(&blocked_dir, original_permissions)
            .expect("restore directory permissions");
        return;
    }

    let result = search_files(
        path_string(repo.path()),
        "secret".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    );

    fs::set_permissions(&blocked_dir, original_permissions).expect("restore directory permissions");

    assert!(
        matches!(
            result,
            Ok(area_matrix_core::SearchResultPage { .. })
                | Err(CoreError::PermissionDenied { .. })
                | Err(CoreError::Db { .. })
        ),
        "unexpected permission result: {result:?}"
    );
    assert_eq!(file_rows(repo.path()), before_files);
    assert_eq!(change_log_count(repo.path()), before_changes);
    assert_eq!(user_visible_paths(repo.path()), before_visible_paths);
    assert_eq!(
        fs::read(blocked_path).expect("blocked file is readable after permission restore"),
        b"search fixture bytes"
    );
    assert!(file_rows(repo.path()).iter().any(|row| row.0 == file_id));
}
