//! Public functions exposed through the UniFFI boundary.

use crate::{
    classify, db, repo_init, repo_path, repo_scan, storage, tree, ChangeFilter, ChangeLogEntry,
    ClassifyResult, CoreError, CoreResult, ExternalEvent, FileEntry, FileFilter, ImportOptions,
    RecoveryReport, ReindexReport, RepoConfig, RepoInitOptions, RepoPathValidation, ScanSession,
    SyncResult,
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
/// This API is the shared entry point for adjacent import modes. C1-07 and
/// C1-08 own move and index semantics, so this task only fixes the public
/// contract for copied imports.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for an empty, metadata-internal, or unsafe
/// source or destination path, `CoreError::DuplicateFile` for duplicate hashes
/// when the selected strategy requires user choice or skip behavior,
/// `CoreError::ICloudPlaceholder` for unavailable iCloud placeholders,
/// `CoreError::PermissionDenied` for unreadable sources or unwritable metadata,
/// `CoreError::Io` for filesystem failures, and `CoreError::Db` for metadata
/// persistence failures. Failed imports must not leave active file rows or
/// final destination half-products; staging residue is reserved for later
/// recovery cleanup.
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

/// Renames a file entry.
pub fn rename_file(_repo_path: String, _file_id: i64, _new_name: String) -> CoreResult<FileEntry> {
    not_implemented()
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
/// C1-02 uses this to prove an initialized empty repository is readable. Later
/// query tasks can extend filtering semantics without changing the empty-repo
/// contract.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when the repository metadata is
/// missing and `CoreError::Db` when SQLite rows cannot be read.
pub fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    db::list_files(repo_path, filter)
}

/// Gets a single file entry.
pub fn get_file(_repo_path: String, _file_id: i64) -> CoreResult<FileEntry> {
    not_implemented()
}

/// Lists change-log entries.
pub fn list_changes(_repo_path: String, _filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>> {
    not_implemented()
}

/// Returns repository tree data as JSON.
///
/// After C1-02 empty initialization this returns the empty repository tree that
/// the first main window can render without scanning user files.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` when metadata is missing,
/// `CoreError::Db` when the tree cannot be read from SQLite, and
/// `CoreError::Io` when repository metadata cannot be inspected.
pub fn list_tree_json(repo_path: String, locale: String) -> CoreResult<String> {
    tree::list_tree_json(repo_path, locale)
}

/// Reads a markdown note for a file.
pub fn read_note(_repo_path: String, _file_id: i64) -> CoreResult<Option<String>> {
    not_implemented()
}

/// Writes a markdown note for a file.
pub fn write_note(_repo_path: String, _file_id: i64, _content_md: String) -> CoreResult<()> {
    not_implemented()
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
