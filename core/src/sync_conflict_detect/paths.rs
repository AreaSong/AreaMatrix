use std::{
    fs,
    io::Read,
    path::{Component, Path, PathBuf},
    time::UNIX_EPOCH,
};

use sha2::{Digest, Sha256};
use walkdir::{DirEntry, WalkDir};

use crate::{CoreError, CoreResult};

use super::{SyncConflictAffectedFile, SyncConflictFileRole};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const HASH_BUFFER_BYTES: usize = 64 * 1024;
const CONFLICTED_COPY_MARKER: &str = "conflicted copy";

pub(super) fn conflict_copy_paths(repo: &Path) -> CoreResult<Vec<PathBuf>> {
    let mut paths = Vec::new();
    for entry in WalkDir::new(repo)
        .follow_links(false)
        .same_file_system(true)
        .into_iter()
        .filter_entry(|entry| should_descend(repo, entry))
    {
        let entry = entry.map_err(map_walkdir_error)?;
        if entry.file_type().is_file() && is_conflicted_copy(entry.path()) {
            paths.push(entry.path().to_path_buf());
        }
    }
    Ok(paths)
}

pub(super) fn inspect_untracked_file(
    absolute_path: &Path,
    relative_path: &str,
) -> CoreResult<SyncConflictAffectedFile> {
    let metadata = fs::metadata(absolute_path).map_err(map_io_error)?;
    if !metadata.is_file() {
        return Err(CoreError::conflict(relative_path.to_owned()));
    }
    Ok(SyncConflictAffectedFile {
        path: relative_path.to_owned(),
        file_id: None,
        role: SyncConflictFileRole::ConflictCopy,
        size_bytes: Some(metadata.len() as i64),
        modified_at: modified_at_from_metadata(&metadata)?,
        hash_sha256: Some(sha256_file(absolute_path)?),
        source_platform: Some("filesystem".to_owned()),
    })
}

pub(super) fn original_path_for_conflicted_copy(relative_path: &str) -> Option<String> {
    let path = Path::new(relative_path);
    let file_name = path.file_name()?.to_str()?;
    let original_name = original_name_from_conflicted_copy(file_name)?;
    let original = path.with_file_name(original_name);
    path_to_forward_slash(&original)
}

pub(super) fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))?;
    let mut parts = Vec::new();
    for component in relative.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        if part == AREA_MATRIX_DIR {
            return Err(CoreError::invalid_path("invalid path"));
        }
        let Some(part) = part.to_str() else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        parts.push(part.to_owned());
    }
    if parts.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(parts.join("/"))
}

pub(super) fn modified_at_from_metadata(metadata: &fs::Metadata) -> CoreResult<Option<i64>> {
    match metadata.modified() {
        Ok(modified) => modified
            .duration_since(UNIX_EPOCH)
            .map(|duration| Some(duration.as_secs() as i64))
            .map_err(|_| CoreError::io("sync conflict metadata timestamp is invalid")),
        Err(error) => Err(map_io_error(error)),
    }
}

pub(super) fn sha256_file(path: &Path) -> CoreResult<String> {
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

pub(super) fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("sync conflict metadata inspection failed"),
    }
}

fn should_descend(repo: &Path, entry: &DirEntry) -> bool {
    if entry.path() == repo {
        return true;
    }
    entry
        .path()
        .strip_prefix(repo)
        .ok()
        .map(|relative| {
            !relative
                .components()
                .any(|component| component.as_os_str() == AREA_MATRIX_DIR)
        })
        .unwrap_or(false)
}

fn is_conflicted_copy(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.to_ascii_lowercase().contains(CONFLICTED_COPY_MARKER))
        .unwrap_or(false)
}

fn original_name_from_conflicted_copy(file_name: &str) -> Option<String> {
    let lower = file_name.to_ascii_lowercase();
    let marker_index = lower.find(CONFLICTED_COPY_MARKER)?;
    let prefix_end = lower[..marker_index].rfind('(')?;
    let suffix_start = lower[marker_index..]
        .find(')')
        .map(|offset| marker_index + offset + 1)?;

    let mut original = String::new();
    original.push_str(file_name[..prefix_end].trim_end());
    original.push_str(file_name[suffix_start..].trim_start());
    if original.is_empty() {
        None
    } else {
        Some(original)
    }
}

fn path_to_forward_slash(path: &Path) -> Option<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        let Component::Normal(part) = component else {
            return None;
        };
        parts.push(part.to_str()?.to_owned());
    }
    Some(parts.join("/"))
}

fn map_walkdir_error(error: walkdir::Error) -> CoreError {
    if let Some(source) = error.io_error() {
        map_io_error(std::io::Error::new(source.kind(), source.to_string()))
    } else {
        CoreError::io(error.to_string())
    }
}
