//! Public FFI queries entry points.

use std::path::PathBuf;

use crate::{
    db, missing_file_recovery, note, tree, ChangeFilter, ChangeLogEntry, CoreResult, FileEntry,
    FileFilter, MissingFileRecoveryReport, MissingFileRelinkRequest,
    MissingFileRemoveRecordRequest, MissingFileState,
};

/// Lists file entries from repository metadata.
///
/// The file-list API is the read-only metadata query used by the main window
/// and multi-selection summary. The public contract accepts a
/// [`FileFilter`] for exact category filtering, optional deleted-row inclusion,
/// import-time bounds, `limit` clamping, and offset pagination. Returned rows
/// are ordered by `imported_at DESC`.
///
/// This API must not write repository metadata or mutate user files. Search,
/// tag filtering, smart lists, and single-file detail aggregation belong to
/// later capabilities and must not be hidden behind this entry point.
///
/// mobile library query reuses this query for `mobile library surface` mobile-library rows. Mobile callers
/// must use the documented `limit` and `offset` fields instead of loading the
/// entire repository. The returned [`FileEntry::availability_status`] gives UI
/// consumers a structured availability status for `Missing` badges, while
/// missing-file recovery stays with missing-file recovery rather than this list contract.
///
/// desktop main query reuses the same paginated metadata query for `Windows main-window surface` and
/// `Linux main-window surface` desktop main-window rows. Desktop shells must not scan the
/// repository directly to assemble the main list; `FileFilter::limit` and
/// `FileFilter::offset` carry the page request, and adjacent watcher, import,
/// conflict, and recovery actions remain outside this contract.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when the repository metadata is
/// missing and `CoreError::Db { message }` when SQLite rows cannot be read.
pub fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    db::list_files(repo_path, filter)
}

/// Gets a single active file entry from repository metadata.
///
/// The file-detail API is the read-only detail query used by detail panes.
/// The caller supplies a repository path and stable `file_id`; the
/// contract returns exactly one active [`FileEntry`] and must not infer
/// metadata from the filesystem path in the UI layer.
///
/// This API has no write side effects. Implementations may inspect target
/// metadata to detect stale rows, but they must not create, delete, move,
/// rename, or overwrite user files. File preview, Quick Look, OCR metadata,
/// change-log aggregation, and note aggregation belong to adjacent capabilities
/// and must not be hidden behind this entry point.
///
/// mobile library query allows a mobile list row to open a Core-backed detail record from
/// `mobile library surface`; mobile file detail composes this API with [`list_changes`] and
/// [`read_note`] for `mobile file detail surface` mobile-file-detail. This contract stays
/// limited to base [`FileEntry`] metadata and intentionally does not introduce
/// a separate detail DTO. The returned [`FileEntry::availability_status`]
/// mirrors the list payload so detail consumers can keep a missing row visible
/// without platform-side filesystem inference and route the missing state to
/// `missing-file recovery surface` rather than inferring it from the filesystem.
///
/// desktop main-window consumers use this detail query after selecting a
/// row from [`list_files`] or [`search_files`]. It returns the same base
/// metadata shape and does not add platform-side preview, watcher, rescan, or
/// recovery behavior.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing,
/// `CoreError::FileNotFound { path }` when the requested active file row is absent or
/// not visible to detail consumers, and `CoreError::Db { message }` when SQLite rows cannot
/// be read.
pub fn get_file(repo_path: String, file_id: i64) -> CoreResult<FileEntry> {
    let repo = PathBuf::from(repo_path);
    let entry = db::get_active_file_by_id(&repo, file_id)?;
    Ok(db::with_availability_status(&repo, entry))
}

/// Returns the missing-file recovery state for missing-file recovery surface.
///
/// The state gives page consumers the last known path, missing reason, relink
/// hash expectation, remove-record confirmation requirement, and rescan route
/// availability. It does not scan the whole repository, trigger manual rescan,
/// open a platform picker, delete metadata, or mutate user files.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the file id is invalid or
/// no active missing-file row exists, `CoreError::PermissionDenied { path }`
/// when recovery metadata cannot be inspected, and `CoreError::Db { message }`
/// when metadata cannot be read.
pub fn get_missing_file_state(repo_path: String, file_id: i64) -> CoreResult<MissingFileState> {
    missing_file_recovery::get_missing_file_state(repo_path, file_id)
}

/// Relinks one missing-file record to a user-selected matching path.
///
/// The platform layer owns the picker and access recovery. Core receives only
/// an authorized path and later implementation must verify the selected file
/// hash before updating metadata. A hash mismatch must leave the missing
/// record unchanged and return a report the UI can render; this entry point
/// must never overwrite, move, delete, trash, or download user files.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the file id or selected path
/// is invalid, `CoreError::PermissionDenied { path }` when confirmation or
/// access is missing, and `CoreError::Db { message }` when metadata or
/// change-log persistence fails.
pub fn relink_missing_file(
    repo_path: String,
    request: MissingFileRelinkRequest,
) -> CoreResult<MissingFileRecoveryReport> {
    missing_file_recovery::relink_missing_file(repo_path, request)
}

/// Removes only the AreaMatrix metadata record for a missing file.
///
/// missing-file recovery surface must gather explicit confirmation before calling this API. A
/// successful later implementation removes only the AreaMatrix record, writes a
/// change-log entry, and reports `file_deleted = false`; it must not remove,
/// trash, move, rename, overwrite, or download any user file.
///
/// # Errors
///
/// Returns `CoreError::PermissionDenied { path }` when confirmation is missing,
/// `CoreError::FileNotFound { path }` when the file id is invalid or no longer
/// removable, and `CoreError::Db { message }` when metadata or change-log
/// persistence fails.
pub fn remove_missing_file_record(
    repo_path: String,
    request: MissingFileRemoveRecordRequest,
) -> CoreResult<MissingFileRecoveryReport> {
    missing_file_recovery::remove_missing_file_record(repo_path, request)
}

/// Lists change-log entries from repository metadata.
///
/// The change-log API is the read-only log query used by detail, import
/// result, and error recovery surfaces. The public contract accepts
/// a [`ChangeFilter`] for optional `file_id`, `category`, `action`,
/// `occurred_at` bounds, `limit`, and `offset`. Returned rows are ordered by
/// `occurred_at DESC`, and each [`ChangeLogEntry::detail_json`] value must
/// remain parseable JSON for action-specific UI rendering.
///
/// This API has no write side effects: it must not mutate repository metadata,
/// create files, rename files, or probe user file contents. Undo history,
/// rollback, and batch revert behavior belong to undo/redo capabilities and must not be
/// hidden behind this query entry point.
///
/// mobile library and mobile file detail consumers can lazily request a small `limit`/`offset`
/// page for visible detail timelines. In mobile file detail, `mobile file detail surface` uses `file_id` to
/// load the Log segment without blocking the Meta segment. The API remains a
/// read-only metadata query and does not trigger filesystem rescan, sync
/// repair, conflict resolution, or missing-file recovery.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing
/// and `CoreError::Db { message }` when SQLite rows or persisted change-log details cannot
/// be read as the documented contract.
pub fn list_changes(repo_path: String, filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>> {
    db::list_changes(repo_path, filter)
}

/// Returns repository tree data as JSON.
///
/// The tree JSON API is the read-only tree query for main-window navigation.
/// The caller supplies an initialized repository path and a display locale such
/// as `zh-Hans` or `en`. The output is a single JSON string so Swift can decode
/// one `TreeNode` snapshot without repeated FFI crossings. Tree nodes must use
/// stable path keys, stable sibling ordering, and a Swift-compatible `children`
/// array shape. The query may read repository file paths and classifier config
/// to build display names, but it must not create generated overviews, mutate
/// repository metadata, or modify user files.
///
/// Virtual smart lists, search result trees, and Smart List tree projections remain
/// outside this API boundary.
///
/// mobile library uses this tree snapshot for compact category browsing.
/// Mobile shells must keep large-repository list data paginated through
/// [`list_files`]; this tree contract does not add search, sync, or recovery
/// actions.
///
/// desktop main-window consumers may use the same tree snapshot for the
/// Windows and Linux sidebar. The platform UI remains responsible for native
/// rendering and virtualization; Core only returns the read-only tree JSON.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when metadata is missing,
/// `CoreError::Db { message }` when the tree cannot be read from SQLite, and
/// `CoreError::Io { message }` when repository file paths, file metadata, or classifier
/// config cannot be inspected.
pub fn list_tree_json(
    repo_path: String,
    locale: impl crate::ContentLocaleInput,
) -> CoreResult<String> {
    let locale = locale.into_content_locale()?;
    tree::list_tree_json(repo_path, locale.as_str().to_owned())
}

/// Reads the markdown note associated with one active file entry.
///
/// file note contract exposes this read-only query for detail note surface. The
/// caller supplies a repository path and stable `file_id`; the result is
/// `Some(markdown)` when a note exists and `None` when the file has no note.
/// This API must not create note rows, write sidecar files, insert change-log
/// entries, or mutate user files.
///
/// mobile file detail reuses this as the lazy Note segment query for `mobile file detail surface`. Mobile
/// callers can show the empty-note state from `None` and isolate note read
/// failures to the Note segment; note editing remains with the existing
/// `write_note` contract and is not added to the mobile file detail contract-api task.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing,
/// `CoreError::FileNotFound { path }` when the active file row is absent,
/// `CoreError::PermissionDenied { path }` or `CoreError::Io { message }` for blocked sidecar or
/// metadata reads, and `CoreError::Db { message }` when note metadata cannot be queried.
pub fn read_note(repo_path: String, file_id: i64) -> CoreResult<Option<String>> {
    note::read_note(repo_path, file_id)
}

/// Writes markdown note content for one active file entry.
///
/// file note contract writes exactly one note for the target file. A successful call upserts
/// the `notes` row, writes the same-directory sidecar markdown file, and records
/// `change_log.action = edited_note` only after DB state and sidecar content are
/// consistent. The app layer owns `InFlightTracker` marking so watcher events
/// from the sidecar write are not treated as external changes.
///
/// The call must not delete, move, rename, or overwrite the target file or any
/// unconfirmed user-authored file. Failed writes must preserve the previous note
/// content and must not leave a successful change-log entry without matching DB
/// and sidecar state.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing,
/// `CoreError::FileNotFound { path }` when the active file row is absent,
/// `CoreError::PermissionDenied { path }` for blocked writes, `CoreError::Io { message }` for
/// filesystem failures, and `CoreError::Db { message }` for transactional metadata failures.
pub fn write_note(repo_path: String, file_id: i64, content_md: String) -> CoreResult<()> {
    note::write_note(repo_path, file_id, content_md)
}
