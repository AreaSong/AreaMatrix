//! Public functions exposed through the UniFFI boundary.

use crate::{
    ChangeFilter, ChangeLogEntry, ClassifyResult, CoreError, CoreResult, ExternalEvent, FileEntry,
    FileFilter, ImportOptions, RecoveryReport, ReindexReport, RepoConfig, RepoInitOptions,
    RepoPathValidation, ScanSession, SyncResult,
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
/// # Errors
///
/// Returns `CoreError::InvalidPath`, `CoreError::PermissionDenied`,
/// `CoreError::ICloudPlaceholder`, or `CoreError::RepoNotInitialized` once the
/// C1-01 implementation task wires the read-only filesystem checks.
pub fn validate_repo_path(_repo_path: String) -> CoreResult<RepoPathValidation> {
    not_implemented()
}

/// Initializes a repository.
pub fn init_repo(_repo_path: String, _options: RepoInitOptions) -> CoreResult<()> {
    not_implemented()
}

/// Loads repository configuration.
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
