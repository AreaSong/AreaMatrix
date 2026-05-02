use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_changes, rename_file, ChangeFilter, CoreError, DuplicateStrategy,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn default_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn count_file_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows by status")
}

fn count_change_logs(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn insert_file(repo: &Path, path: &str, category: &str, imported_at: i64) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has a filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 1,
                ?4, 'copied', 'imported', NULL,
                ?5, ?5, 'active'
             )",
            params![
                path,
                current_name,
                category,
                format!("{imported_at:064x}"),
                imported_at,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, detail: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![file_id, action, detail, occurred_at],
        )
        .expect("insert change-log row");
}

fn actions(changes: &[area_matrix_core::ChangeLogEntry]) -> Vec<&str> {
    changes
        .iter()
        .map(|change| change.action.as_str())
        .collect()
}

fn assert_detail_json_objects(changes: &[area_matrix_core::ChangeLogEntry]) {
    for change in changes {
        let detail = serde_json::from_str::<Value>(&change.detail_json).expect("parse detail_json");
        assert!(
            detail.is_object(),
            "detail_json for action `{}` must be an object",
            change.action
        );
    }
}

#[test]
fn list_change_log_validation_reads_real_import_and_rename_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_bytes = fs::read(&source).expect("read source before import");
    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import copied file for change-log validation");
    let renamed = rename_file(
        path_string(repo.path()),
        imported.id,
        "invoice-final.pdf".to_owned(),
    )
    .expect("rename imported file for change-log validation");
    let before_change_logs = count_change_logs(repo.path());
    let before_active_files = count_file_rows(repo.path(), "active");
    let before_staging = staging_entries(repo.path());

    let mut filter = default_filter();
    filter.file_id = Some(imported.id);
    let changes = list_changes(path_string(repo.path()), filter).expect("list file changes");

    assert_eq!(actions(&changes), vec!["renamed", "imported"]);
    assert_eq!(changes[0].filename, "invoice-final.pdf");
    assert_eq!(changes[0].category, "finance");
    assert_eq!(changes[1].category, "finance");
    assert_detail_json_objects(&changes);
    assert_eq!(
        fs::read(&source).expect("read source after list_changes"),
        source_bytes
    );
    assert_eq!(
        fs::read(repo.path().join(&renamed.path)).expect("read renamed repo file"),
        source_bytes
    );
    assert_eq!(count_change_logs(repo.path()), before_change_logs);
    assert_eq!(count_file_rows(repo.path(), "active"), before_active_files);
    assert_eq!(staging_entries(repo.path()), before_staging);
}

#[test]
fn list_change_log_validation_filters_orders_paginates_and_keeps_details_parseable() {
    let repo = initialized_repo();
    let finance_id = insert_file(repo.path(), "finance/report.pdf", "finance", 10);
    let docs_id = insert_file(repo.path(), "docs/spec.pdf", "docs", 20);
    for (action, occurred_at) in [
        ("imported", 10),
        ("renamed", 20),
        ("moved", 30),
        ("edited_note", 40),
        ("external_modified", 50),
    ] {
        insert_change(
            repo.path(),
            finance_id,
            action,
            r#"{"by":"validation","source":"c1-13"}"#,
            occurred_at,
        );
    }
    insert_change(
        repo.path(),
        docs_id,
        "imported",
        r#"{"by":"validation","source":"other-category"}"#,
        60,
    );

    let all_changes =
        list_changes(path_string(repo.path()), default_filter()).expect("list all changes");
    assert_eq!(
        actions(&all_changes),
        vec![
            "imported",
            "external_modified",
            "edited_note",
            "moved",
            "renamed",
            "imported"
        ]
    );
    assert_detail_json_objects(&all_changes);

    let mut exact_filter = default_filter();
    exact_filter.file_id = Some(finance_id);
    exact_filter.category = Some("finance".to_owned());
    exact_filter.action = Some("moved".to_owned());
    exact_filter.since = Some(25);
    exact_filter.until = Some(35);
    let exact = list_changes(path_string(repo.path()), exact_filter).expect("filter exactly");
    assert_eq!(actions(&exact), vec!["moved"]);

    let mut paged_filter = default_filter();
    paged_filter.category = Some("finance".to_owned());
    paged_filter.limit = 2;
    paged_filter.offset = 1;
    let paged = list_changes(path_string(repo.path()), paged_filter).expect("list paged changes");
    assert_eq!(actions(&paged), vec!["edited_note", "moved"]);
}

#[test]
fn list_change_log_validation_returns_documented_errors() {
    let uninitialized_repo = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        list_changes(path_string(uninitialized_repo.path()), default_filter()),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/bad.pdf", "finance", 10);
    insert_change(repo.path(), file_id, "imported", "not-json", 100);

    assert!(matches!(
        list_changes(path_string(repo.path()), default_filter()),
        Err(CoreError::Db { .. })
    ));

    let repo = initialized_repo();
    open_db(repo.path())
        .execute_batch("DROP TABLE change_log;")
        .expect("drop change_log table to simulate metadata corruption");

    assert!(matches!(
        list_changes(path_string(repo.path()), default_filter()),
        Err(CoreError::Db { .. })
    ));
}
