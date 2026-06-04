use std::{
    fs::File,
    io::{BufReader, Read},
    path::{Component, Path, PathBuf},
};

use sha2::{Digest, Sha256};

use crate::{
    db::MissingFileRecoveryEntry, CoreError, CoreResult, FileOrigin, MissingFileReason, StorageMode,
};

const HASH_BUFFER_BYTES: usize = 64 * 1024;
const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(super) struct RelinkCandidate {
    pub(super) relative_path: String,
    pub(super) current_name: String,
    pub(super) category: String,
    pub(super) source_path: Option<String>,
    pub(super) hash_sha256: String,
    pub(super) size_bytes: i64,
}

pub(super) fn backing_file_path(repo: &Path, entry: &MissingFileRecoveryEntry) -> PathBuf {
    if matches!(entry.storage_mode, StorageMode::Indexed) {
        if let Some(source_path) = &entry.source_path {
            return PathBuf::from(source_path);
        }
    }
    repo.join(&entry.path)
}

pub(super) fn ensure_record_is_missing(path: &Path) -> CoreResult<()> {
    match path.try_exists() {
        Ok(false) => Ok(()),
        Ok(true) => Err(CoreError::file_not_found("missing file record")),
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            Err(CoreError::permission_denied(path.to_string_lossy()))
        }
        Err(error) => Err(CoreError::db(error.to_string())),
    }
}

pub(super) fn missing_reason(path: &Path) -> MissingFileReason {
    match path.try_exists() {
        Ok(false) => MissingFileReason::PathMissing,
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            MissingFileReason::PermissionDenied
        }
        _ => MissingFileReason::Unknown,
    }
}

pub(super) fn inspect_relink_candidate(
    repo: &Path,
    entry: &MissingFileRecoveryEntry,
    selected_path: &Path,
) -> CoreResult<RelinkCandidate> {
    let is_external_indexed =
        matches!(entry.storage_mode, StorageMode::Indexed) && is_external_indexed_entry(entry);
    let (relative_path, category, source_path) = if is_external_indexed {
        (
            selected_path.to_string_lossy().into_owned(),
            entry.category.clone(),
            Some(selected_path.to_string_lossy().into_owned()),
        )
    } else {
        let relative_path = repo_relative_path(repo, selected_path)?;
        let category = top_level_category(&relative_path);
        (relative_path, category, None)
    };
    let metadata = selected_path
        .metadata()
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::NotFound => CoreError::file_not_found("selected relink path"),
            std::io::ErrorKind::PermissionDenied => {
                CoreError::permission_denied(selected_path.to_string_lossy())
            }
            _ => CoreError::db(error.to_string()),
        })?;
    if !metadata.is_file() {
        return Err(CoreError::file_not_found("selected relink path"));
    }
    let hashed = hash_file(selected_path)?;
    let current_name = selected_path
        .file_name()
        .ok_or_else(|| CoreError::file_not_found("selected relink path"))?
        .to_string_lossy()
        .into_owned();

    Ok(RelinkCandidate {
        relative_path,
        current_name,
        category,
        source_path,
        hash_sha256: hashed.hash_sha256,
        size_bytes: hashed.size_bytes,
    })
}

pub(super) fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

pub(super) fn origin_detail(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

fn is_external_indexed_entry(entry: &MissingFileRecoveryEntry) -> bool {
    matches!(entry.storage_mode, StorageMode::Indexed)
        && matches!(entry.origin, FileOrigin::Imported)
        && entry.source_path.is_some()
}

fn repo_relative_path(repo: &Path, selected_path: &Path) -> CoreResult<String> {
    let relative = selected_path
        .strip_prefix(repo)
        .map_err(|_| CoreError::permission_denied("selected relink path must be inside repo"))?;
    validate_repo_relative_path(relative)?;
    Ok(relative.to_string_lossy().into_owned())
}

fn top_level_category(relative_path: &str) -> String {
    relative_path
        .split_once('/')
        .map(|(top_level, _)| top_level)
        .filter(|top_level| !top_level.is_empty())
        .unwrap_or("__root__")
        .to_owned()
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.as_os_str().is_empty() {
        return Err(CoreError::file_not_found("selected relink path"));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::permission_denied("selected relink path"));
        };
        if part == AREA_MATRIX_DIR {
            return Err(CoreError::permission_denied("selected relink path"));
        }
    }
    Ok(())
}

struct HashedFile {
    hash_sha256: String,
    size_bytes: i64,
}

fn hash_file(path: &Path) -> CoreResult<HashedFile> {
    let file = File::open(path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::file_not_found("selected relink path"),
        std::io::ErrorKind::PermissionDenied => {
            CoreError::permission_denied(path.to_string_lossy())
        }
        _ => CoreError::db(error.to_string()),
    })?;
    let mut reader = BufReader::with_capacity(HASH_BUFFER_BYTES, file);
    let mut hasher = Sha256::new();
    let mut size_bytes = 0_i64;
    let mut buffer = [0_u8; HASH_BUFFER_BYTES];
    loop {
        let read = reader
            .read(&mut buffer)
            .map_err(|error| match error.kind() {
                std::io::ErrorKind::PermissionDenied => {
                    CoreError::permission_denied(path.to_string_lossy())
                }
                _ => CoreError::db(error.to_string()),
            })?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        size_bytes += read as i64;
    }
    Ok(HashedFile {
        hash_sha256: format!("{:x}", hasher.finalize()),
        size_bytes,
    })
}
