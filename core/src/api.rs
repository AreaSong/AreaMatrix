//! Public functions exposed through the UniFFI boundary.

use std::path::PathBuf;

use crate::{
    classify, db, note, repo_init, repo_path, repo_scan, storage, tree, ChangeFilter,
    ChangeLogEntry, ClassifyResult, CoreError, CoreResult, ExternalEvent, FileEntry, FileFilter,
    ImportOptions, RecoveryReport, ReindexReport, RepoConfig, RepoInitOptions, RepoPathValidation,
    ScanSession, SyncResult,
};

fn not_implemented<T>() -> CoreResult<T> {
    Err(CoreError::Internal)
}

/// Returns the AreaMatrix core crate version.
pub fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// Validates the requested logging level.
///
/// Full subscriber wiring is left for a later observability task so this
/// skeleton remains side-effect light.
pub fn init_logging(level: String) -> CoreResult<()> {
    match level.as_str() {
        "trace" | "debug" | "info" | "warn" | "error" => Ok(()),
        _ => Err(CoreError::Config),
    }
}

/// Validates a candidate repository path without mutating the filesystem.
///
/// The C1-01 contract accepts a user-selected repository directory path and
/// returns structured status flags, a recommended initialization mode, and
/// display-ready issues for the Swift UI. This API is read-only: it must not
/// create `.areamatrix/`, initialize a database, move user files, or trigger
/// iCloud placeholder downloads.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for empty or metadata-internal paths,
/// `CoreError::PermissionDenied` when metadata or directory checks are blocked,
/// or `CoreError::ICloudPlaceholder` for unavailable iCloud-managed paths.
pub fn validate_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    repo_path::validate_repo_path(repo_path)
}

/// Validates that a repository path already has AreaMatrix metadata.
///
/// This read-only variant is for main-window recovery and reopen flows that
/// require an initialized repository. New-repository onboarding should keep
/// using [`validate_repo_path`] so non-empty folders can still be offered as
/// `AdoptExisting` candidates.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when the path is a readable
/// directory but lacks `.areamatrix/` metadata. Other path, permission, iCloud,
/// and metadata-read failures follow [`validate_repo_path`].
pub fn validate_initialized_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    repo_path::validate_initialized_repo_path(repo_path)
}

/// Initializes AreaMatrix metadata for a repository root.
///
/// The C1-02 contract uses `RepoInitOptions { mode: CreateEmpty, .. }` for an
/// empty user-selected directory. A successful call creates only AreaMatrix
/// metadata: `.areamatrix/index.db`, `.areamatrix/staging/`,
/// `.areamatrix/archives/`, `.areamatrix/generated/`, default classifier and
/// ignore config files, and the generated root overview under
/// `.areamatrix/generated/root.md`.
///
/// The C1-03 contract uses `RepoInitOptions { mode: AdoptExisting, .. }` for a
/// non-empty user-selected directory. That mode has the same metadata-write
/// boundary plus an adoption scan session: existing user files remain in place,
/// are indexed with `FileOrigin::Adopted`, and can be resumed through
/// [`get_latest_scan_session`] and [`resume_scan_session`]. Adopt mode must skip
/// `.areamatrix/`, generated overviews, system temporary files, and root
/// `AREAMATRIX.md` while treating `README.md` as normal user content.
///
/// The API returns `Ok(())` after the empty repository can be read through
/// [`load_config`], `list_files`, and [`list_tree_json`]. It must never create,
/// delete, move, rename, or overwrite user-authored files such as `README.md`.
/// When a previous attempt left a recoverable `.areamatrix.init-*` metadata
/// directory, retrying initialization may remove only that internal temporary
/// state before creating the final `.areamatrix/` directory.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for empty paths or `.areamatrix` internals,
/// `CoreError::PermissionDenied` for unwritable roots, `CoreError::Config` for
/// invalid init options or repeated initialization, `CoreError::Io` for
/// filesystem failures, and `CoreError::Db` for SQLite initialization failures.
pub fn init_repo(repo_path: String, options: RepoInitOptions) -> CoreResult<()> {
    repo_init::init_repo(repo_path, options)
}

/// Loads repository configuration written during initialization.
///
/// C1-02 requires this API to read the `repo_config` state created by
/// [`init_repo`] for an empty repository.
///
/// # Errors
///
/// Returns `CoreError::Io`, `CoreError::Config`, or `CoreError::Db` when the
/// initialized metadata cannot be read or decoded.
pub fn load_config(repo_path: String) -> CoreResult<RepoConfig> {
    db::load_config_or_default(repo_path)
}

/// Updates repository configuration through the `repo_config` table.
///
/// C1-04 uses this API for settings panes that mutate repository defaults:
/// storage mode, overview output policy, AI feature flag, locale, and iCloud
/// warning preference. The call is transactional: either all config keys are
/// updated with a fresh `updated_at` value, or the previously persisted config
/// remains readable through [`load_config`].
///
/// The API only persists the settings contract. It does not create
/// `AREAMATRIX.md`, rewrite `classifier.yaml`, touch `README.md`, or perform
/// any adjacent import, overview, or classifier behavior.
///
/// # Errors
///
/// Returns `CoreError::Config` for mismatched or invalid payloads and missing
/// initialized metadata, `CoreError::PermissionDenied` for unwritable metadata,
/// `CoreError::Io` for filesystem inspection failures, and `CoreError::Db` for
/// SQLite persistence failures.
pub fn update_config(repo_path: String, new_config: RepoConfig) -> CoreResult<()> {
    db::update_config(repo_path, new_config)
}

/// Performs startup recovery.
pub fn recover_on_startup(_repo_path: String) -> CoreResult<RecoveryReport> {
    not_implemented()
}

/// Reindexes a repository from the filesystem.
pub fn reindex_from_filesystem(_repo_path: String) -> CoreResult<ReindexReport> {
    not_implemented()
}

/// Returns the latest adopt or reindex scan session if one exists.
///
/// C1-03 consumers use this read-only API to recover the state of an unfinished
/// or recently completed adoption scan. It reports the persisted session kind,
/// lifecycle status, last processed path, counters, timestamps, and recorded
/// errors without touching user files or starting a new scan.
///
/// # Errors
///
/// Returns `CoreError::Db` when scan-session metadata cannot be read,
/// `CoreError::Io` when repository metadata cannot be inspected, and
/// `CoreError::InvalidPath` or `CoreError::PermissionDenied` for invalid or
/// inaccessible repository roots.
pub fn get_latest_scan_session(repo_path: String) -> CoreResult<Option<ScanSession>> {
    repo_scan::get_latest_scan_session(repo_path)
}

/// Resumes a paused, interrupted, or failed adopt/reindex scan session.
///
/// For C1-03, this is the continuation path for `AdoptExisting` sessions. The
/// contract is idempotent: already-indexed files are updated in place, new files
/// are inserted with the original layout preserved, and a completed session
/// returns an empty report instead of mutating user files.
///
/// # Errors
///
/// Returns `CoreError::Db` when the session or indexed rows cannot be persisted,
/// `CoreError::Io` for filesystem inspection failures, `CoreError::InvalidPath`
/// for malformed repository paths, and `CoreError::PermissionDenied` when the
/// repository cannot be inspected or metadata cannot be updated.
pub fn resume_scan_session(repo_path: String, scan_session_id: i64) -> CoreResult<ReindexReport> {
    repo_scan::resume_scan_session(repo_path, scan_session_id)
}

/// Predicts a category for a filename without importing or mutating files.
///
/// C1-05 uses this API for import previews and classifier settings. It reads
/// classifier rules from `.areamatrix/classifier.yaml`, falls back to the
/// bundled default rules when the file is absent, and returns a suggested
/// category/name pair. It must not create repository metadata, touch the
/// database, import files, or move user content.
///
/// # Errors
///
/// Returns `CoreError::Config` when the repository path, filename, YAML syntax,
/// or classifier schema is invalid. Returns `CoreError::Classify` when the
/// classifier rule source cannot be read as a file.
pub fn predict_category(repo_path: String, filename: String) -> CoreResult<ClassifyResult> {
    classify::predict_category(repo_path, filename)
}

/// Imports one source file into repository storage.
///
/// C1-06 defines the copied-file contract for `ImportOptions` values whose
/// `mode` is `StorageMode::Copied`. The source path is read as immutable input,
/// file bytes are copied through `.areamatrix/staging/`, the content hash is
/// used for duplicate detection, and a successful call returns the active
/// `FileEntry` persisted in `files` with a matching `change_log` import event.
/// The original source file must remain unchanged.
///
/// C1-07 defines the moved-file contract for `ImportOptions` values whose
/// `mode` is `StorageMode::Moved`. The source path is validated, staged under
/// AreaMatrix-owned metadata, atomically renamed into the final repository
/// destination, and recorded with `files.storage_mode = Moved`,
/// `files.source_path` set to the original source, and `change_log.action =
/// imported`. A successful moved import removes the original source path and
/// leaves the final file, DB row, and change log consistent. A failed moved
/// import must keep the original source readable or leave only recoverable
/// internal staging state; it must not cross unconfirmed user directory
/// boundaries.
///
/// C1-08 owns index-only semantics. C1-08 defines the indexed-file contract
/// for `ImportOptions` values whose `mode` is `StorageMode::Indexed`. The
/// source path is validated and may be read for metadata and hashing, but Core
/// must not copy, move, rename, or delete the source file, and must not create
/// a final repository-owned file copy. A successful indexed import records
/// `files.storage_mode = Indexed`, preserves `files.source_path`, and writes a
/// `change_log.action = imported` event so list/detail/log consumers can
/// surface the external reference. This entry point keeps copied, moved, and
/// indexed contracts explicit instead of hiding adjacent behavior behind a
/// generic import success path.
///
/// C1-09 owns duplicate detection for this entry point. Core hashes the source
/// bytes before committing a final destination. `Skip` and `Ask` return
/// `CoreError::DuplicateFile { existing_path }` with the first active path that
/// already owns the hash, and must leave the attempted source, final
/// destination, active rows, and change log unchanged. `KeepBoth` allows a
/// second active row with the same hash when the resolved destination path is
/// distinct. `Overwrite` is accepted only after the UI has made the dangerous
/// replace decision; it moves a recoverable copy of the old repo-owned file to
/// the system Trash, soft-deletes the old active row, promotes the new import,
/// and writes deleted/imported change-log entries in the same metadata
/// transition.
///
/// C1-10 owns same-name conflict handling for this entry point. The target
/// name comes from the source filename or `ImportOptions::override_filename`;
/// the output `FileEntry.path` and `FileEntry.current_name` must report the
/// final conflict-free name that was actually written. Same-name imports with
/// different content must not overwrite an existing user file by default:
/// Core resolves a safe numbered name such as `name_1.ext`, while
/// `CoreError::Conflict` is reserved for exhausted or raced resolution.
/// Dangerous replacement remains explicit through `DuplicateStrategy::Overwrite`
/// after S1-24 has confirmed the user decision.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for an empty, metadata-internal, or unsafe
/// source or destination path, `CoreError::FileNotFound` when the source cannot
/// be found, `CoreError::DuplicateFile { existing_path }` for duplicate hashes
/// when the selected strategy requires user choice or skip behavior,
/// `CoreError::ICloudPlaceholder` for unavailable iCloud placeholders,
/// `CoreError::PermissionDenied` for unreadable sources or unwritable metadata,
/// `CoreError::Io` for filesystem failures, and `CoreError::Db` for metadata
/// persistence failures.
/// Failed imports must not leave active file rows or final destination half-products;
/// staging residue is reserved for later recovery cleanup.
pub fn import_file(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<FileEntry> {
    storage::import_file(repo_path, source_path, options)
}

/// Deletes a file entry.
pub fn delete_file(_repo_path: String, _file_id: i64, _hard: bool) -> CoreResult<()> {
    not_implemented()
}

/// Renames a file entry to a conflict-free filename in its current category.
///
/// C1-10 exposes this entry point for manual name-conflict resolution from
/// S1-23. The input name is a filename, not a path, and must use the same
/// validation boundary as `ImportOptions::override_filename`. A successful
/// call returns the updated `FileEntry`, persists matching `files.path` and
/// `files.current_name`, and records the rename in `change_log` without
/// changing category or silently overwriting an existing file. Replace flows
/// remain guarded by S1-24 rather than becoming a default rename branch.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for empty or unsafe names,
/// `CoreError::FileNotFound` when the file row or repo-owned file is missing,
/// `CoreError::Conflict` when a safe final name cannot be resolved,
/// `CoreError::PermissionDenied` for blocked filesystem writes,
/// `CoreError::Io` for filesystem failures, and `CoreError::Db` for metadata
/// persistence failures.
pub fn rename_file(repo_path: String, file_id: i64, new_name: String) -> CoreResult<FileEntry> {
    storage::rename_file(repo_path, file_id, new_name)
}

/// Moves a file entry to a category.
pub fn move_to_category(
    _repo_path: String,
    _file_id: i64,
    _new_category: String,
) -> CoreResult<FileEntry> {
    not_implemented()
}

/// Restores a deleted file entry.
pub fn restore_file(_repo_path: String, _file_id: i64) -> CoreResult<FileEntry> {
    not_implemented()
}

/// Lists file entries from repository metadata.
///
/// C1-11 defines this as the read-only file-list query used by the Stage 1
/// main window and multi-selection summary. The public contract accepts a
/// [`FileFilter`] for exact category filtering, optional deleted-row inclusion,
/// import-time bounds, `limit` clamping, and offset pagination. Returned rows
/// are ordered by `imported_at DESC`.
///
/// This API must not write repository metadata or mutate user files. Search,
/// tag filtering, smart lists, and single-file detail aggregation belong to
/// later capabilities and must not be hidden behind this entry point.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when the repository metadata is
/// missing and `CoreError::Db` when SQLite rows cannot be read.
pub fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    db::list_files(repo_path, filter)
}

/// Gets a single active file entry from repository metadata.
///
/// C1-12 defines this as the read-only detail query used by Stage 1 detail
/// panes. The caller supplies a repository path and stable `file_id`; the
/// contract returns exactly one active [`FileEntry`] and must not infer
/// metadata from the filesystem path in the UI layer.
///
/// This API has no write side effects. Implementations may inspect target
/// metadata to detect stale rows, but they must not create, delete, move,
/// rename, or overwrite user files. File preview, Quick Look, OCR metadata,
/// change-log aggregation, and note aggregation belong to adjacent capabilities
/// and must not be hidden behind this entry point.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when repository metadata is missing,
/// `CoreError::FileNotFound` when the requested active file row is absent or
/// not visible to detail consumers, and `CoreError::Db` when SQLite rows cannot
/// be read.
pub fn get_file(repo_path: String, file_id: i64) -> CoreResult<FileEntry> {
    let repo = PathBuf::from(repo_path);
    db::get_active_file_by_id(&repo, file_id)
}

/// Lists change-log entries from repository metadata.
///
/// C1-13 defines this as the read-only change-log query used by Stage 1 detail
/// log, import result, and error recovery surfaces. The public contract accepts
/// a [`ChangeFilter`] for optional `file_id`, `category`, `action`,
/// `occurred_at` bounds, `limit`, and `offset`. Returned rows are ordered by
/// `occurred_at DESC`, and each [`ChangeLogEntry::detail_json`] value must
/// remain parseable JSON for action-specific UI rendering.
///
/// This API has no write side effects: it must not mutate repository metadata,
/// create files, rename files, or probe user file contents. Undo history,
/// rollback, and batch revert behavior belong to Stage 2 and must not be
/// hidden behind this query entry point.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when repository metadata is missing
/// and `CoreError::Db` when SQLite rows or persisted change-log details cannot
/// be read as the documented contract.
pub fn list_changes(repo_path: String, filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>> {
    db::list_changes(repo_path, filter)
}

/// Returns repository tree data as JSON.
///
/// C1-15 defines this as the read-only tree query for the Stage 1 main window.
/// The caller supplies an initialized repository path and a display locale such
/// as `zh-Hans` or `en`. The output is a single JSON string so Swift can decode
/// one `TreeNode` snapshot without repeated FFI crossings. Tree nodes must use
/// stable path keys, stable sibling ordering, and a Swift-compatible `children`
/// array shape. The query may read repository file paths and classifier config
/// to build display names, but it must not create generated overviews, mutate
/// repository metadata, or modify user files.
///
/// Virtual smart lists, search result trees, and Stage 2 tree projections remain
/// outside this API boundary.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when metadata is missing,
/// `CoreError::Db` when the tree cannot be read from SQLite, and
/// `CoreError::Io` when repository file paths, file metadata, or classifier
/// config cannot be inspected.
pub fn list_tree_json(repo_path: String, locale: String) -> CoreResult<String> {
    tree::list_tree_json(repo_path, locale)
}

/// Reads the markdown note associated with one active file entry.
///
/// C1-14 exposes this read-only query for the S1-14 detail-note surface. The
/// caller supplies a repository path and stable `file_id`; the result is
/// `Some(markdown)` when a note exists and `None` when the file has no note.
/// This API must not create note rows, write sidecar files, insert change-log
/// entries, or mutate user files.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when repository metadata is missing,
/// `CoreError::FileNotFound` when the active file row is absent,
/// `CoreError::PermissionDenied` or `CoreError::Io` for blocked sidecar or
/// metadata reads, and `CoreError::Db` when note metadata cannot be queried.
pub fn read_note(repo_path: String, file_id: i64) -> CoreResult<Option<String>> {
    note::read_note(repo_path, file_id)
}

/// Writes markdown note content for one active file entry.
///
/// C1-14 writes exactly one note for the target file. A successful call upserts
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
/// Returns `CoreError::RepoNotInitialized` when repository metadata is missing,
/// `CoreError::FileNotFound` when the active file row is absent,
/// `CoreError::PermissionDenied` for blocked writes, `CoreError::Io` for
/// filesystem failures, and `CoreError::Db` for transactional metadata failures.
pub fn write_note(repo_path: String, file_id: i64, content_md: String) -> CoreResult<()> {
    note::write_note(repo_path, file_id, content_md)
}

/// Synchronizes external filesystem changes.
pub fn sync_external_changes(
    _repo_path: String,
    _events: Vec<ExternalEvent>,
) -> CoreResult<SyncResult> {
    not_implemented()
}

/// Gets the latest filesystem event cursor.
pub fn get_fs_event_cursor(_repo_path: String) -> CoreResult<Option<i64>> {
    not_implemented()
}

/// Sets the latest filesystem event cursor.
pub fn set_fs_event_cursor(_repo_path: String, _last_event_id: i64) -> CoreResult<()> {
    not_implemented()
}
