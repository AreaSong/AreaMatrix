//! Public FFI syncing entry points.

use crate::{
    platform_watcher_status, sync, ContentLocale, CoreResult, ExternalEvent,
    ExternalSyncLocaleRecoveryPlan, ExternalSyncLocaleRecoveryReport, PlatformWatcherHealthSignal,
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
/// Core owns rename pairing for the `ExternalEventKind::Renamed` contract. A
/// rename event's `path` is only the repository-relative or absolute new path
/// after app-layer filtering and debounce. Core reads a stable target hash and
/// requires exactly one active metadata row with that hash whose recorded old
/// path no longer exists. A target path already represented by any active,
/// staging, or deleted row, a still-existing old path, or zero or multiple hash
/// candidates fails closed with `CoreError::Conflict { path }`.
///
/// A successful rename updates `files.path`, `files.current_name`, category,
/// size/hash, and `updated_at`, writes `change_log.action = renamed` with
/// old/new path detail, increments `SyncResult::detected_renames`, and suppresses
/// the matching removed plan from the same batch. Core only records the
/// external rename; it must not rename, move, delete, overwrite, copy, or
/// download a user file. Callers replay the same event after a recoverable
/// failure instead of synthesizing replacement events.
///
/// external removed sync owns the `ExternalEventKind::Removed` contract. A removed event's
/// `path` is the repository-relative or absolute path after app-layer filtering and debounce.
/// The sync branch only confirms the path is absent,
/// marks the matching active row as `status = deleted`, refreshes `deleted_at`
/// and `updated_at`, writes `change_log.action = deleted` with external deletion detail,
/// and increments `SyncResult::detected_deletes`. It must not
/// remove, trash, move, rename, overwrite, copy, or download a user file.
/// Deleted rows are not visible to default `list_files` and return `CoreError::FileNotFound { path }`
/// through `get_file`.
///
/// The Core commits the metadata/change-log batch first, regenerates affected
/// overviews second, and persists the maximum event cursor last. An overview or
/// cursor failure leaves the cursor unchanged so the platform can replay the
/// batch. Replay must therefore remain idempotent because metadata may already
/// be durable when a later step fails.
///
/// # Errors
/// Returns `CoreError::InvalidPath { path }`, `CoreError::RepoNotInitialized { path }`,
/// `CoreError::ICloudPlaceholder { path }`, `CoreError::PermissionDenied { path }`,
/// `CoreError::Io { message }`, or `CoreError::Db { message }` for repository/path,
/// placeholder, metadata/hash, or transactional persistence failures. Returns
/// `CoreError::FileNotFound { path }` when a renamed target no longer exists and
/// `CoreError::Conflict { path }` when rename pairing is absent or ambiguous, an old path still
/// exists, a target row is occupied, or a stable file snapshot cannot be obtained.
pub fn sync_external_changes(
    repo_path: String,
    events: Vec<ExternalEvent>,
    content_locale: impl crate::ContentLocaleInput,
) -> CoreResult<SyncResult> {
    let content_locale = content_locale.into_content_locale()?;
    sync::sync_external_changes(repo_path, events, content_locale.as_str().to_owned())
}

/// Returns an explicit recovery plan for legacy external-sync receipts that have no locale.
///
/// The plan is read-only and its opaque token binds the repository path, current filesystem
/// cursor, and exact NULL-receipt set. `None` means no legacy receipt needs recovery.
pub fn prepare_external_sync_locale_recovery(
    repo_path: String,
) -> CoreResult<Option<ExternalSyncLocaleRecoveryPlan>> {
    sync::prepare_external_sync_locale_recovery(repo_path)
}

/// Applies a user-selected concrete locale to one unchanged legacy receipt set.
///
/// Core rechecks the token inside an immediate transaction. A stale token or changed receipt set
/// returns `Conflict` and leaves receipts, cursor, overview, and user files untouched.
pub fn resolve_external_sync_locale_recovery(
    repo_path: String,
    recovery_token: String,
    content_locale: ContentLocale,
) -> CoreResult<ExternalSyncLocaleRecoveryReport> {
    sync::resolve_external_sync_locale_recovery(repo_path, recovery_token, content_locale)
}

/// Returns the latest processed filesystem event cursor from `.areamatrix/index.db`.
///
/// `None` means the initialized repository has no durable cursor row yet. It
/// does not mean the repository may be uninitialized.
///
/// # Errors
/// Returns `CoreError::InvalidPath { path }` for an invalid repository path,
/// `CoreError::RepoNotInitialized { path }` when AreaMatrix metadata is absent,
/// `CoreError::ICloudPlaceholder { path }` for a placeholder-shaped path,
/// `CoreError::PermissionDenied { path }` or `CoreError::Io { message }` when
/// read-only path inspection fails, and `CoreError::Db { message }` when the
/// cursor cannot be read from SQLite.
pub fn get_fs_event_cursor(repo_path: String) -> CoreResult<Option<i64>> {
    sync::get_fs_event_cursor(repo_path)
}

/// Persists the latest processed filesystem event cursor in `.areamatrix/index.db`.
/// Prefer [`sync_external_changes`] for batch-success cursor advancement.
/// This must not inspect, create, move, delete, rename, overwrite, copy, or download user files.
/// Values are monotonic; a lower replayed value cannot move the cursor backward.
///
/// # Errors
/// Returns `CoreError::InvalidPath { path }` for a negative event id or invalid
/// repository path, `CoreError::RepoNotInitialized { path }` when AreaMatrix
/// metadata is absent, `CoreError::ICloudPlaceholder { path }` for a
/// placeholder-shaped path, `CoreError::PermissionDenied { path }` or
/// `CoreError::Io { message }` when path inspection fails, and
/// `CoreError::Db { message }` when the cursor cannot be persisted to SQLite.
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
