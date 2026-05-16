use std::fs;

use area_matrix_core::{
    create_saved_search, run_smart_list, CoreError, ErrorKind, ErrorRecoverability,
    SearchIndexStatus, SearchPagination,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

#[path = "support/smart_list_failure.rs"]
mod smart_list_failure_support;

use smart_list_failure_support::{
    assert_config_error, assert_db_error, assert_snapshot_unchanged, create_request, first_page,
    initialized_repo, insert_change, insert_file, insert_note, insert_tag, open_db, path_string,
    relative_directory_entries, smart_list_query, snapshot,
};

#[test]
fn smart_list_failure_recovery_empty_state_returns_empty_page_without_writes() {
    let repo = initialized_repo();
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Empty Smart List", smart_list_query()),
    )
    .expect("create smart list");
    let before = snapshot(repo.path());

    let page =
        run_smart_list(path_string(repo.path()), saved.id, first_page()).expect("run smart list");

    assert_eq!(page.query, "report");
    assert_eq!(page.total_count, 0);
    assert!(page.results.is_empty());
    assert!(page.diagnostics.is_empty());
    assert_eq!(page.index_status, SearchIndexStatus::Ready);
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_failure_recovery_invalid_inputs_are_config_and_non_mutating() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");
    insert_tag(repo.path(), file_id, "tax");
    insert_note(repo.path(), file_id, "quarterly report");
    insert_change(repo.path(), file_id);
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", smart_list_query()),
    )
    .expect("create smart list");
    let before = snapshot(repo.path());

    assert_config_error(run_smart_list(String::new(), saved.id, first_page()));
    assert_config_error(run_smart_list(path_string(repo.path()), 0, first_page()));
    assert_config_error(run_smart_list(path_string(repo.path()), -1, first_page()));
    assert_config_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        SearchPagination {
            limit: 0,
            offset: 0,
        },
    ));
    assert_config_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        SearchPagination {
            limit: 1001,
            offset: 0,
        },
    ));
    assert_config_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        SearchPagination {
            limit: 50,
            offset: -1,
        },
    ));

    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_failure_recovery_missing_id_maps_to_file_not_found_and_refresh() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");
    insert_change(repo.path(), file_id);
    let before = snapshot(repo.path());

    let error = run_smart_list(path_string(repo.path()), 404, first_page())
        .expect_err("missing smart list should fail");
    let mapping = error.to_error_mapping();

    assert!(matches!(error, CoreError::FileNotFound { .. }));
    assert_eq!(mapping.kind, ErrorKind::FileNotFound);
    assert_eq!(mapping.recoverability, ErrorRecoverability::RefreshRequired);
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_failure_recovery_malformed_saved_query_is_db_not_silent_drop() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Broken Smart List", smart_list_query()),
    )
    .expect("create smart list");
    open_db(repo.path())
        .execute(
            "UPDATE saved_searches SET query_json = '{' WHERE id = ?1",
            params![saved.id],
        )
        .expect("corrupt saved search query json");
    let before = snapshot(repo.path());

    let error = assert_db_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        first_page(),
    ));

    assert!(!error.to_error_mapping().raw_context.is_empty());
    assert!(snapshot(repo.path())
        .files
        .iter()
        .any(|row| row.0 == file_id));
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_failure_recovery_search_metadata_db_error_preserves_files() {
    let repo = initialized_repo();
    let user_file = repo.path().join("finance/report.pdf");
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", smart_list_query()),
    )
    .expect("create smart list");
    open_db(repo.path())
        .execute_batch("DROP TABLE files;")
        .expect("simulate search metadata corruption");

    let error = assert_db_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        first_page(),
    ));

    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    assert_eq!(
        fs::read(user_file).expect("read user file after db failure"),
        b"fixture bytes for finance/report.pdf"
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        Vec::<String>::new()
    );
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(file_id, 1);
}

#[test]
fn smart_list_failure_recovery_corrupted_db_is_fatal_and_preserves_user_files() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("finance/report.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create user dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    let metadata_dir = repo.path().join(".areamatrix");
    fs::create_dir(&metadata_dir).expect("create metadata directory");
    fs::create_dir(metadata_dir.join("staging")).expect("create staging directory");
    fs::create_dir(metadata_dir.join("generated")).expect("create generated directory");
    fs::write(metadata_dir.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database fixture");

    let error = assert_db_error(run_smart_list(path_string(repo.path()), 1, first_page()));

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(
        fs::read(user_file).expect("read user file after corrupted db failure"),
        b"user file bytes"
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        Vec::<String>::new()
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        Vec::<String>::new()
    );
}

#[cfg(unix)]
#[test]
fn smart_list_failure_recovery_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");
    insert_note(repo.path(), file_id, "private report notes");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", smart_list_query()),
    )
    .expect("create smart list");
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

    let result = run_smart_list(path_string(repo.path()), saved.id, first_page());

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_failure_recovery_does_not_create_staging_generated_ai_remote_or_secret_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/local-report.txt", "docs");
    insert_tag(repo.path(), file_id, "local");
    insert_note(repo.path(), file_id, "local report note");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Local Reports", smart_list_query()),
    )
    .expect("create smart list");
    let before = snapshot(repo.path());

    let page =
        run_smart_list(path_string(repo.path()), saved.id, first_page()).expect("run smart list");

    assert_eq!(page.total_count, 1);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_snapshot_unchanged(repo.path(), &before);
}
