//! External filesystem synchronization.

use std::{
    fs,
    io::{self, Read},
    path::{Component, Path, PathBuf},
};

use serde_json::json;
use sha2::{Digest, Sha256};

use crate::{
    db::{self, ExternalCreatedRow, ExternalRenamedRow},
    repo_path, CoreError, CoreResult, ExternalEvent, ExternalEventKind, SyncResult,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const ROOT_OVERVIEW_FILE: &str = "AREAMATRIX.md";
const HASH_BUFFER_BYTES: usize = 64 * 1024;
const FORBIDDEN_COMPONENT_CHARS: &[char] = &['/', '\\', ':', '*', '?', '"', '<', '>', '|'];

struct CreatedPlan {
    row: ExternalCreatedRow,
}

struct RenamedPlan {
    row: ExternalRenamedRow,
}

struct ResolvedEventPath {
    absolute_path: PathBuf,
    relative_path: String,
}

/// Synchronizes implemented external filesystem events into repository metadata.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for paths outside the initialized
/// repository, `CoreError::ICloudPlaceholder` for placeholder paths,
/// `CoreError::PermissionDenied` for unreadable files, `CoreError::FileNotFound`
/// for missing renamed targets, `CoreError::Conflict` for ambiguous or
/// cross-category rename pairing, `CoreError::Io` for metadata/hash failures,
/// or `CoreError::Db` for transactional persistence failures.
pub(crate) fn sync_external_changes(
    repo_path: String,
    events: Vec<ExternalEvent>,
) -> CoreResult<SyncResult> {
    let repo = initialized_repo_path(&repo_path)?;
    let mut created_plans = Vec::new();
    let mut renamed_plans = Vec::new();
    let mut max_sync_event_id = None;
    let mut has_out_of_scope_events = false;

    for event in events {
        match event.kind {
            ExternalEventKind::Created => {
                validate_event_id(event.fs_event_id)?;
                max_sync_event_id = Some(max_event_id(max_sync_event_id, event.fs_event_id));
                if let Some(plan) = plan_created_event(&repo, &event)? {
                    created_plans.push(plan);
                }
            }
            ExternalEventKind::Renamed => {
                validate_event_id(event.fs_event_id)?;
                max_sync_event_id = Some(max_event_id(max_sync_event_id, event.fs_event_id));
                if let Some(plan) = plan_renamed_event(&repo, &event)? {
                    renamed_plans.push(plan);
                }
            }
            ExternalEventKind::Removed | ExternalEventKind::Modified => {
                has_out_of_scope_events = true;
            }
        }
    }

    let cursor = cursor_for_batch(max_sync_event_id, has_out_of_scope_events);
    let created_rows = created_plans.into_iter().map(|plan| plan.row).collect();
    let renamed_rows = renamed_plans.into_iter().map(|plan| plan.row).collect();
    let applied = db::apply_external_sync_batch(&repo, created_rows, renamed_rows, cursor)?;

    Ok(SyncResult {
        detected_creates: applied.detected_creates,
        detected_renames: applied.detected_renames,
        detected_deletes: 0,
        detected_modifies: 0,
        errors: Vec::new(),
    })
}

/// Returns the latest processed filesystem event cursor.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized` or `CoreError::Db` when repository
/// metadata is absent or unreadable.
pub(crate) fn get_fs_event_cursor(repo_path: String) -> CoreResult<Option<i64>> {
    let repo = initialized_repo_path(&repo_path)?;
    db::get_fs_event_cursor(&repo)
}

/// Persists the latest processed filesystem event cursor.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath` for negative cursors,
/// `CoreError::RepoNotInitialized` when metadata is absent, or `CoreError::Db`
/// when SQLite persistence fails.
pub(crate) fn set_fs_event_cursor(repo_path: String, last_event_id: i64) -> CoreResult<()> {
    validate_event_id(last_event_id)?;
    let repo = initialized_repo_path(&repo_path)?;
    db::set_fs_event_cursor(&repo, last_event_id)
}

fn plan_created_event(repo: &Path, event: &ExternalEvent) -> CoreResult<Option<CreatedPlan>> {
    let Some(resolved) = resolve_event_path(repo, &event.path)? else {
        return Ok(None);
    };
    if has_icloud_placeholder_marker(Path::new(&resolved.relative_path)) {
        return Err(CoreError::ICloudPlaceholder);
    }

    let metadata = fs::symlink_metadata(&resolved.absolute_path).map_err(map_io_error)?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::InvalidPath);
    }

    let hash_sha256 = sha256_file(&resolved.absolute_path)?;
    let current_name = file_name_from_relative(&resolved.relative_path)?;
    let category = category_for_relative_path(&resolved.relative_path);
    let detail_json = external_create_detail(
        &resolved.relative_path,
        &category,
        &hash_sha256,
        metadata.len() as i64,
    )?;

    Ok(Some(CreatedPlan {
        row: ExternalCreatedRow {
            path: resolved.relative_path,
            original_name: current_name.clone(),
            current_name,
            category,
            size_bytes: metadata.len() as i64,
            hash_sha256,
            detail_json,
        },
    }))
}

fn plan_renamed_event(repo: &Path, event: &ExternalEvent) -> CoreResult<Option<RenamedPlan>> {
    let Some(resolved) = resolve_event_path(repo, &event.path)? else {
        return Ok(None);
    };
    if has_icloud_placeholder_marker(Path::new(&resolved.relative_path)) {
        return Err(CoreError::ICloudPlaceholder);
    }

    let metadata =
        fs::symlink_metadata(&resolved.absolute_path).map_err(map_renamed_target_metadata_error)?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::InvalidPath);
    }

    let hash_sha256 = sha256_file(&resolved.absolute_path)?;
    let current_name = file_name_from_relative(&resolved.relative_path)?;
    let category = category_for_relative_path(&resolved.relative_path);

    if let Some(active_at_target) = db::find_active_file_by_path(repo, &resolved.relative_path)? {
        if active_at_target.hash_sha256 == hash_sha256 {
            return Ok(None);
        }
        return Err(CoreError::Conflict);
    }

    let candidates =
        db::find_external_rename_candidates_by_hash(repo, &hash_sha256, &resolved.relative_path)?;
    let candidate = match candidates.as_slice() {
        [candidate] => candidate,
        _ => return Err(CoreError::Conflict),
    };
    if candidate.category != category {
        return Err(CoreError::Conflict);
    }

    let detail_json = external_rename_detail(
        &candidate.path,
        &resolved.relative_path,
        &candidate.current_name,
        &current_name,
    )?;

    Ok(Some(RenamedPlan {
        row: ExternalRenamedRow {
            file_id: candidate.id,
            path: resolved.relative_path,
            current_name,
            detail_json,
        },
    }))
}

fn resolve_event_path(repo: &Path, raw_path: &str) -> CoreResult<Option<ResolvedEventPath>> {
    if raw_path.trim().is_empty() {
        return Err(CoreError::InvalidPath);
    }

    let raw = Path::new(raw_path);
    let relative_path = if raw.is_absolute() {
        relative_repo_path(repo, raw)?
    } else {
        normalize_relative_path(raw)?
    };
    if should_skip_relative_path(&relative_path) {
        return Ok(None);
    }

    Ok(Some(ResolvedEventPath {
        absolute_path: repo.join(&relative_path),
        relative_path,
    }))
}

fn normalize_relative_path(path: &Path) -> CoreResult<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let Some(part) = part.to_str() else {
                    return Err(CoreError::InvalidPath);
                };
                validate_relative_component(part)?;
                parts.push(part.to_owned());
            }
            _ => return Err(CoreError::InvalidPath),
        }
    }
    if parts.is_empty() {
        return Err(CoreError::InvalidPath);
    }
    Ok(parts.join("/"))
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|_| CoreError::InvalidPath)?;
    normalize_relative_path(relative)
}

fn validate_relative_component(component: &str) -> CoreResult<()> {
    if component.is_empty() || component == "." || component == ".." {
        return Err(CoreError::InvalidPath);
    }
    if component
        .chars()
        .any(|ch| ch.is_control() || FORBIDDEN_COMPONENT_CHARS.contains(&ch))
    {
        return Err(CoreError::InvalidPath);
    }
    Ok(())
}

fn should_skip_relative_path(relative_path: &str) -> bool {
    relative_path == ROOT_OVERVIEW_FILE
        || relative_path
            .split('/')
            .any(|component| component == AREA_MATRIX_DIR)
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

fn category_for_relative_path(relative_path: &str) -> String {
    match relative_path.split_once('/') {
        Some((top_level, _)) if !top_level.is_empty() => top_level.to_owned(),
        _ => "__root__".to_owned(),
    }
}

fn file_name_from_relative(relative_path: &str) -> CoreResult<String> {
    relative_path
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
        .ok_or(CoreError::InvalidPath)
}

fn external_create_detail(
    relative_path: &str,
    category: &str,
    hash_sha256: &str,
    size_bytes: i64,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "kind": "create",
        "path": relative_path,
        "category": category,
        "hash_after": hash_sha256,
        "size_bytes": size_bytes,
        "by": "external",
    }))
    .map_err(|_| CoreError::Internal)
}

fn external_rename_detail(
    from_path: &str,
    to_path: &str,
    from_name: &str,
    to_name: &str,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "from_path": from_path,
        "to_path": to_path,
        "from_name": from_name,
        "to_name": to_name,
        "by": "external",
    }))
    .map_err(|_| CoreError::Internal)
}

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    repo_path::validate_initialized_repo_path(repo_path.to_owned())?;
    Ok(PathBuf::from(repo_path))
}

fn validate_event_id(event_id: i64) -> CoreResult<()> {
    if event_id < 0 {
        Err(CoreError::InvalidPath)
    } else {
        Ok(())
    }
}

fn max_event_id(current: Option<i64>, candidate: i64) -> i64 {
    current.map_or(candidate, |value| value.max(candidate))
}

fn cursor_for_batch(max_sync_event_id: Option<i64>, has_out_of_scope_events: bool) -> Option<i64> {
    if has_out_of_scope_events {
        None
    } else {
        max_sync_event_id
    }
}

fn sha256_file(path: &Path) -> CoreResult<String> {
    let mut file = fs::File::open(path).map_err(map_io_error)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; HASH_BUFFER_BYTES];

    loop {
        let bytes_read = file.read(&mut buffer).map_err(map_io_error)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        _ => CoreError::Io,
    }
}

fn map_renamed_target_metadata_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::NotFound => CoreError::FileNotFound,
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        _ => CoreError::Io,
    }
}
