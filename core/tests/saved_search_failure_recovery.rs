use std::fs;

use area_matrix_core::{
    create_saved_search, delete_saved_search, list_saved_searches, update_saved_search, ErrorKind,
    ErrorRecoverability,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

#[path = "support/saved_search_failure.rs"]
mod saved_search_failure_support;

use saved_search_failure_support::{
    assert_config_error, assert_db_error, create_request, initialized_repo, insert_active_file,
    open_db, path_string, snapshot, table_exists, update_request, user_visible_paths,
};

#[test]
fn saved_search_failure_recovery_empty_repo_lists_empty_without_side_effects() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let searches =
        list_saved_searches(path_string(repo.path())).expect("list empty saved searches");

    assert!(searches.is_empty());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_invalid_inputs_are_config_and_non_mutating() {
    let repo = initialized_repo();
    insert_active_file(repo.path());
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create baseline saved search");
    let before = snapshot(repo.path());

    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();
    assert_config_error(create_saved_search(path_string(repo.path()), invalid_query));

    let mut invalid_filter = create_request("Bad filter");
    invalid_filter.query.filter.imported_after = Some(200);
    invalid_filter.query.filter.imported_before = Some(100);
    assert_config_error(create_saved_search(
        path_string(repo.path()),
        invalid_filter,
    ));

    assert_config_error(update_saved_search(
        path_string(repo.path()),
        update_request(0, "Invalid id"),
    ));
    assert_config_error(delete_saved_search(path_string(repo.path()), -1));
    assert_config_error(list_saved_searches(String::new()));

    let mut empty_icon = update_request(saved.id, "Still Finance");
    empty_icon.icon = Some(" ".to_owned());
    assert_config_error(update_saved_search(path_string(repo.path()), empty_icon));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_duplicate_names_are_structured_and_non_mutating() {
    let repo = initialized_repo();
    let first = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create first saved search");
    let second = create_saved_search(path_string(repo.path()), create_request("Receipts"))
        .expect("create second saved search");
    let before = snapshot(repo.path());

    assert_config_error(create_saved_search(
        path_string(repo.path()),
        create_request("finance pdfs"),
    ));
    assert_db_error(update_saved_search(
        path_string(repo.path()),
        update_request(second.id, &first.name),
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_post_insert_read_failure_rolls_back_partial_row() {
    let repo = initialized_repo();
    insert_active_file(repo.path());
    let before = snapshot(repo.path());
    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER poison_saved_search_after_insert
             AFTER INSERT ON saved_searches
             BEGIN
               UPDATE saved_searches SET query_json = '{' WHERE id = NEW.id;
             END;",
        )
        .expect("install insert poison trigger");

    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Blocked"),
    ));
    assert_eq!(snapshot(repo.path()), before);

    open_db(repo.path())
        .execute_batch("DROP TRIGGER poison_saved_search_after_insert;")
        .expect("drop insert poison trigger");
    let saved = create_saved_search(path_string(repo.path()), create_request("Recovered"))
        .expect("retry create after trigger is removed");
    assert_eq!(saved.name, "Recovered");
}

#[test]
fn saved_search_failure_recovery_post_update_read_failure_rolls_back_existing_row() {
    let repo = initialized_repo();
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create baseline saved search");
    let before = snapshot(repo.path());
    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER poison_saved_search_after_update
             AFTER UPDATE ON saved_searches
             WHEN NEW.name = 'Blocked Update'
             BEGIN
               UPDATE saved_searches SET query_json = '{' WHERE id = NEW.id;
             END;",
        )
        .expect("install update poison trigger");

    assert_db_error(update_saved_search(
        path_string(repo.path()),
        update_request(saved.id, "Blocked Update"),
    ));
    assert_eq!(snapshot(repo.path()), before);

    open_db(repo.path())
        .execute_batch("DROP TRIGGER poison_saved_search_after_update;")
        .expect("drop update poison trigger");
    let updated = update_saved_search(
        path_string(repo.path()),
        update_request(saved.id, "Recovered Update"),
    )
    .expect("retry update after trigger is removed");
    assert_eq!(updated.name, "Recovered Update");
}

#[test]
fn saved_search_failure_recovery_malformed_metadata_is_db_error_not_silent_drop() {
    let repo = initialized_repo();
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
    open_db(repo.path())
        .execute(
            "UPDATE saved_searches SET query_json = '{' WHERE id = ?1",
            params![saved.id],
        )
        .expect("corrupt saved search query json");
    let before = snapshot(repo.path());

    let error = assert_db_error(list_saved_searches(path_string(repo.path())));

    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_uninitialized_repo_is_db_error_without_metadata_creation() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");

    assert_db_error(list_saved_searches(path_string(repo.path())));
    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Finance PDFs"),
    ));

    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user readme"),
        b"user readme"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn saved_search_failure_recovery_missing_table_is_db_error_without_auto_schema_write() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    open_db(repo.path())
        .execute_batch(
            "DROP INDEX IF EXISTS idx_saved_searches_sidebar;
             DROP TABLE saved_searches;",
        )
        .expect("remove saved_searches table fixture");
    let before_paths = user_visible_paths(repo.path());

    assert_db_error(list_saved_searches(path_string(repo.path())));
    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Finance PDFs"),
    ));

    assert!(!table_exists(repo.path(), "saved_searches"));
    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user readme"),
        b"user readme"
    );
}

#[test]
fn saved_search_failure_recovery_corrupted_db_is_fatal_mapping_and_preserves_files() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("finance/invoice.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create user dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    fs::create_dir(repo.path().join(".areamatrix")).expect("create metadata directory");
    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("write corrupted database fixture");

    let error =
        list_saved_searches(path_string(repo.path())).expect_err("corrupted database must fail");

    assert_eq!(error.kind(), ErrorKind::Db);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(
        fs::read(&user_file).expect("read user file after db failure"),
        b"user file bytes"
    );
}

#[cfg(unix)]
#[test]
fn saved_search_failure_recovery_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
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

    let result = create_saved_search(path_string(repo.path()), create_request("Blocked"));

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_failures_do_not_enable_ai_or_remote_state() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());
    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();

    assert_config_error(create_saved_search(path_string(repo.path()), invalid_query));

    let ai_enabled: String = open_db(repo.path())
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'ai_enabled'",
            [],
            |row| row.get(0),
        )
        .expect("read ai_enabled config");
    assert_eq!(ai_enabled, "false");
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(snapshot(repo.path()), before);
}
