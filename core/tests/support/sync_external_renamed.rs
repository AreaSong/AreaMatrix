#![allow(dead_code)]

use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, list_changes, list_files, sync_external_changes, ChangeFilter,
    ExternalEvent, ExternalEventKind, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
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

pub(crate) fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent directory");
    }
    fs::write(path, bytes).expect("write repository file");
}

pub(crate) fn event(
    relative_path: &str,
    kind: ExternalEventKind,
    fs_event_id: i64,
) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind,
        fs_event_id,
    }
}

pub(crate) fn created(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Created, fs_event_id)
}

pub(crate) fn renamed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Renamed, fs_event_id)
}

pub(crate) fn removed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Removed, fs_event_id)
}

pub(crate) fn modified(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Modified, fs_event_id)
}

pub(crate) fn default_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

pub(crate) fn default_change_filter() -> ChangeFilter {
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

pub(crate) fn listed_files(repo: &Path) -> Vec<area_matrix_core::FileEntry> {
    list_files(path_string(repo), default_file_filter()).expect("list files")
}

pub(crate) fn listed_changes(repo: &Path) -> Vec<area_matrix_core::ChangeLogEntry> {
    list_changes(path_string(repo), default_change_filter()).expect("list changes")
}

pub(crate) fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON object")
}

pub(crate) fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn sync_created_file(
    repo: &Path,
    relative_path: &str,
    bytes: &[u8],
) -> area_matrix_core::FileEntry {
    write_repo_file(repo, relative_path, bytes);
    let result = sync_external_changes(
        path_string(repo),
        vec![created(relative_path, 1)],
        "en".to_owned(),
    )
    .expect("sync external created file");
    assert_eq!(result.detected_creates, 1);
    listed_files(repo)
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created file row should be listed")
}

pub(crate) fn count_changes_with_action(repo: &Path, action: &str) -> usize {
    listed_changes(repo)
        .into_iter()
        .filter(|change| change.action == action)
        .count()
}

pub(crate) fn install_renamed_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_renamed_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'renamed'
             BEGIN
                 SELECT RAISE(FAIL, 'forced renamed change log failure');
             END;",
        )
        .expect("install renamed change log failure trigger");
}

pub(crate) fn insert_nonactive_path(repo: &Path, relative_path: &str, status: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (?1, 'reserved.pdf', 'reserved.pdf', 'docs', 0,
                'reserved-hash', 'indexed', 'imported', NULL, 1, 1, ?2)",
            [relative_path, status],
        )
        .expect("insert non-active path fixture");
}
