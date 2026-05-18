use std::{
    fs,
    path::{Component, Path, PathBuf},
    time::UNIX_EPOCH,
};

use sha2::{Digest, Sha256};
use walkdir::DirEntry;

use crate::{db, CoreError, CoreResult, ICloudConflictVersionRole};

use super::types::{ConflictBinding, ConflictCandidate, VersionState};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const CONFLICTED_COPY_MARKER: &str = "conflicted copy";

pub(super) fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::io("io error"));
    }
    let repo = PathBuf::from(repo_path);
    if has_icloud_placeholder_component(&repo) {
        return Err(CoreError::icloud_placeholder("icloud placeholder"));
    }
    Ok(repo)
}

pub(super) fn validate_initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    let repo = validate_repo_path(repo_path)?;
    db::ensure_initialized(&repo).map_err(normalize_optional_conflict_state_error)?;
    Ok(repo)
}

pub(super) fn bind_conflict(repo: &Path, conflict_id: &str) -> CoreResult<ConflictBinding> {
    if conflict_id.trim().is_empty() {
        return Err(CoreError::conflict("conflict id is required"));
    }

    let conflict_relative = Path::new(conflict_id);
    validate_repo_relative_path(conflict_relative)?;
    let conflicted_path = repo.join(conflict_relative);
    reject_placeholder_path(&conflicted_path)?;
    ensure_existing_regular_file(&conflicted_path)?;
    if !is_conflicted_copy(&conflicted_path) {
        return Err(CoreError::conflict(conflict_id.to_owned()));
    }

    let original_path = original_path_for_conflicted_copy(&conflicted_path);
    let original_relative_path = match original_path.as_deref() {
        Some(path) if path.try_exists().map_err(map_io_error)? => Some(relative_path(repo, path)?),
        Some(_) => None,
        None => return Err(CoreError::conflict("original version cannot be inferred")),
    };

    Ok(ConflictBinding {
        conflict_id: conflict_id.to_owned(),
        original_relative_path,
        conflicted_relative_path: conflict_id.to_owned(),
        original_path,
        conflicted_path,
    })
}

pub(super) fn version_states(binding: &ConflictBinding) -> CoreResult<Vec<VersionState>> {
    let mut versions = Vec::new();
    if let (Some(path), Some(relative_path)) = (
        binding.original_path.as_ref(),
        binding.original_relative_path.as_ref(),
    ) {
        versions.push(version_state(
            path,
            relative_path,
            ICloudConflictVersionRole::Original,
        )?);
    }
    versions.push(version_state(
        &binding.conflicted_path,
        &binding.conflicted_relative_path,
        ICloudConflictVersionRole::ConflictedCopy,
    )?);
    Ok(versions)
}

pub(super) fn candidate_for_path(
    repo: &Path,
    conflicted_path: &Path,
) -> CoreResult<ConflictCandidate> {
    reject_placeholder_path(conflicted_path)?;
    let relative_path = relative_path(repo, conflicted_path)?;
    let conflicted_modified_at = modified_at(conflicted_path)?;
    let original_path = original_path_for_conflicted_copy(conflicted_path);
    let (original_relative_path, original_modified_at, uncertainty_reason) =
        original_metadata(repo, original_path.as_deref())?;

    Ok(ConflictCandidate {
        relative_path,
        original_relative_path,
        original_modified_at,
        conflicted_modified_at,
        uncertainty_reason,
    })
}

pub(super) fn should_descend(repo: &Path, entry: &DirEntry) -> bool {
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

pub(super) fn is_conflicted_copy(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.to_ascii_lowercase().contains(CONFLICTED_COPY_MARKER))
        .unwrap_or(false)
}

pub(super) fn reject_placeholder_path(path: &Path) -> CoreResult<()> {
    if has_icloud_placeholder_component(path) {
        Err(CoreError::icloud_placeholder("icloud placeholder"))
    } else {
        Ok(())
    }
}

pub(super) fn map_walkdir_error(error: walkdir::Error) -> CoreError {
    if let Some(source) = error.io_error() {
        map_io_error(std::io::Error::new(source.kind(), source.to_string()))
    } else {
        CoreError::io(error.to_string())
    }
}

pub(super) fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        _ => CoreError::io(error.to_string()),
    }
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() || path.as_os_str().is_empty() {
        return Err(CoreError::conflict(path.display().to_string()));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::conflict(path.display().to_string()));
        };
        if part == AREA_MATRIX_DIR {
            return Err(CoreError::conflict(path.display().to_string()));
        }
    }
    Ok(())
}

fn version_state(
    path: &Path,
    relative_path: &str,
    role: ICloudConflictVersionRole,
) -> CoreResult<VersionState> {
    reject_placeholder_path(path)?;
    let metadata = path.metadata().map_err(map_io_error)?;
    if !metadata.is_file() {
        return Err(CoreError::conflict(relative_path.to_owned()));
    }
    Ok(VersionState {
        role,
        relative_path: relative_path.to_owned(),
        absolute_path: path.to_path_buf(),
        modified_at: modified_at_from_metadata(&metadata)?,
        size_bytes: metadata.len() as i64,
        hash_sha256: sha256_file(path)?,
    })
}

fn original_metadata(
    repo: &Path,
    original_path: Option<&Path>,
) -> CoreResult<(Option<String>, Option<i64>, Option<String>)> {
    let Some(original_path) = original_path else {
        return Ok((
            None,
            None,
            Some("original version cannot be inferred".to_owned()),
        ));
    };
    if !original_path.try_exists().map_err(map_io_error)? {
        return Ok((None, None, Some("original version not found".to_owned())));
    }

    Ok((
        Some(relative_path(repo, original_path)?),
        Some(modified_at(original_path)?),
        None,
    ))
}

fn ensure_existing_regular_file(path: &Path) -> CoreResult<()> {
    match path.metadata() {
        Ok(metadata) if metadata.is_file() => Ok(()),
        Ok(_) => Err(CoreError::conflict(path.display().to_string())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Err(CoreError::conflict(path.display().to_string()))
        }
        Err(error) => Err(map_io_error(error)),
    }
}

fn original_path_for_conflicted_copy(conflicted_path: &Path) -> Option<PathBuf> {
    let file_name = conflicted_path.file_name()?.to_str()?;
    let original_name = original_name_from_conflicted_copy(file_name)?;
    Some(conflicted_path.with_file_name(original_name))
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

fn relative_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::io(error.to_string()))
        .map(|relative| relative.to_string_lossy().replace('\\', "/"))
}

fn modified_at(path: &Path) -> CoreResult<i64> {
    let metadata = fs::metadata(path).map_err(map_io_error)?;
    modified_at_from_metadata(&metadata)
}

fn modified_at_from_metadata(metadata: &fs::Metadata) -> CoreResult<i64> {
    let modified = metadata.modified().map_err(map_io_error)?;
    let duration = modified
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::io(error.to_string()))?;
    Ok(duration.as_secs() as i64)
}

fn sha256_file(path: &Path) -> CoreResult<String> {
    let bytes = fs::read(path).map_err(map_io_error)?;
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    Ok(format!("{:x}", hasher.finalize()))
}

fn has_icloud_placeholder_component(path: &Path) -> bool {
    path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .to_ascii_lowercase()
            .ends_with(".icloud")
    })
}

fn normalize_optional_conflict_state_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::db("conflict state unavailable"),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::{original_name_from_conflicted_copy, should_descend};
    use walkdir::WalkDir;

    #[test]
    fn parses_standard_conflicted_copy_name() {
        assert_eq!(
            original_name_from_conflicted_copy("report (Alice's conflicted copy).pdf").as_deref(),
            Some("report.pdf")
        );
    }

    #[test]
    fn does_not_descend_into_metadata_directory() {
        let repo = tempfile::tempdir().expect("create temp repository");
        let metadata = repo.path().join(".areamatrix");
        std::fs::create_dir(&metadata).expect("create metadata directory");

        let root = WalkDir::new(repo.path())
            .max_depth(0)
            .into_iter()
            .next()
            .expect("root entry")
            .expect("root entry result");
        assert!(should_descend(repo.path(), &root));

        let metadata_entry = WalkDir::new(&metadata)
            .max_depth(0)
            .into_iter()
            .next()
            .expect("metadata entry")
            .expect("metadata entry result");
        assert!(!should_descend(repo.path(), &metadata_entry));
    }
}
