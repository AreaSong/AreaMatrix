use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, import_file, init_repo, sync_external_changes, CoreError,
    DuplicateStrategy, ExternalEvent, ExternalEventKind, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

fn import_fixture(repo: &Path, category: &str, name: &str) -> area_matrix_core::FileEntry {
    let source_dir = tempfile::tempdir().expect("create temporary source directory");
    let source = source_dir.path().join(name);
    fs::write(&source, format!("fixture for {category}/{name}"))
        .expect("write imported source fixture");
    import_file(
        path_string(repo),
        path_string(&source),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::AutoClassify,
            target_directory: None,
            override_category: Some(category.to_owned()),
            override_filename: None,
            duplicate_strategy: DuplicateStrategy::Skip,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("import repository fixture")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn event(path: &str, kind: ExternalEventKind, event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: path.to_owned(),
        kind,
        fs_event_id: event_id,
    }
}

fn read_generated(repo: &Path, relative_path: &str) -> String {
    fs::read_to_string(repo.join(".areamatrix/generated").join(relative_path))
        .expect("read generated overview")
}

#[test]
fn mixed_replay_uses_receipt_max_locale_per_node_and_global_max_for_root() {
    let repo = initialized_repo();
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user-authored readme\n").expect("write user README fixture");
    let docs = import_fixture(repo.path(), "docs", "existing.txt");
    open_db(repo.path())
        .execute(
            "INSERT INTO external_sync_receipts (
               event_id, kind, path, file_id, current_category, content_locale, applied_at
             ) VALUES (10, 'modified', ?1, ?2, 'docs', 'zh-Hans', 1)",
            params![docs.path, docs.id],
        )
        .expect("insert replay receipt with Chinese locale");
    let new_path = repo.path().join("code/new.txt");
    fs::create_dir_all(new_path.parent().expect("new file parent"))
        .expect("create external file parent");
    fs::write(&new_path, "new external file").expect("write external file fixture");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            event(&docs.path, ExternalEventKind::Modified, 10),
            event("code/new.txt", ExternalEventKind::Created, 20),
        ],
        "en".to_owned(),
    )
    .expect("apply mixed replay and new external event");

    assert_eq!(result.detected_creates, 1);
    assert!(read_generated(repo.path(), "nodes/docs.md").starts_with("# \u{6587}\u{6863} (docs)"));
    assert!(read_generated(repo.path(), "nodes/code.md").starts_with("# Code (code)"));
    assert!(read_generated(repo.path(), "root.md").starts_with("# AreaMatrix Repository"));
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read committed cursor"),
        Some(20)
    );
    let receipt_count: i64 = open_db(repo.path())
        .query_row("SELECT COUNT(*) FROM external_sync_receipts", [], |row| {
            row.get(0)
        })
        .expect("count cleaned receipts");
    assert_eq!(receipt_count, 0);
    assert_eq!(
        fs::read_to_string(readme).expect("read untouched user README"),
        "user-authored readme\n"
    );
}

#[test]
fn equal_max_event_id_with_different_receipt_locales_fails_closed() {
    let repo = initialized_repo();
    let first = import_fixture(repo.path(), "docs", "first.txt");
    let second = import_fixture(repo.path(), "docs", "second.txt");
    let node_before = read_generated(repo.path(), "nodes/docs.md");
    let connection = open_db(repo.path());
    connection
        .execute(
            "INSERT INTO external_sync_receipts (
               event_id, kind, path, file_id, current_category, content_locale, applied_at
             ) VALUES (50, 'modified', ?1, ?2, 'docs', 'en', 1)",
            params![first.path, first.id],
        )
        .expect("insert English receipt");
    connection
        .execute(
            "INSERT INTO external_sync_receipts (
               event_id, kind, path, file_id, current_category, content_locale, applied_at
             ) VALUES (50, 'modified', ?1, ?2, 'docs', 'zh-Hans', 1)",
            params![second.path, second.id],
        )
        .expect("insert Chinese receipt");

    let error = sync_external_changes(
        path_string(repo.path()),
        vec![
            event(&first.path, ExternalEventKind::Modified, 50),
            event(&second.path, ExternalEventKind::Modified, 50),
        ],
        "en".to_owned(),
    )
    .expect_err("ambiguous max-event locale must fail closed");

    assert!(matches!(error, CoreError::Internal { .. }));
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read unadvanced cursor"),
        None
    );
    assert_eq!(read_generated(repo.path(), "nodes/docs.md"), node_before);
    let receipt_count: i64 = open_db(repo.path())
        .query_row("SELECT COUNT(*) FROM external_sync_receipts", [], |row| {
            row.get(0)
        })
        .expect("count retained receipts");
    assert_eq!(receipt_count, 2);
}
