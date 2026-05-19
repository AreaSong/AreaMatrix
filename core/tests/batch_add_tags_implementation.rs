use std::{fs, path::Path};

use area_matrix_core::{
    batch_add_tags, init_repo, BatchMutationStatus, OverviewOutput, RepoInitMode, RepoInitOptions,
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

fn change_rows(repo: &Path) -> Vec<(i64, serde_json::Value)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT file_id, detail_json
               FROM change_log
              WHERE action = 'external_modified'
              ORDER BY id",
        )
        .expect("prepare change-log query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(1)?;
            let parsed = serde_json::from_str(&detail).expect("change detail json is valid");
            Ok((row.get(0)?, parsed))
        })
        .expect("query change-log rows")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

fn undo_row(repo: &Path, token: &str) -> (String, String, serde_json::Value, serde_json::Value) {
    let connection = open_db(repo);
    connection
        .query_row(
            "SELECT kind, status, summary_json, inverse_json
               FROM undo_actions
              WHERE token = ?1",
            params![token],
            |row| {
                let summary: String = row.get(2)?;
                let inverse: String = row.get(3)?;
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    serde_json::from_str(&summary).expect("summary json is valid"),
                    serde_json::from_str(&inverse).expect("inverse json is valid"),
                ))
            },
        )
        .expect("read undo action row")
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
            .expect("path is inside repository")
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

#[test]
fn batch_add_tags_implementation_adds_unique_relations_and_records_undo() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    let second_id = insert_file(repo.path(), "finance/invoice.pdf", "finance", "active");
    insert_tag(repo.path(), first_id, "urgent", 100);
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![second_id, first_id, second_id],
        vec![
            " Urgent ".to_owned(),
            "ClientA".to_owned(),
            "urgent".to_owned(),
        ],
    )
    .expect("batch add tags");

    assert_eq!(report.requested_file_count, 2);
    assert_eq!(report.requested_tag_count, 2);
    assert_eq!(report.added_count, 3);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(
        report
            .item_results
            .iter()
            .map(|item| (item.file_id, item.tag.as_str(), item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            (second_id, "urgent", BatchMutationStatus::Added),
            (second_id, "clienta", BatchMutationStatus::Added),
            (first_id, "urgent", BatchMutationStatus::AlreadyHadTag),
            (first_id, "clienta", BatchMutationStatus::Added),
        ]
    );
    assert!(report.item_results.iter().all(|item| item.error.is_none()));
    let token = report.undo_token.expect("new relations create undo token");
    assert!(token.starts_with("undo:batch-tags:"));

    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (first_id, "clienta".to_owned()),
            (first_id, "urgent".to_owned()),
            (second_id, "clienta".to_owned()),
            (second_id, "urgent".to_owned()),
        ]
    );
    let changes = change_rows(repo.path());
    assert_eq!(changes.len(), 3);
    assert!(changes
        .iter()
        .all(|(_, detail)| detail["kind"] == "batch_tag_added"));
    assert_eq!(
        changes
            .iter()
            .map(|(_, detail)| detail["tag"].as_str().expect("tag string"))
            .collect::<Vec<_>>(),
        vec!["urgent", "clienta", "clienta"]
    );

    let (kind, status, summary, inverse) = undo_row(repo.path(), &token);
    assert_eq!(kind, "batch_add_tags");
    assert_eq!(status, "pending");
    assert_eq!(summary["kind"], "batch_add_tags");
    assert_eq!(summary["added_count"], 3);
    assert_eq!(inverse["kind"], "remove_tags");
    let relations = inverse["relations"].as_array().expect("relations array");
    assert_eq!(relations.len(), 3);
    assert!(relations
        .iter()
        .all(|relation| !(relation["file_id"] == first_id && relation["tag"] == "urgent")));
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_add_tags_implementation_all_existing_relations_skip_without_undo() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    insert_tag(repo.path(), file_id, "urgent", 100);
    let before_tags = tag_rows(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["Urgent".to_owned()],
    )
    .expect("idempotent batch tag");

    assert_eq!(report.added_count, 0);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.undo_token, None);
    assert_eq!(
        report.item_results[0].status,
        BatchMutationStatus::AlreadyHadTag
    );
    assert_eq!(tag_rows(repo.path()), before_tags);
    assert!(change_rows(repo.path()).is_empty());
    let undo_count: i64 = open_db(repo.path())
        .query_row("SELECT COUNT(*) FROM undo_actions", [], |row| row.get(0))
        .expect("count undo actions");
    assert_eq!(undo_count, 0);
}

#[test]
fn batch_add_tags_implementation_tracks_missing_target_as_failed_item() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before_tags = tag_rows(repo.path());
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id, 404],
        vec!["urgent".to_owned()],
    )
    .expect("partial missing target returns report");

    assert_eq!(report.requested_file_count, 2);
    assert_eq!(report.requested_tag_count, 1);
    assert_eq!(report.added_count, 1);
    assert_eq!(report.skipped_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report
            .item_results
            .iter()
            .map(|item| (item.file_id, item.tag.as_str(), item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            (file_id, "urgent", BatchMutationStatus::Added),
            (404, "urgent", BatchMutationStatus::Failed),
        ]
    );
    assert!(report.item_results[0].error.is_none());
    assert!(report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has error")
        .contains("FileNotFound"));
    let token = report
        .undo_token
        .expect("successful item creates undo token");

    let mut expected_tags = before_tags;
    expected_tags.push((file_id, "urgent".to_owned()));
    expected_tags.sort();
    assert_eq!(tag_rows(repo.path()), expected_tags);
    assert_eq!(change_rows(repo.path()).len(), 1);

    let (_kind, _status, summary, inverse) = undo_row(repo.path(), &token);
    assert_eq!(summary["added_count"], 1);
    let relations = inverse["relations"].as_array().expect("relations array");
    assert_eq!(relations.len(), 1);
    assert_eq!(relations[0]["file_id"], file_id);
    assert_eq!(relations[0]["tag"], "urgent");
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_add_tags_implementation_rolls_back_failed_item_writes() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs", "active");
    let second_id = insert_file(repo.path(), "docs/plan.pdf", "docs", "active");
    let connection = open_db(repo.path());
    let trigger_sql = format!(
        "CREATE TRIGGER fail_change_log_for_second
         BEFORE INSERT ON change_log
         WHEN NEW.file_id = {second_id}
         BEGIN
           SELECT RAISE(FAIL, 'forced change_log failure');
         END"
    );
    connection
        .execute_batch(&trigger_sql)
        .expect("install failure trigger");
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id],
        vec!["urgent".to_owned()],
    )
    .expect("partial db failure returns report");

    assert_eq!(report.added_count, 1);
    assert_eq!(report.skipped_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(report.item_results[0].status, BatchMutationStatus::Added);
    assert_eq!(report.item_results[1].status, BatchMutationStatus::Failed);
    assert!(report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has db error")
        .contains("Db"));
    assert_eq!(tag_rows(repo.path()), vec![(first_id, "urgent".to_owned())]);
    assert_eq!(change_rows(repo.path()).len(), 1);

    let token = report
        .undo_token
        .expect("successful item creates undo token");
    let (_kind, _status, summary, inverse) = undo_row(repo.path(), &token);
    assert_eq!(summary["added_count"], 1);
    let relations = inverse["relations"].as_array().expect("relations array");
    assert_eq!(relations.len(), 1);
    assert_eq!(relations[0]["file_id"], first_id);
    assert_eq!(relations[0]["tag"], "urgent");
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}
