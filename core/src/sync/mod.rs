//! External filesystem synchronization.

use std::{
    collections::BTreeSet,
    fs,
    io::{self, Read},
    path::{Component, Path, PathBuf},
};

use serde_json::json;
use sha2::{Digest, Sha256};

use crate::{
    db::{self, ExternalCreatedRow, ExternalModifiedRow, ExternalRemovedRow, ExternalRenamedRow},
    overview, repo_path, CoreError, CoreResult, ExternalEvent, ExternalEventKind, SyncResult,
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
    previous_category: String,
}

struct RemovedPlan {
    row: ExternalRemovedRow,
}

struct ModifiedPlan {
    row: ExternalModifiedRow,
}

enum ModifiedEventPlan {
    Created(CreatedPlan),
    Modified(ModifiedPlan),
}

struct ResolvedEventPath {
    absolute_path: PathBuf,
    relative_path: String,
}

/// Synchronizes implemented external filesystem events into repository metadata.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for paths outside the initialized
/// repository, `CoreError::ICloudPlaceholder { path }` for placeholder paths,
/// `CoreError::PermissionDenied { path }` for unreadable files, `CoreError::FileNotFound { path }`
/// for missing renamed targets, `CoreError::Conflict { path }` for ambiguous rename pairing,
/// `CoreError::Io { message }` for metadata/hash failures,
/// or `CoreError::Db { message }` for transactional persistence failures.
pub(crate) fn sync_external_changes(
    repo_path: String,
    events: Vec<ExternalEvent>,
) -> CoreResult<SyncResult> {
    let repo = initialized_repo_path(&repo_path)?;
    let mut created_plans = Vec::new();
    let mut renamed_plans = Vec::new();
    let mut removed_plans = Vec::new();
    let mut modified_plans = Vec::new();
    let mut affected_nodes = BTreeSet::new();
    let mut max_sync_event_id = None;

    for event in events {
        validate_event_id(event.fs_event_id)?;
        max_sync_event_id = Some(max_event_id(max_sync_event_id, event.fs_event_id));
        if should_skip_event(&repo, &event.path)? {
            continue;
        }
        if let Some(node) = affected_node_for_event(&repo, &event)? {
            affected_nodes.insert(node);
        }
        match event.kind {
            ExternalEventKind::Created => {
                if let Some(plan) = plan_created_event(&repo, &event)? {
                    created_plans.push(plan);
                }
            }
            ExternalEventKind::Renamed => {
                if let Some(plan) = plan_renamed_event(&repo, &event)? {
                    affected_nodes.insert(plan.previous_category.clone());
                    renamed_plans.push(plan);
                }
            }
            ExternalEventKind::Removed => {
                if let Some(plan) = plan_removed_event(&repo, &event)? {
                    removed_plans.push(plan);
                }
            }
            ExternalEventKind::Modified => {
                if let Some(plan) = plan_modified_event(&repo, &event)? {
                    match plan {
                        ModifiedEventPlan::Created(plan) => created_plans.push(plan),
                        ModifiedEventPlan::Modified(plan) => modified_plans.push(plan),
                    }
                }
            }
        }
    }

    let renamed_file_ids = renamed_plans
        .iter()
        .map(|plan| plan.row.file_id)
        .collect::<BTreeSet<_>>();
    removed_plans.retain(|plan| !renamed_file_ids.contains(&plan.row.file_id));
    let created_rows = created_plans.into_iter().map(|plan| plan.row).collect();
    let renamed_rows = renamed_plans.into_iter().map(|plan| plan.row).collect();
    let modified_rows = modified_plans.into_iter().map(|plan| plan.row).collect();
    let removed_rows = removed_plans.into_iter().map(|plan| plan.row).collect();
    let applied = db::apply_external_sync_batch(
        &repo,
        created_rows,
        renamed_rows,
        modified_rows,
        removed_rows,
    )?;
    regenerate_affected_overviews(&repo, &affected_nodes)?;
    if let Some(cursor) = max_sync_event_id {
        db::set_fs_event_cursor(&repo, cursor)?;
    }

    Ok(SyncResult {
        detected_creates: applied.detected_creates,
        detected_renames: applied.detected_renames,
        detected_deletes: applied.detected_deletes,
        detected_modifies: applied.detected_modifies,
        errors: Vec::new(),
    })
}

/// Returns the latest processed filesystem event cursor.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` or `CoreError::Db { message }` when repository
/// metadata is absent or unreadable.
pub(crate) fn get_fs_event_cursor(repo_path: String) -> CoreResult<Option<i64>> {
    let repo = initialized_repo_path(&repo_path)?;
    db::get_fs_event_cursor(&repo)
}

/// Persists the latest processed filesystem event cursor.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for negative cursors,
/// `CoreError::RepoNotInitialized { path }` when metadata is absent, or `CoreError::Db { message }`
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
        return Err(CoreError::icloud_placeholder("icloud placeholder"));
    }

    let metadata = fs::symlink_metadata(&resolved.absolute_path).map_err(map_io_error)?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::invalid_path("invalid path"));
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
        return Err(CoreError::icloud_placeholder("icloud placeholder"));
    }

    let metadata =
        fs::symlink_metadata(&resolved.absolute_path).map_err(map_renamed_target_metadata_error)?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let hash_sha256 = sha256_file(&resolved.absolute_path)?;
    let current_name = file_name_from_relative(&resolved.relative_path)?;
    let category = category_for_relative_path(&resolved.relative_path);

    if let Some(active_at_target) = db::find_active_file_by_path(repo, &resolved.relative_path)? {
        if active_at_target.hash_sha256 == hash_sha256 {
            return Ok(None);
        }
        return Err(CoreError::conflict("path conflict"));
    }

    let candidates =
        db::find_external_rename_candidates_by_hash(repo, &hash_sha256, &resolved.relative_path)?;
    let candidate = match candidates.as_slice() {
        [candidate] => candidate,
        _ => return Err(CoreError::conflict("path conflict")),
    };
    let detail_json = external_rename_detail(
        &candidate.path,
        &resolved.relative_path,
        &candidate.current_name,
        &current_name,
        &candidate.category,
        &category,
    )?;

    Ok(Some(RenamedPlan {
        row: ExternalRenamedRow {
            file_id: candidate.id,
            path: resolved.relative_path,
            current_name,
            category: category.clone(),
            detail_json,
        },
        previous_category: candidate.category.clone(),
    }))
}

fn plan_modified_event(
    repo: &Path,
    event: &ExternalEvent,
) -> CoreResult<Option<ModifiedEventPlan>> {
    let Some(resolved) = resolve_event_path(repo, &event.path)? else {
        return Ok(None);
    };
    if has_icloud_placeholder_marker(Path::new(&resolved.relative_path)) {
        return Err(CoreError::icloud_placeholder("icloud placeholder"));
    }

    let metadata = fs::symlink_metadata(&resolved.absolute_path).map_err(map_io_error)?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let Some(file) = db::find_active_file_by_path(repo, &resolved.relative_path)? else {
        return plan_created_event(repo, event).map(|plan| plan.map(ModifiedEventPlan::Created));
    };
    let hash_sha256 = sha256_file(&resolved.absolute_path)?;
    let size_bytes = metadata.len() as i64;
    if file.hash_sha256 == hash_sha256 && file.size_bytes == size_bytes {
        return Ok(None);
    }
    let detail_json = external_modified_detail(
        &resolved.relative_path,
        &file.hash_sha256,
        &hash_sha256,
        file.size_bytes,
        size_bytes,
    )?;

    Ok(Some(ModifiedEventPlan::Modified(ModifiedPlan {
        row: ExternalModifiedRow {
            file_id: file.id,
            size_bytes,
            hash_sha256,
            detail_json,
        },
    })))
}

fn plan_removed_event(repo: &Path, event: &ExternalEvent) -> CoreResult<Option<RemovedPlan>> {
    let Some(resolved) = resolve_event_path(repo, &event.path)? else {
        return Ok(None);
    };
    if has_icloud_placeholder_marker(Path::new(&resolved.relative_path)) {
        return Err(CoreError::icloud_placeholder("icloud placeholder"));
    }
    ensure_path_absent(&resolved.absolute_path)?;

    let Some(file) = db::find_active_file_by_path(repo, &resolved.relative_path)? else {
        return Ok(None);
    };
    let detail_json = external_removed_detail()?;

    Ok(Some(RemovedPlan {
        row: ExternalRemovedRow {
            file_id: file.id,
            detail_json,
        },
    }))
}

fn affected_node_for_event(repo: &Path, event: &ExternalEvent) -> CoreResult<Option<String>> {
    resolve_event_path(repo, &event.path)
        .map(|resolved| resolved.map(|path| category_for_relative_path(&path.relative_path)))
}

fn regenerate_affected_overviews(repo: &Path, nodes: &BTreeSet<String>) -> CoreResult<()> {
    for node in nodes {
        overview::regenerate_for_node(repo, node)?;
    }
    Ok(())
}

fn resolve_event_path(repo: &Path, raw_path: &str) -> CoreResult<Option<ResolvedEventPath>> {
    if raw_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
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

fn should_skip_event(repo: &Path, raw_path: &str) -> CoreResult<bool> {
    let Some(resolved) = resolve_event_path(repo, raw_path)? else {
        return Ok(true);
    };
    is_managed_note_sidecar(repo, &resolved.relative_path)
}

fn is_managed_note_sidecar(repo: &Path, relative_path: &str) -> CoreResult<bool> {
    let Some(file_path) = relative_path.strip_suffix(".md") else {
        return Ok(false);
    };
    let Some(file) = db::find_active_file_by_path(repo, file_path)? else {
        return Ok(false);
    };
    db::read_note_content(repo, file.id).map(|note| note.is_some())
}

fn normalize_relative_path(path: &Path) -> CoreResult<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let Some(part) = part.to_str() else {
                    return Err(CoreError::invalid_path("invalid path"));
                };
                validate_relative_component(part)?;
                parts.push(part.to_owned());
            }
            _ => return Err(CoreError::invalid_path("invalid path")),
        }
    }
    if parts.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(parts.join("/"))
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))?;
    normalize_relative_path(relative)
}

fn validate_relative_component(component: &str) -> CoreResult<()> {
    if component.is_empty() || component == "." || component == ".." {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if component
        .chars()
        .any(|ch| ch.is_control() || FORBIDDEN_COMPONENT_CHARS.contains(&ch))
    {
        return Err(CoreError::invalid_path("invalid path"));
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
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
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
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn external_rename_detail(
    from_path: &str,
    to_path: &str,
    from_name: &str,
    to_name: &str,
    from_category: &str,
    to_category: &str,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "from_path": from_path,
        "to_path": to_path,
        "from_name": from_name,
        "to_name": to_name,
        "from_category": from_category,
        "to_category": to_category,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn external_modified_detail(
    relative_path: &str,
    hash_before: &str,
    hash_after: &str,
    size_before: i64,
    size_after: i64,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "kind": "content",
        "path": relative_path,
        "hash_before": hash_before,
        "hash_after": hash_after,
        "size_before": size_before,
        "size_after": size_after,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn external_removed_detail() -> CoreResult<String> {
    serde_json::to_string(&json!({
        "hard": false,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    repo_path::validate_initialized_repo_path(repo_path.to_owned())?;
    Ok(PathBuf::from(repo_path))
}

fn validate_event_id(event_id: i64) -> CoreResult<()> {
    if event_id < 0 {
        Err(CoreError::invalid_path("invalid path"))
    } else {
        Ok(())
    }
}

fn max_event_id(current: Option<i64>, candidate: i64) -> i64 {
    current.map_or(candidate, |value| value.max(candidate))
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

fn ensure_path_absent(path: &Path) -> CoreResult<()> {
    match fs::symlink_metadata(path) {
        Ok(_) => Err(CoreError::io("io error")),
        Err(error) => match error.kind() {
            io::ErrorKind::NotFound => Ok(()),
            io::ErrorKind::InvalidInput => Err(CoreError::invalid_path("invalid path")),
            io::ErrorKind::PermissionDenied => {
                Err(CoreError::permission_denied("permission denied"))
            }
            _ => Err(CoreError::io("io error")),
        },
    }
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("io error"),
    }
}

fn map_renamed_target_metadata_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("io error"),
    }
}
