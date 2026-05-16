use std::{fs, path::Path};

use area_matrix_core::{
    add_tag, init_repo, list_changes, list_tags, remove_tag, ChangeFilter, CoreError,
    OverviewOutput, RepoInitMode, RepoInitOptions,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file(repo: &Path, relative_path: &str, category: &str, status: &str) -> i64 {
    let file_path = repo.join(relative_path);
    if status == "active" {
        fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
            .expect("create fixture directory");
        fs::write(&file_path, b"fixture bytes").expect("write fixture file");
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
                ?1, ?2, ?2, ?3, 13,
                ?4, 'copied', 'imported', NULL,
                100, 100, ?5
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str, added_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, ?3)",
            params![file_id, tag, added_at],
        )
        .expect("insert tag row");
}

fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tags query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tags")
        .map(|row| row.expect("read tag row"))
        .collect()
}

fn latest_change_detail(repo: &Path, file_id: i64, action: &str) -> serde_json::Value {
    let detail: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = ?2
             ORDER BY occurred_at DESC, id DESC
             LIMIT 1",
            params![file_id, action],
            |row| row.get(0),
        )
        .expect("read latest change-log detail");
    serde_json::from_str(&detail).expect("tag change detail is valid JSON")
}

fn tag_change_count(repo: &Path, file_id: i64, kind: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*)
               FROM change_log
              WHERE file_id = ?1
                AND action = 'external_modified'
                AND json_extract(detail_json, '$.kind') = ?2",
            params![file_id, kind],
            |row| row.get(0),
        )
        .expect("count tag change rows")
}

fn default_change_filter(file_id: i64, action: &str) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: Some(action.to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

#[test]
fn tag_crud_implementation_adds_normalized_tag_and_returns_refresh_snapshot() {
    let repo = initialized_repo();
    let target_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    let other_id = insert_file(repo.path(), "finance/invoice.pdf", "finance", "active");
    insert_tag(repo.path(), other_id, "urgent", 300);

    let tags = add_tag(path_string(repo.path()), target_id, " ClientA ".to_owned())
        .expect("add tag to active file");

    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (target_id, "clienta".to_owned()),
            (other_id, "urgent".to_owned())
        ]
    );
    assert_eq!(tags.file_id, target_id);
    assert_eq!(
        tags.file_tags
            .iter()
            .map(|record| (record.value.as_str(), record.selected))
            .collect::<Vec<_>>(),
        vec![("clienta", true)]
    );
    assert_eq!(
        tags.available_tags
            .iter()
            .map(|record| (record.value.as_str(), record.file_count, record.selected))
            .collect::<Vec<_>>(),
        vec![("clienta", 1, true), ("urgent", 1, false)]
    );
    assert_eq!(tags.recent_tags[0].value, "clienta");
    assert!(tags.updated_at > 0);

    let detail = latest_change_detail(repo.path(), target_id, "external_modified");
    assert_eq!(detail["kind"], "tag_added");
    assert_eq!(detail["tag"], "clienta");
    assert_eq!(detail["changed"], true);
    assert_eq!(detail["by"], "user");
}

#[test]
fn tag_crud_implementation_duplicate_add_and_missing_remove_are_idempotent() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");

    add_tag(path_string(repo.path()), file_id, "urgent".to_owned()).expect("add tag once");
    let duplicate = add_tag(path_string(repo.path()), file_id, "Urgent".to_owned())
        .expect("duplicate add is idempotent");
    let missing_remove = remove_tag(path_string(repo.path()), file_id, "missing".to_owned())
        .expect("missing remove is idempotent");

    assert_eq!(tag_rows(repo.path()), vec![(file_id, "urgent".to_owned())]);
    assert_eq!(tag_change_count(repo.path(), file_id, "tag_added"), 1);
    assert_eq!(tag_change_count(repo.path(), file_id, "tag_removed"), 0);
    assert_eq!(duplicate.file_tags[0].value, "urgent");
    assert_eq!(missing_remove.file_tags[0].value, "urgent");
}

#[test]
fn tag_crud_implementation_removes_only_target_relation_and_keeps_registry_counts() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    let second_id = insert_file(repo.path(), "finance/invoice.pdf", "finance", "active");
    insert_tag(repo.path(), first_id, "urgent", 100);
    insert_tag(repo.path(), second_id, "urgent", 200);
    insert_tag(repo.path(), first_id, "clienta", 300);

    let tags = remove_tag(path_string(repo.path()), first_id, "urgent".to_owned())
        .expect("remove one relation");

    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (first_id, "clienta".to_owned()),
            (second_id, "urgent".to_owned())
        ]
    );
    assert_eq!(
        tags.file_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["clienta"]
    );
    assert_eq!(
        tags.available_tags
            .iter()
            .map(|record| (record.value.as_str(), record.file_count, record.selected))
            .collect::<Vec<_>>(),
        vec![("clienta", 1, true), ("urgent", 1, false)]
    );
    assert_eq!(tag_change_count(repo.path(), first_id, "tag_removed"), 1);
    assert_eq!(tag_change_count(repo.path(), second_id, "tag_removed"), 0);
}

#[test]
fn tag_crud_implementation_list_is_read_only_and_stable_sorted() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    let other_id = insert_file(repo.path(), "finance/invoice.pdf", "finance", "active");
    insert_tag(repo.path(), file_id, "zeta", 100);
    insert_tag(repo.path(), file_id, "alpha", 200);
    insert_tag(repo.path(), other_id, "beta", 300);
    let before_tags = tag_rows(repo.path());

    let tags = list_tags(path_string(repo.path()), file_id).expect("list tag set");

    assert_eq!(tag_rows(repo.path()), before_tags);
    assert_eq!(tag_change_count(repo.path(), file_id, "tag_added"), 0);
    assert_eq!(
        tags.file_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["alpha", "zeta"]
    );
    assert_eq!(
        tags.available_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["alpha", "beta", "zeta"]
    );
    assert_eq!(
        tags.recent_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["beta", "alpha", "zeta"]
    );
}

#[test]
fn tag_crud_implementation_maps_invalid_input_and_missing_files() {
    let repo = initialized_repo();
    let deleted_id = insert_file(repo.path(), "docs/deleted.pdf", "docs", "deleted");

    assert!(matches!(
        add_tag(path_string(repo.path()), deleted_id, "urgent".to_owned()),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        add_tag(path_string(repo.path()), 1, "bad/tag".to_owned()),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        remove_tag(path_string(repo.path()), 1, "bad:tag".to_owned()),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        add_tag(
            path_string(&repo.path().join(".areamatrix")),
            1,
            "urgent".to_owned()
        ),
        Err(CoreError::InvalidPath { .. })
    ));
}

#[test]
fn tag_crud_implementation_change_log_entries_are_queryable() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");

    add_tag(path_string(repo.path()), file_id, "urgent".to_owned()).expect("add tag");
    remove_tag(path_string(repo.path()), file_id, "urgent".to_owned()).expect("remove tag");

    let changes = list_changes(
        path_string(repo.path()),
        default_change_filter(file_id, "external_modified"),
    )
    .expect("list tag changes");

    assert_eq!(changes.len(), 2);
    assert!(changes
        .iter()
        .all(|change| change.action == "external_modified"));
    assert!(changes
        .iter()
        .any(|change| change.detail_json.contains("\"kind\":\"tag_added\"")));
    assert!(changes
        .iter()
        .any(|change| change.detail_json.contains("\"kind\":\"tag_removed\"")));
}
