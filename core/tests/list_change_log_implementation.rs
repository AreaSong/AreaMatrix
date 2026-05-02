use std::path::Path;

use area_matrix_core::{
    init_repo, list_changes, ChangeFilter, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

fn insert_change(repo: &Path, file_id: Option<i64>, action: &str, detail: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![file_id, action, detail, occurred_at],
        )
        .expect("insert change-log row");
}

#[test]
fn list_change_log_implementation_empty_repo_returns_empty_array() {
    let repo = initialized_repo();

    let changes = list_changes(path_string(repo.path()), default_filter()).expect("list empty log");

    assert_eq!(changes, Vec::new());
}

#[test]
fn list_change_log_implementation_requires_initialized_repo() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    let result = list_changes(path_string(repo.path()), default_filter());

    assert_eq!(
        result,
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
}

#[test]
fn list_change_log_implementation_filters_by_file_category_action_and_time_window() {
    let repo = initialized_repo();
    let finance_id = insert_file(repo.path(), "finance/report.pdf", "finance", 10);
    let docs_id = insert_file(repo.path(), "docs/spec.pdf", "docs", 20);
    insert_change(
        repo.path(),
        Some(finance_id),
        "imported",
        r#"{"source":"/tmp/report.pdf","mode":"copied","by":"user"}"#,
        100,
    );
    insert_change(
        repo.path(),
        Some(finance_id),
        "renamed",
        r#"{"from_name":"draft.pdf","final_name":"report.pdf","by":"user"}"#,
        200,
    );
    insert_change(
        repo.path(),
        Some(docs_id),
        "moved",
        r#"{"from_category":"inbox","to_category":"docs","by":"user"}"#,
        300,
    );

    let mut filter = default_filter();
    filter.file_id = Some(finance_id);
    filter.category = Some("finance".to_owned());
    filter.action = Some("renamed".to_owned());
    filter.since = Some(150);
    filter.until = Some(250);

    let changes = list_changes(path_string(repo.path()), filter).expect("list filtered changes");

    assert_eq!(actions(&changes), vec!["renamed"]);
    assert_eq!(changes[0].file_id, Some(finance_id));
    assert_eq!(changes[0].filename, "report.pdf");
    assert_eq!(changes[0].category, "finance");
}

#[test]
fn list_change_log_implementation_queries_all_stage_one_action_kinds() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance", 10);
    for (action, occurred_at) in [
        ("imported", 10),
        ("renamed", 20),
        ("moved", 30),
        ("edited_note", 40),
        ("external_modified", 50),
    ] {
        insert_change(
            repo.path(),
            Some(file_id),
            action,
            r#"{"by":"test","kind":"query"}"#,
            occurred_at,
        );
    }

    let changes =
        list_changes(path_string(repo.path()), default_filter()).expect("list all action kinds");

    assert_eq!(
        actions(&changes),
        vec![
            "external_modified",
            "edited_note",
            "moved",
            "renamed",
            "imported"
        ]
    );
    for change in changes {
        serde_json::from_str::<serde_json::Value>(&change.detail_json)
            .expect("returned detail_json remains parseable JSON");
    }
}

#[test]
fn list_change_log_implementation_orders_by_occurred_at_desc_and_paginates() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", 10);
    for occurred_at in [10, 20, 30, 40] {
        insert_change(
            repo.path(),
            Some(file_id),
            "imported",
            r#"{"source":"/tmp/spec.pdf","by":"user"}"#,
            occurred_at,
        );
    }

    let mut filter = default_filter();
    filter.limit = 2;
    filter.offset = 1;

    let changes = list_changes(path_string(repo.path()), filter).expect("list paged changes");

    assert_eq!(
        changes
            .iter()
            .map(|change| change.occurred_at)
            .collect::<Vec<_>>(),
        vec![30, 20]
    );
}

#[test]
fn list_change_log_implementation_clamps_limit_and_negative_offset() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", 10);
    seed_many_changes(repo.path(), file_id, 1001);

    let mut filter = default_filter();
    filter.limit = 2000;
    filter.offset = -10;

    let changes = list_changes(path_string(repo.path()), filter).expect("list clamped changes");

    assert_eq!(changes.len(), 1000);
    assert_eq!(changes.first().map(|change| change.occurred_at), Some(1000));
    assert_eq!(changes.last().map(|change| change.occurred_at), Some(1));
}

#[test]
fn list_change_log_implementation_rejects_unparseable_or_non_object_detail_json() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance", 10);
    insert_change(repo.path(), Some(file_id), "imported", "not-json", 100);

    let result = list_changes(path_string(repo.path()), default_filter());

    assert!(matches!(result, Err(CoreError::Db { .. })));

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/array.pdf", "finance", 10);
    insert_change(repo.path(), Some(file_id), "imported", r#"[]"#, 100);

    let result = list_changes(path_string(repo.path()), default_filter());

    assert!(matches!(result, Err(CoreError::Db { .. })));
}

fn actions(changes: &[area_matrix_core::ChangeLogEntry]) -> Vec<&str> {
    changes
        .iter()
        .map(|change| change.action.as_str())
        .collect()
}

fn seed_many_changes(repo: &Path, file_id: i64, count: i64) {
    let mut connection = open_db(repo);
    let tx = connection.transaction().expect("start seed transaction");
    {
        let mut statement = tx
            .prepare(
                "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
                 VALUES (?1, 'imported', ?2, ?3)",
            )
            .expect("prepare seeded change insert");
        for index in 0..count {
            statement
                .execute(params![file_id, r#"{"by":"seed"}"#, index])
                .expect("insert seeded change");
        }
    }
    tx.commit().expect("commit seeded changes");
}
