use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileAvailabilityStatus,
    FileFilter, FileOrigin, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
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

fn files_provider_selection(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let provider_scope = tempfile::tempdir().expect("create files-provider scope directory");
    let source_path = provider_scope.path().join(name);
    fs::write(&source_path, content).expect("write selected files-provider fixture");
    (provider_scope, source_path)
}

fn files_import_options(filename: Option<&str>) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: filename.map(str::to_owned),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn row_count(repo: &Path, table: &str, status: Option<&str>) -> i64 {
    let connection = open_db(repo);
    match status {
        Some(status) => connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE status = ?1"),
                [status],
                |row| row.get(0),
            )
            .expect("count rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count rows"),
    }
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

#[test]
fn files_import_implementation_copies_authorized_provider_file_into_repo() {
    let repo = initialized_repo();
    let bytes = b"files provider document bytes";
    let (_provider_scope, selected) = files_provider_selection("picked-report.pdf", bytes);
    let selected_path = path_string(&selected);

    let entry = import_file(
        path_string(repo.path()),
        selected_path.clone(),
        files_import_options(Some("Quarterly Report.pdf")),
    )
    .expect("import authorized files-provider selection");

    assert_eq!(fs::read(&selected).expect("read selected file"), bytes);
    assert_eq!(entry.path, "inbox/Quarterly Report.pdf");
    assert_eq!(entry.original_name, "picked-report.pdf");
    assert_eq!(entry.current_name, "Quarterly Report.pdf");
    assert_eq!(entry.category, "inbox");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(selected_path.as_str()));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied repo file"),
        bytes
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list mobile files");
    assert_eq!(files, vec![entry.clone()]);

    let (status, storage_mode, source_path_db): (String, String, Option<String>) =
        open_db(repo.path())
            .query_row(
                "SELECT status, storage_mode, source_path FROM files WHERE id = ?1",
                [entry.id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read imported files-provider row");
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "copied");
    assert_eq!(source_path_db.as_deref(), Some(selected_path.as_str()));

    let (action, detail_json): (String, String) = open_db(repo.path())
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [entry.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read files-provider import change log");
    assert_eq!(action, "imported");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse import detail json");
    assert_eq!(detail["source"], selected_path);
    assert_eq!(detail["mode"], "copied");
    assert_eq!(detail["category"], "inbox");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["requested_name"], "Quarterly Report.pdf");
    assert_eq!(detail["final_path"], entry.path);
    assert_eq!(detail["by"], "user");
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn files_import_implementation_cancel_without_core_call_writes_no_state() {
    let repo = initialized_repo();
    let (_provider_scope, selected) =
        files_provider_selection("cancelled.txt", b"cancelled selection bytes");

    assert_eq!(
        fs::read(&selected).expect("read cancelled files-provider selection"),
        b"cancelled selection bytes"
    );
    assert_eq!(row_count(repo.path(), "files", None), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo.path().join("inbox").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn files_import_implementation_icloud_placeholder_returns_structured_error() {
    let repo = initialized_repo();
    let (_provider_scope, placeholder) =
        files_provider_selection("remote-report.pdf.icloud", b"placeholder marker");

    let result = import_file(
        path_string(repo.path()),
        path_string(&placeholder),
        files_import_options(Some("Remote Report.pdf")),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::ICloudPlaceholder { path }) if path == path_string(&placeholder)
        ),
        "iCloud placeholder error should carry the selected provider path"
    );
    assert_eq!(
        fs::read(&placeholder).expect("read provider placeholder marker"),
        b"placeholder marker"
    );
    assert_eq!(row_count(repo.path(), "files", None), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo.path().join("inbox").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[cfg(unix)]
#[test]
fn files_import_implementation_permission_denied_keeps_repo_and_source_unchanged() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_provider_scope, selected) = files_provider_selection("locked.pdf", b"locked bytes");
    let original_permissions = fs::metadata(&selected)
        .expect("read selected file metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&selected, blocked_permissions).expect("block selected file reads");

    let result = import_file(
        path_string(repo.path()),
        path_string(&selected),
        files_import_options(Some("Locked.pdf")),
    );

    fs::set_permissions(&selected, original_permissions).expect("restore selected file reads");

    assert!(
        matches!(
            result,
            Err(CoreError::PermissionDenied { path }) if path == path_string(&selected)
        ),
        "permission error should carry the selected provider path"
    );
    assert_eq!(
        fs::read(&selected).expect("read restored selected file"),
        b"locked bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo.path().join("inbox").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn files_import_implementation_duplicate_skip_preserves_existing_import() {
    let repo = initialized_repo();
    let (_first_scope, first) = files_provider_selection("first.pdf", b"same files bytes");
    let (_second_scope, second) = files_provider_selection("second.pdf", b"same files bytes");

    let first_entry = import_file(
        path_string(repo.path()),
        path_string(&first),
        files_import_options(None),
    )
    .expect("import first files-provider selection");

    let result = import_file(
        path_string(repo.path()),
        path_string(&second),
        files_import_options(None),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first_entry.path
        ),
        "duplicate import should route to the existing path"
    );
    assert_eq!(
        fs::read(&second).expect("read duplicate provider file"),
        b"same files bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 1);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn files_import_implementation_name_conflict_keep_both_uses_numbered_name() {
    let repo = initialized_repo();
    let (_first_scope, first) = files_provider_selection("first.pdf", b"first files bytes");
    let (_second_scope, second) = files_provider_selection("second.pdf", b"second files bytes");

    let mut options = files_import_options(Some("Shared Name.pdf"));
    options.duplicate_strategy = DuplicateStrategy::KeepBoth;
    let first_entry = import_file(
        path_string(repo.path()),
        path_string(&first),
        options.clone(),
    )
    .expect("import first named files-provider selection");
    let second_entry = import_file(path_string(repo.path()), path_string(&second), options)
        .expect("import second named files-provider selection");

    assert_eq!(first_entry.path, "inbox/Shared Name.pdf");
    assert_eq!(second_entry.path, "inbox/Shared Name_1.pdf");
    assert_eq!(second_entry.current_name, "Shared Name_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&first_entry.path)).expect("read first copied file"),
        b"first files bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&second_entry.path)).expect("read second copied file"),
        b"second files bytes"
    );
    assert_eq!(
        fs::read(&second).expect("read second provider source"),
        b"second files bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 2);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
