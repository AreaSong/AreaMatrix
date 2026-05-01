//! Public functions exposed through the UniFFI boundary.

use crate::{
    repo_path, ChangeFilter, ChangeLogEntry, ClassifyResult, CoreError, CoreResult, ExternalEvent,
    FileEntry, FileFilter, ImportOptions, RecoveryReport, ReindexReport, RepoConfig,
    RepoInitOptions, RepoPathValidation, ScanSession, SyncResult,
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
/// The API returns `Ok(())` after the empty repository can be read through
/// [`load_config`], `list_files`, and [`list_tree_json`]. It must never create,
/// delete, move, rename, or overwrite user-authored files such as `README.md`.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for empty paths or `.areamatrix` internals,
/// `CoreError::PermissionDenied` for unwritable roots, `CoreError::Config` for
/// invalid init options or repeated initialization, `CoreError::Io` for
/// filesystem failures, and `CoreError::Db` for SQLite initialization failures.
pub fn init_repo(_repo_path: String, _options: RepoInitOptions) -> CoreResult<()> {
    not_implemented()
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
pub fn load_config(_repo_path: String) -> CoreResult<RepoConfig> {
    not_implemented()
}

/// Updates repository configuration.
pub fn update_config(_repo_path: String, _new_config: RepoConfig) -> CoreResult<()> {
    not_implemented()
}

/// Performs startup recovery.
pub fn recover_on_startup(_repo_path: String) -> CoreResult<RecoveryReport> {
    not_implemented()
}

/// Reindexes a repository from the filesystem.
pub fn reindex_from_filesystem(_repo_path: String) -> CoreResult<ReindexReport> {
    not_implemented()
}

/// Returns the latest scan session if one exists.
pub fn get_latest_scan_session(_repo_path: String) -> CoreResult<Option<ScanSession>> {
    not_implemented()
}

/// Resumes a scan session.
pub fn resume_scan_session(_repo_path: String, _scan_session_id: i64) -> CoreResult<ReindexReport> {
    not_implemented()
}

/// Predicts a category for a filename.
pub fn predict_category(_repo_path: String, _filename: String) -> CoreResult<ClassifyResult> {
    not_implemented()
}

/// Imports a file into a repository.
pub fn import_file(
    _repo_path: String,
    _source_path: String,
    _options: ImportOptions,
) -> CoreResult<FileEntry> {
    not_implemented()
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

/// Lists file entries.
pub fn list_files(_repo_path: String, _filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    not_implemented()
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
pub fn list_tree_json(_repo_path: String, _locale: String) -> CoreResult<String> {
    not_implemented()
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
