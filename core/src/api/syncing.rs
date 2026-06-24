//! Public FFI syncing entry points.

use crate::{
    platform_watcher_status, sync, CoreResult, ExternalEvent, PlatformWatcherHealthSignal,
    PlatformWatcherSnapshot, SyncResult,
};

/// Synchronizes external filesystem changes after app-layer filtering.
///
/// external created sync owns the `ExternalEventKind::Created` contract.
/// The platform layer is responsible for FSEvents startup, debounce,
/// in-flight filtering, and iCloud placeholder download coordination.
/// Created sync reads only metadata/hash, inserts an active `FileEntry` with
/// `storage_mode = StorageMode::Indexed`, `origin = FileOrigin::External`, and
/// writes a queryable change-log entry with `change_log.action =
/// external_modified` and `kind = create`. It increments
/// `SyncResult::detected_creates` and must skip `.areamatrix/` plus generated overview output.
/// It must not move, delete, rename, overwrite, copy, or download the
/// external user file.
///
/// external renamed sync owns the `ExternalEventKind::Renamed` contract. A rename event's
/// `path` is the repository-relative or absolute new path after app-layer
/// FSEvents pairing/debounce. The contract result is a `files.path` and
/// `files.current_name` update, `updated_at` refresh, `change_log.action =
/// renamed` with old/new path detail, and `SyncResult::detected_renames`
/// increment. The sync branch only confirms the new path exists and must not
/// rename, move, delete, overwrite, copy, or download a user file. If a rename
/// cannot be paired, callers may replay it as removed + created; the rename
/// branch must then avoid claiming a detected rename.
///
/// external removed sync owns the `ExternalEventKind::Removed` contract. A removed event's
/// `path` is the repository-relative or absolute path after app-layer debounce and rename pairing.
/// The sync branch only confirms the path is absent,
/// marks the matching active row as `status = deleted`, refreshes `deleted_at`
/// and `updated_at`, writes `change_log.action = deleted` with external deletion detail,
/// and increments `SyncResult::detected_deletes`. It must not
/// remove, trash, move, rename, overwrite, copy, or download a user file.
/// Deleted rows are not visible to default `list_files` and return `CoreError::FileNotFound { path }`
/// through `get_file`.
///
/// Cursor persistence is part of the batch success contract.
///
/// # Errors
/// Returns `CoreError::InvalidPath { path }`, `CoreError::ICloudPlaceholder { path }`,
/// `CoreError::PermissionDenied { path }`, `CoreError::Io { message }`, or `CoreError::Db { message }` for
/// path, placeholder, metadata/hash, or transactional persistence failures.
/// Returns `CoreError::FileNotFound { path }` when a renamed target no longer exists and
/// when a deleted row is later opened through detail APIs. Returns
/// `CoreError::Conflict { path }` when a renamed target cannot be paired without
/// colliding with another active row.
pub fn sync_external_changes(
    repo_path: String,
    events: Vec<ExternalEvent>,
) -> CoreResult<SyncResult> {
    sync::sync_external_changes(repo_path, events)
}

/// Returns the latest processed filesystem event cursor, or `None` before the first durable batch.
/// # Errors
/// Returns `CoreError::RepoNotInitialized { path }` or `CoreError::Db { message }`.
pub fn get_fs_event_cursor(repo_path: String) -> CoreResult<Option<i64>> {
    sync::get_fs_event_cursor(repo_path)
}

/// Persists the latest processed filesystem event cursor in `.areamatrix/index.db`.
/// Prefer [`sync_external_changes`] for batch-success cursor advancement.
/// This must not inspect, create, move, delete, rename, overwrite, copy, or download user files.
/// # Errors
/// Returns `CoreError::RepoNotInitialized { path }`, `CoreError::InvalidPath { path }`, or `CoreError::Db { message }`.
pub fn set_fs_event_cursor(repo_path: String, last_event_id: i64) -> CoreResult<()> {
    sync::set_fs_event_cursor(repo_path, last_event_id)
}

/// Records platform watcher health for Windows and Linux watcher-status pages.
///
/// platform watcher status accepts a sanitized watcher health signal from the platform layer and
/// returns a normalized [`PlatformWatcherSnapshot`] for `Windows watcher-status surface` and
/// `Linux watcher-status surface`. The snapshot carries watcher lifecycle status, backend,
/// watched path, latest event/sync timestamps, pending count, optional watch
/// count, structured health reasons, and a display-safe error summary.
///
/// The platform layer owns ReadDirectoryChangesW/inotify startup, restart,
/// debouncing, path reveal, diagnostics export, and event capture. Core must
/// not start platform watchers, open Explorer/file managers, trigger manual
/// rescan, inspect user file contents, or move/delete/rename/overwrite user
/// files from this contract. Manual rescan remains manual rescan and must route through
/// the `rescan confirmation surface` confirmation flow before any indexing write.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when the health signal is invalid or
/// watcher health metadata is unavailable, and `CoreError::Io { message }` for
/// later AreaMatrix-owned metadata I/O failures.
pub fn record_watcher_health(
    repo_path: String,
    signal: PlatformWatcherHealthSignal,
) -> CoreResult<PlatformWatcherSnapshot> {
    platform_watcher_status::record_watcher_health(repo_path, signal)
}
