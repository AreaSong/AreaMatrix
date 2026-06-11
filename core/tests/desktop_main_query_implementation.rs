use std::{fs, path::Path};

use area_matrix_core::{
    get_file, init_repo, list_files, list_tree_json, search_files, FileAvailabilityStatus,
    FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions, SearchFilter, SearchIndexStatus,
    SearchPagination, SearchScope, SearchSort, SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

#[derive(Debug, PartialEq)]
struct MetadataSnapshot {
    files: Vec<(i64, String, String, String, String)>,
    change_count: i64,
    note_count: i64,
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
    .expect("initialize desktop query repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn default_file_filter(limit: i64, offset: i64) -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit,
        offset,
    }
}

fn default_search_filter() -> SearchFilter {
    SearchFilter {
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
    }
}

fn page(limit: i64, offset: i64) -> SearchPagination {
    SearchPagination { limit, offset }
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create user fixture parent directory");
    }
    fs::write(path, content).expect("write user fixture file");
}

fn insert_desktop_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    imported_at: i64,
    write_file: bool,
) -> i64 {
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path has a filename");
    if write_file {
        write_repo_file(
            repo,
            relative_path,
            format!("content-{imported_at}").as_bytes(),
        );
    }

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4,
                ?5, 'copied', 'imported', NULL,
                ?6, ?7, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                100 + imported_at,
                format!("{imported_at:064x}"),
                imported_at,
                imported_at + 1,
            ],
        )
        .expect("insert desktop file row");
    connection.last_insert_rowid()
}

fn insert_note(repo: &Path, file_id: i64, content: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at) VALUES (?1, ?2, 100)",
            params![file_id, content],
        )
        .expect("insert note row");
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

fn metadata_snapshot(repo: &Path) -> MetadataSnapshot {
    let connection = open_db(repo);
    let files = file_rows(&connection);
    let change_count = count_rows(&connection, "change_log");
    let note_count = count_rows(&connection, "notes");
    MetadataSnapshot {
        files,
        change_count,
        note_count,
    }
}

fn file_rows(connection: &Connection) -> Vec<(i64, String, String, String, String)> {
    let mut statement = connection
        .prepare("SELECT id, path, current_name, category, status FROM files ORDER BY id")
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

fn count_rows(connection: &Connection, table: &str) -> i64 {
    connection
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .expect("count metadata rows")
}

fn file_bytes(repo: &Path, relative_path: &str) -> Vec<u8> {
    fs::read(repo.join(relative_path)).expect("read user fixture file")
}

fn child_slugs(node: &Value) -> Vec<&str> {
    node["children"]
        .as_array()
        .expect("TreeNode children should be an array")
        .iter()
        .map(|child| child["slug"].as_str().expect("child slug should be string"))
        .collect()
}

#[test]
fn desktop_main_query_implementation_composes_shared_read_only_snapshot() {
    let repo = initialized_repo();
    insert_desktop_file(repo.path(), "docs/old.pdf", "docs", 10, true);
    let report_id = insert_desktop_file(repo.path(), "docs/report.pdf", "docs", 20, true);
    let invoice_id = insert_desktop_file(repo.path(), "finance/invoice.txt", "finance", 30, true);
    insert_note(repo.path(), report_id, "desktop shared query note");
    insert_change(
        repo.path(),
        invoice_id,
        "renamed",
        r#"{"to":"desktop-window"}"#,
    );
    let before = metadata_snapshot(repo.path());
    let before_report = file_bytes(repo.path(), "docs/report.pdf");
    let before_invoice = file_bytes(repo.path(), "finance/invoice.txt");

    let mut list_filter = default_file_filter(2, 0);
    list_filter.category = Some("docs".to_owned());
    let files = list_files(path_string(repo.path()), list_filter).expect("list desktop rows");

    assert_eq!(
        files
            .iter()
            .map(|file| file.current_name.as_str())
            .collect::<Vec<_>>(),
        vec!["report.pdf", "old.pdf"]
    );

    let detail = get_file(path_string(repo.path()), report_id).expect("get selected detail");
    assert_eq!(detail.id, report_id);
    assert_eq!(
        detail.availability_status,
        FileAvailabilityStatus::Available
    );

    let search = search_files(
        path_string(repo.path()),
        "desktop".to_owned(),
        default_search_filter(),
        SearchSort::Relevance,
        page(10, 0),
    )
    .expect("search desktop rows");
    assert_eq!(search.index_status, SearchIndexStatus::Ready);
    assert_eq!(search.total_count, 2);
    assert_eq!(search.results[0].entry.id, report_id);

    let tree_json =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list desktop tree");
    let tree = serde_json::from_str::<Value>(&tree_json).expect("parse tree JSON");
    assert_eq!(tree["file_count"], 3);
    assert_eq!(child_slugs(&tree), vec!["docs", "finance"]);

    assert_eq!(metadata_snapshot(repo.path()), before);
    assert_eq!(file_bytes(repo.path(), "docs/report.pdf"), before_report);
    assert_eq!(
        file_bytes(repo.path(), "finance/invoice.txt"),
        before_invoice
    );
}

#[test]
fn desktop_main_query_implementation_marks_missing_rows_across_list_detail_and_search() {
    let repo = initialized_repo();
    let missing_id = insert_desktop_file(repo.path(), "docs/missing.pdf", "docs", 50, false);
    insert_desktop_file(repo.path(), "docs/present.pdf", "docs", 40, true);
    let before = metadata_snapshot(repo.path());

    let mut list_filter = default_file_filter(10, 0);
    list_filter.category = Some("docs".to_owned());
    let files = list_files(path_string(repo.path()), list_filter).expect("list missing row");

    assert_eq!(files[0].id, missing_id);
    assert_eq!(
        files[0].availability_status,
        FileAvailabilityStatus::Missing
    );
    assert!(!repo.path().join("docs/missing.pdf").exists());

    let detail = get_file(path_string(repo.path()), missing_id).expect("get missing detail");
    assert_eq!(detail.availability_status, FileAvailabilityStatus::Missing);

    let search = search_files(
        path_string(repo.path()),
        "missing".to_owned(),
        default_search_filter(),
        SearchSort::NewestImported,
        page(10, 0),
    )
    .expect("search missing row");
    assert_eq!(search.total_count, 1);
    assert_eq!(search.results[0].entry.id, missing_id);
    assert_eq!(
        search.results[0].entry.availability_status,
        FileAvailabilityStatus::Missing
    );
    assert_eq!(metadata_snapshot(repo.path()), before);
}

#[test]
fn desktop_main_query_implementation_paginates_large_desktop_lists() {
    let repo = initialized_repo();
    seed_indexed_rows(repo.path(), 1105);
    let before = metadata_snapshot(repo.path());

    let files =
        list_files(path_string(repo.path()), default_file_filter(25, 1000)).expect("list page");
    assert_eq!(files.len(), 25);
    assert_eq!(files[0].current_name, "file-0104.txt");
    assert_eq!(files[24].current_name, "file-0080.txt");

    let search = search_files(
        path_string(repo.path()),
        String::new(),
        default_search_filter(),
        SearchSort::NewestImported,
        page(30, 1075),
    )
    .expect("search large desktop page");
    assert_eq!(search.total_count, 1105);
    assert_eq!(search.results.len(), 30);
    assert_eq!(search.results[0].entry.current_name, "file-0029.txt");
    assert_eq!(search.results[29].entry.current_name, "file-0000.txt");
    assert_eq!(metadata_snapshot(repo.path()), before);
}

fn seed_indexed_rows(repo: &Path, count: i64) {
    let mut connection = open_db(repo);
    let transaction = connection.transaction().expect("start seed transaction");
    {
        let mut statement = transaction
            .prepare(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?2, 'docs', 1,
                    ?3, 'indexed', 'external', ?1,
                    ?4, ?4, 'active'
                 )",
            )
            .expect("prepare seed insert");
        for index in 0..count {
            let current_name = format!("file-{index:04}.txt");
            let path = format!("/external/{current_name}");
            statement
                .execute(params![path, current_name, format!("{index:064x}"), index])
                .expect("insert indexed row");
        }
    }
    transaction.commit().expect("commit seed transaction");
}
