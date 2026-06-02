//! Read-only repository path validation.

use std::{
    ffi::OsStr,
    fs::{self, Metadata},
    io,
    path::{Component, Path},
};

use rusqlite::{Connection, OpenFlags};

use crate::{
    repo_entries, CoreError, CoreResult, PlatformPathKind, RepoInitMode, RepoPathIssue,
    RepoPathValidation,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

/// Validates a candidate repository path without mutating user files.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for an empty path or a path inside
/// `.areamatrix/`, `CoreError::PermissionDenied { path }` when read-only inspection is
/// blocked, `CoreError::ICloudPlaceholder { path }` for placeholder markers, and
/// `CoreError::Db { message }` if existing scan-session metadata cannot be read.
pub(crate) fn validate_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    validate_repo_path_with_requirement(repo_path, InitializationRequirement::Optional)
}

/// Validates a path that must already be an AreaMatrix repository.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when the selected directory is
/// inspectable but lacks `.areamatrix/` metadata.
pub(crate) fn validate_initialized_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    validate_repo_path_with_requirement(repo_path, InitializationRequirement::Required)
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum InitializationRequirement {
    Optional,
    Required,
}

fn validate_repo_path_with_requirement(
    repo_path: String,
    initialization_requirement: InitializationRequirement,
) -> CoreResult<RepoPathValidation> {
    if repo_path.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let path = Path::new(&repo_path);
    if is_inside_area_matrix(path) {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if has_icloud_placeholder_marker(path) {
        return Err(CoreError::icloud_placeholder("icloud placeholder"));
    }

    let path_characteristics = classify_platform_path(path);
    if path_characteristics.has_windows_reserved_name {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let is_icloud_path = path_characteristics.platform_path_kind == PlatformPathKind::ICloudDrive;
    let is_onedrive_path = path_characteristics.platform_path_kind == PlatformPathKind::OneDrive;
    let mut issues = Vec::new();
    if is_icloud_path {
        issues.push(RepoPathIssue::ICloudPath);
    }
    if is_onedrive_path {
        issues.push(RepoPathIssue::OneDrivePath);
    }
    if !path_characteristics.is_case_sensitive_path {
        issues.push(RepoPathIssue::WindowsCaseInsensitive);
    }

    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => {
            return validation_for_missing_or_blocked(
                repo_path,
                &path_characteristics,
                issues,
                error,
            )
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
            is_onedrive_path,
            platform_path_kind: path_characteristics.platform_path_kind,
            is_case_sensitive_path: path_characteristics.is_case_sensitive_path,
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
    if initialization_requirement == InitializationRequirement::Required
        && !directory_state.is_initialized
    {
        return Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ));
    }

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
        is_onedrive_path,
        platform_path_kind: path_characteristics.platform_path_kind,
        is_case_sensitive_path: path_characteristics.is_case_sensitive_path,
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
    path_characteristics: &PathCharacteristics,
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
                is_icloud_path: path_characteristics.platform_path_kind
                    == PlatformPathKind::ICloudDrive,
                is_onedrive_path: path_characteristics.platform_path_kind
                    == PlatformPathKind::OneDrive,
                platform_path_kind: path_characteristics.platform_path_kind.clone(),
                is_case_sensitive_path: path_characteristics.is_case_sensitive_path,
                has_unfinished_scan_session: false,
                recommended_mode: None,
                issues,
            })
        }
        io::ErrorKind::InvalidInput => Err(CoreError::invalid_path("invalid path")),
        io::ErrorKind::PermissionDenied => Err(CoreError::permission_denied("permission denied")),
        _ => Err(CoreError::io("io error")),
    }
}

fn inspect_directory(path: &Path) -> CoreResult<DirectoryState> {
    let mut has_user_content_entries = false;
    let entries = fs::read_dir(path).map_err(map_directory_read_error)?;
    for entry in entries {
        let entry = entry.map_err(map_directory_read_error)?;
        if is_area_matrix_metadata_dir(&entry)? {
            continue;
        }
        if repo_entries::is_user_content_entry(&entry).map_err(map_directory_read_error)? {
            has_user_content_entries = true;
        }
    }

    let is_initialized = metadata_dir_exists(&path.join(AREA_MATRIX_DIR))?;
    let has_unfinished_scan_session = if is_initialized {
        has_unfinished_scan_session(path)?
    } else {
        false
    };

    Ok(DirectoryState {
        is_empty: !has_user_content_entries,
        is_initialized,
        has_unfinished_scan_session,
    })
}

fn map_directory_read_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

fn metadata_dir_exists(path: &Path) -> CoreResult<bool> {
    match fs::metadata(path) {
        Ok(metadata) => Ok(metadata.is_dir()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            Err(CoreError::permission_denied("permission denied"))
        }
        Err(error) if error.kind() == io::ErrorKind::InvalidInput => {
            Err(CoreError::invalid_path("invalid path"))
        }
        Err(_) => Err(CoreError::io("io error")),
    }
}

fn has_unfinished_scan_session(repo_path: &Path) -> CoreResult<bool> {
    let db_path = repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    match db_path.try_exists() {
        Ok(true) => {}
        Ok(false) => return Ok(false),
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            return Err(CoreError::permission_denied("permission denied"));
        }
        Err(error) if error.kind() == io::ErrorKind::InvalidInput => {
            return Err(CoreError::invalid_path("invalid path"));
        }
        Err(_) => return Err(CoreError::io("io error")),
    }

    let connection = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let table_exists: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'scan_sessions'",
            [],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;

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
        .map_err(|error| CoreError::db(error.to_string()))?;

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

fn is_area_matrix_metadata_dir(entry: &fs::DirEntry) -> CoreResult<bool> {
    if entry.file_name() != AREA_MATRIX_DIR {
        return Ok(false);
    }

    entry
        .file_type()
        .map(|file_type| file_type.is_dir())
        .map_err(map_directory_read_error)
}

fn is_inside_area_matrix(path: &Path) -> bool {
    if path
        .components()
        .any(|component| component.as_os_str() == AREA_MATRIX_DIR)
    {
        return true;
    }

    let components = path_components(path);
    if !is_windows_shaped_path(path, &components) {
        return false;
    }

    components
        .iter()
        .any(|component| component.eq_ignore_ascii_case(AREA_MATRIX_DIR))
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

struct PathCharacteristics {
    platform_path_kind: PlatformPathKind,
    is_case_sensitive_path: bool,
    has_windows_reserved_name: bool,
}

fn classify_platform_path(path: &Path) -> PathCharacteristics {
    let components = path_components(path);
    let windows_shaped = is_windows_shaped_path(path, &components);
    let platform_path_kind = platform_path_kind(path, &components, windows_shaped);
    PathCharacteristics {
        platform_path_kind,
        is_case_sensitive_path: !windows_shaped,
        has_windows_reserved_name: windows_shaped
            && components
                .iter()
                .any(|component| is_windows_reserved_name(component)),
    }
}

fn path_components(path: &Path) -> Vec<String> {
    path.components()
        .filter_map(component_to_string)
        .flat_map(split_windows_separators)
        .filter(|component| !component.is_empty())
        .collect()
}

fn component_to_string(component: Component<'_>) -> Option<String> {
    match component {
        Component::Prefix(prefix) => Some(prefix.as_os_str().to_string_lossy().into_owned()),
        Component::RootDir | Component::CurDir | Component::ParentDir => None,
        Component::Normal(value) => Some(value.to_string_lossy().into_owned()),
    }
}

fn split_windows_separators(component: String) -> impl Iterator<Item = String> {
    component
        .split(['\\', '/'])
        .map(str::to_owned)
        .collect::<Vec<_>>()
        .into_iter()
}

fn is_windows_shaped_path(path: &Path, components: &[String]) -> bool {
    let raw = path.as_os_str().to_string_lossy();
    has_windows_drive_prefix(&raw)
        || raw.starts_with("\\\\")
        || raw.starts_with("//")
        || raw.contains('\\')
        || components.iter().any(|component| component.contains('\\'))
}

fn has_windows_drive_prefix(raw: &str) -> bool {
    let bytes = raw.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':'
}

fn platform_path_kind(
    path: &Path,
    components: &[String],
    windows_shaped: bool,
) -> PlatformPathKind {
    let raw = path.as_os_str().to_string_lossy();
    if windows_shaped && (raw.starts_with("\\\\") || raw.starts_with("//")) {
        return PlatformPathKind::NetworkShare;
    }
    if components.iter().any(is_icloud_component) {
        return PlatformPathKind::ICloudDrive;
    }
    if components.iter().any(is_onedrive_component) {
        return PlatformPathKind::OneDrive;
    }
    PlatformPathKind::Local
}

fn is_icloud_component(component: &String) -> bool {
    let component = component.to_ascii_lowercase();
    component == "mobile documents"
        || component == "icloud drive"
        || component.starts_with("com~apple~clouddocs")
}

fn is_onedrive_component(component: &String) -> bool {
    let component = component.to_ascii_lowercase();
    component.contains("onedrive") || component.contains("one drive")
}

fn is_windows_reserved_name(component: &String) -> bool {
    let stem = windows_component_stem(component);
    matches!(
        stem.as_str(),
        "con"
            | "prn"
            | "aux"
            | "nul"
            | "com1"
            | "com2"
            | "com3"
            | "com4"
            | "com5"
            | "com6"
            | "com7"
            | "com8"
            | "com9"
            | "lpt1"
            | "lpt2"
            | "lpt3"
            | "lpt4"
            | "lpt5"
            | "lpt6"
            | "lpt7"
            | "lpt8"
            | "lpt9"
    )
}

fn windows_component_stem(component: &str) -> String {
    OsStr::new(component)
        .to_string_lossy()
        .trim_end_matches([' ', '.'])
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase()
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
