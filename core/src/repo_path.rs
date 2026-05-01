//! Read-only repository path validation.

use std::{
    fs::{self, Metadata},
    io,
    path::Path,
};

use rusqlite::{Connection, OpenFlags};

use crate::{CoreError, CoreResult, RepoInitMode, RepoPathIssue, RepoPathValidation};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

/// Validates a candidate repository path without mutating user files.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for an empty path or a path inside
/// `.areamatrix/`, `CoreError::PermissionDenied` when read-only inspection is
/// blocked, `CoreError::ICloudPlaceholder` for placeholder markers, and
/// `CoreError::Db` if existing scan-session metadata cannot be read.
pub(crate) fn validate_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    if repo_path.is_empty() {
        return Err(CoreError::InvalidPath);
    }

    let path = Path::new(&repo_path);
    if is_inside_area_matrix(path) {
        return Err(CoreError::InvalidPath);
    }
    if has_icloud_placeholder_marker(path) {
        return Err(CoreError::ICloudPlaceholder);
    }

    let is_icloud_path = is_likely_icloud_path(path);
    let mut issues = Vec::new();
    if is_icloud_path {
        issues.push(RepoPathIssue::ICloudPath);
    }

    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => {
            return validation_for_missing_or_blocked(repo_path, is_icloud_path, issues, error)
        }
    };

    if !metadata.is_dir() {
        issues.push(RepoPathIssue::NotDirectory);
        return Ok(RepoPathValidation {
            repo_path,
            exists: true,
            is_directory: false,
            is_readable: false,
            is_writable: false,
            is_empty: false,
            is_initialized: false,
            is_inside_area_matrix: false,
            is_icloud_path,
            has_unfinished_scan_session: false,
            recommended_mode: None,
            issues,
        });
    }

    let is_writable = metadata_allows_write(&metadata);
    if !is_writable {
        issues.push(RepoPathIssue::NotWritable);
    }

    let directory_state = inspect_directory(path)?;
    if !directory_state.is_empty {
        issues.push(RepoPathIssue::NonEmptyDirectory);
    }
    if directory_state.is_initialized {
        issues.push(RepoPathIssue::AlreadyInitialized);
    }
    if directory_state.has_unfinished_scan_session {
        issues.push(RepoPathIssue::UnfinishedScanSession);
    }

    let recommended_mode = recommend_mode(
        is_writable,
        directory_state.is_empty,
        directory_state.is_initialized,
        directory_state.has_unfinished_scan_session,
    );

    Ok(RepoPathValidation {
        repo_path,
        exists: true,
        is_directory: true,
        is_readable: true,
        is_writable,
        is_empty: directory_state.is_empty,
        is_initialized: directory_state.is_initialized,
        is_inside_area_matrix: false,
        is_icloud_path,
        has_unfinished_scan_session: directory_state.has_unfinished_scan_session,
        recommended_mode,
        issues,
    })
}

struct DirectoryState {
    is_empty: bool,
    is_initialized: bool,
    has_unfinished_scan_session: bool,
}

fn validation_for_missing_or_blocked(
    repo_path: String,
    is_icloud_path: bool,
    mut issues: Vec<RepoPathIssue>,
    error: io::Error,
) -> CoreResult<RepoPathValidation> {
    match error.kind() {
        io::ErrorKind::NotFound => {
            issues.push(RepoPathIssue::MissingPath);
            Ok(RepoPathValidation {
                repo_path,
                exists: false,
                is_directory: false,
                is_readable: false,
                is_writable: false,
                is_empty: false,
                is_initialized: false,
                is_inside_area_matrix: false,
                is_icloud_path,
                has_unfinished_scan_session: false,
                recommended_mode: None,
                issues,
            })
        }
        io::ErrorKind::InvalidInput => Err(CoreError::InvalidPath),
        io::ErrorKind::PermissionDenied => Err(CoreError::PermissionDenied),
        _ => Err(CoreError::Io),
    }
}

fn inspect_directory(path: &Path) -> CoreResult<DirectoryState> {
    let mut has_user_visible_entries = false;
    let entries = fs::read_dir(path).map_err(map_directory_read_error)?;
    for entry in entries {
        let entry = entry.map_err(map_directory_read_error)?;
        if is_user_visible_entry(&entry.file_name().to_string_lossy()) {
            has_user_visible_entries = true;
        }
    }

    let is_initialized = metadata_dir_exists(&path.join(AREA_MATRIX_DIR))?;
    let has_unfinished_scan_session = if is_initialized {
        has_unfinished_scan_session(path)?
    } else {
        false
    };

    Ok(DirectoryState {
        is_empty: !has_user_visible_entries,
        is_initialized,
        has_unfinished_scan_session,
    })
}

fn map_directory_read_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}

fn metadata_dir_exists(path: &Path) -> CoreResult<bool> {
    match fs::metadata(path) {
        Ok(metadata) => Ok(metadata.is_dir()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            Err(CoreError::PermissionDenied)
        }
        Err(error) if error.kind() == io::ErrorKind::InvalidInput => Err(CoreError::InvalidPath),
        Err(_) => Err(CoreError::Io),
    }
}

fn has_unfinished_scan_session(repo_path: &Path) -> CoreResult<bool> {
    let db_path = repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    match db_path.try_exists() {
        Ok(true) => {}
        Ok(false) => return Ok(false),
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            return Err(CoreError::PermissionDenied);
        }
        Err(error) if error.kind() == io::ErrorKind::InvalidInput => {
            return Err(CoreError::InvalidPath);
        }
        Err(_) => return Err(CoreError::Io),
    }

    let connection = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|_| CoreError::Db)?;
    let table_exists: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'scan_sessions'",
            [],
            |row| row.get(0),
        )
        .map_err(|_| CoreError::Db)?;

    if table_exists == 0 {
        return Ok(false);
    }

    let unfinished_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM scan_sessions \
             WHERE kind IN ('adopt', 'reindex') \
             AND status IN ('running', 'paused', 'failed', 'interrupted')",
            [],
            |row| row.get(0),
        )
        .map_err(|_| CoreError::Db)?;

    Ok(unfinished_count > 0)
}

fn recommend_mode(
    is_writable: bool,
    is_empty: bool,
    is_initialized: bool,
    has_unfinished_scan_session: bool,
) -> Option<RepoInitMode> {
    if !is_writable || is_initialized || has_unfinished_scan_session {
        return None;
    }

    if is_empty {
        Some(RepoInitMode::CreateEmpty)
    } else {
        Some(RepoInitMode::AdoptExisting)
    }
}

fn is_user_visible_entry(name: &str) -> bool {
    !name.starts_with('.')
}

fn is_inside_area_matrix(path: &Path) -> bool {
    path.components()
        .any(|component| component.as_os_str() == AREA_MATRIX_DIR)
}

fn has_icloud_placeholder_marker(path: &Path) -> bool {
    path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .to_ascii_lowercase()
            .ends_with(".icloud")
    })
}

fn is_likely_icloud_path(path: &Path) -> bool {
    path.components().any(|component| {
        let component = component.as_os_str().to_string_lossy().to_ascii_lowercase();
        component == "mobile documents"
            || component == "icloud drive"
            || component.starts_with("com~apple~clouddocs")
    })
}

#[cfg(unix)]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o222 != 0
}

#[cfg(not(unix))]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    !metadata.permissions().readonly()
}
