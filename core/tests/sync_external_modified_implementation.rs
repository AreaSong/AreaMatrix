use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, list_changes, list_files, sync_external_changes, write_note,
    ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

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

fn event(relative_path: &str, kind: ExternalEventKind, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind,
        fs_event_id,
    }
}

fn file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: Some("external_modified".to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

#[test]
fn sync_external_modified_implementation_updates_hash_size_log_and_cursor() {
    let repo = initialized_repo();
    let relative_path = "docs/external.txt";
    let file_path = repo.path().join(relative_path);
    fs::create_dir_all(file_path.parent().expect("file parent")).expect("create docs directory");
    fs::write(&file_path, b"before").expect("write initial file");
    sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Created, 1)],
        "en".to_owned(),
    )
    .expect("sync initial created event");
    let before = list_files(path_string(repo.path()), file_filter())
        .expect("list initial file")
        .remove(0);

    fs::write(&file_path, b"after content").expect("modify external file");
    let result = sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Modified, 2)],
        "en".to_owned(),
    )
    .expect("sync external modified event");

    assert_eq!(result.detected_modifies, 1);
    assert_eq!(result.detected_creates, 0);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(2)
    );
    let after = list_files(path_string(repo.path()), file_filter())
        .expect("list modified file")
        .remove(0);
    assert_eq!(after.id, before.id);
    assert_eq!(after.size_bytes, 13);
    assert_ne!(after.hash_sha256, before.hash_sha256);

    let changes = list_changes(path_string(repo.path()), change_filter()).expect("list changes");
    let detail: Value = serde_json::from_str(&changes[0].detail_json).expect("parse change detail");
    assert_eq!(detail["kind"], "content");
    assert_eq!(detail["path"], relative_path);
    assert_eq!(detail["hash_before"], before.hash_sha256);
    assert_eq!(detail["hash_after"], after.hash_sha256);
    assert_eq!(detail["size_before"], 6);
    assert_eq!(detail["size_after"], 13);
}

#[test]
fn sync_external_modified_implementation_indexes_untracked_existing_file() {
    let repo = initialized_repo();
    let relative_path = "inbox/untracked.txt";
    let file_path = repo.path().join(relative_path);
    fs::create_dir_all(file_path.parent().expect("file parent")).expect("create inbox directory");
    fs::write(&file_path, b"untracked").expect("write untracked file");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Modified, 9)],
        "en".to_owned(),
    )
    .expect("sync modified-only event");

    assert_eq!(result.detected_creates, 1);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(9)
    );
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list indexed file")[0].path,
        relative_path
    );
}

#[test]
fn sync_external_modified_implementation_skips_managed_note_sidecar_and_advances_cursor() {
    let repo = initialized_repo();
    let relative_path = "docs/report.pdf";
    let file_path = repo.path().join(relative_path);
    fs::create_dir_all(file_path.parent().expect("file parent")).expect("create docs directory");
    fs::write(&file_path, b"report").expect("write report file");
    sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Created, 1)],
        "en".to_owned(),
    )
    .expect("sync report file");
    let file_id =
        list_files(path_string(repo.path()), file_filter()).expect("list report file")[0].id;
    write_note(path_string(repo.path()), file_id, "managed note".to_owned())
        .expect("write managed note sidecar");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![event("docs/report.pdf.md", ExternalEventKind::Modified, 2)],
        "en".to_owned(),
    )
    .expect("replay managed sidecar event");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(2)
    );
    assert_eq!(
        list_files(path_string(repo.path()), file_filter())
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        list_changes(path_string(repo.path()), change_filter())
            .expect("list external changes")
            .len(),
        1
    );
    assert_eq!(
        fs::read_to_string(repo.path().join("docs/report.pdf.md"))
            .expect("managed sidecar remains readable"),
        "managed note"
    );
}

#[test]
fn sync_external_modified_implementation_indexes_markdown_without_managed_note_contract() {
    let repo = initialized_repo();
    let base_path = repo.path().join("docs/report.pdf");
    fs::create_dir_all(base_path.parent().expect("file parent")).expect("create docs directory");
    fs::write(&base_path, b"report").expect("write report file");
    sync_external_changes(
        path_string(repo.path()),
        vec![event("docs/report.pdf", ExternalEventKind::Created, 1)],
        "en".to_owned(),
    )
    .expect("sync report file");
    fs::write(
        repo.path().join("docs/report.pdf.md"),
        b"independent markdown",
    )
    .expect("write independent markdown file");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![event("docs/report.pdf.md", ExternalEventKind::Modified, 2)],
        "en".to_owned(),
    )
    .expect("sync independent markdown file");

    assert_eq!(result.detected_creates, 1);
    let files = list_files(path_string(repo.path()), file_filter()).expect("list indexed files");
    assert_eq!(files.len(), 2);
    assert!(files.iter().any(|file| file.path == "docs/report.pdf.md"));
}

#[test]
fn sync_external_modified_implementation_db_failure_rolls_back_metadata_and_cursor() {
    let repo = initialized_repo();
    let relative_path = "docs/external.txt";
    let file_path = repo.path().join(relative_path);
    fs::create_dir_all(file_path.parent().expect("file parent")).expect("create docs directory");
    fs::write(&file_path, b"before").expect("write initial file");
    sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Created, 1)],
        "en".to_owned(),
    )
    .expect("sync initial created event");
    let before = list_files(path_string(repo.path()), file_filter())
        .expect("list initial file")
        .remove(0);

    fs::write(&file_path, b"after content").expect("modify external file");
    open_db(repo.path())
        .execute("DROP TABLE change_log", [])
        .expect("remove change log to force transactional failure");
    let result = sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Modified, 2)],
        "en".to_owned(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(1)
    );
    let after = list_files(path_string(repo.path()), file_filter())
        .expect("list rolled back file")
        .remove(0);
    assert_eq!(after.hash_sha256, before.hash_sha256);
    assert_eq!(after.size_bytes, before.size_bytes);
    assert_eq!(
        fs::read(&file_path).expect("modified user file remains readable"),
        b"after content"
    );
}

#[test]
fn sync_external_modified_implementation_overview_failure_defers_cursor_and_replay_repairs_output()
{
    let repo = initialized_repo();
    let relative_path = "docs/external.txt";
    let file_path = repo.path().join(relative_path);
    fs::create_dir_all(file_path.parent().expect("file parent")).expect("create docs directory");
    fs::write(&file_path, b"before").expect("write initial file");
    sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Created, 1)],
        "en".to_owned(),
    )
    .expect("sync initial created event");

    fs::write(&file_path, b"after content").expect("modify external file");
    let generated_nodes = repo.path().join(".areamatrix/generated/nodes");
    fs::remove_dir_all(&generated_nodes).expect("remove generated nodes directory");
    fs::write(&generated_nodes, b"block generated node directory")
        .expect("install generated output blocker");

    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Modified, 2)],
        "en".to_owned(),
    );

    assert!(matches!(failed, Err(CoreError::Io { .. })));
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(1)
    );
    let updated = list_files(path_string(repo.path()), file_filter())
        .expect("list metadata committed before overview failure")
        .remove(0);
    assert_eq!(updated.size_bytes, 13);

    fs::remove_file(&generated_nodes).expect("remove generated output blocker");
    fs::create_dir_all(&generated_nodes).expect("restore generated nodes directory");
    fs::remove_file(&file_path).expect("simulate a later external removal before replay");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Modified, 2)],
        "en".to_owned(),
    )
    .expect("replay modified event after generated output recovers");

    assert_eq!(replayed.detected_modifies, 0);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(2)
    );
    assert!(generated_nodes.join("docs.md").is_file());
    assert!(!file_path.exists());

    let removed = sync_external_changes(
        path_string(repo.path()),
        vec![event(relative_path, ExternalEventKind::Removed, 3)],
        "en".to_owned(),
    )
    .expect("process the later removal after replay advances the cursor");
    assert_eq!(removed.detected_deletes, 1);
    assert!(list_files(path_string(repo.path()), file_filter())
        .expect("list active files after removal")
        .is_empty());
}

#[test]
fn sync_external_modified_implementation_mixed_batch_db_failure_is_atomic() {
    let repo = initialized_repo();
    let modified_path = repo.path().join("docs/modified.txt");
    let removed_path = repo.path().join("docs/removed.txt");
    let created_path = repo.path().join("docs/created.txt");
    fs::create_dir_all(modified_path.parent().expect("file parent"))
        .expect("create docs directory");
    fs::write(&modified_path, b"before").expect("write modified fixture");
    fs::write(&removed_path, b"removed").expect("write removed fixture");
    sync_external_changes(
        path_string(repo.path()),
        vec![
            event("docs/modified.txt", ExternalEventKind::Created, 1),
            event("docs/removed.txt", ExternalEventKind::Created, 2),
        ],
        "en".to_owned(),
    )
    .expect("sync initial files");
    let before = list_files(path_string(repo.path()), file_filter()).expect("list initial files");

    fs::write(&modified_path, b"after").expect("modify external file");
    fs::remove_file(&removed_path).expect("remove external file");
    fs::write(&created_path, b"created").expect("write new external file");
    open_db(repo.path())
        .execute("DROP TABLE change_log", [])
        .expect("remove change log to force transactional failure");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            event("docs/created.txt", ExternalEventKind::Created, 10),
            event("docs/modified.txt", ExternalEventKind::Modified, 11),
            event("docs/removed.txt", ExternalEventKind::Removed, 12),
        ],
        "en".to_owned(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).unwrap(),
        Some(2)
    );
    let after =
        list_files(path_string(repo.path()), file_filter()).expect("list rolled back batch");
    assert_eq!(after.len(), 2);
    for before_file in before {
        let after_file = after
            .iter()
            .find(|file| file.id == before_file.id)
            .expect("original DB row remains active");
        assert_eq!(after_file.path, before_file.path);
        assert_eq!(after_file.hash_sha256, before_file.hash_sha256);
        assert_eq!(after_file.size_bytes, before_file.size_bytes);
    }
    assert!(after.iter().all(|file| file.path != "docs/created.txt"));
    assert_eq!(
        fs::read(&modified_path).expect("modified user file remains readable"),
        b"after"
    );
    assert!(!removed_path.exists());
    assert_eq!(
        fs::read(&created_path).expect("created user file remains readable"),
        b"created"
    );
}
