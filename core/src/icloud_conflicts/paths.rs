use std::{
    fs::{self, File},
    io::Read,
    path::{Component, Path, PathBuf},
    time::UNIX_EPOCH,
};

use sha2::{Digest, Sha256};
use walkdir::DirEntry;

use crate::{db, CoreError, CoreResult, ICloudConflictVersionRole};

use super::types::{ConflictBinding, ConflictCandidate, VersionState};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const CONFLICTED_COPY_MARKER: &str = "conflicted copy";
const HASH_BUFFER_BYTES: usize = 64 * 1024;

pub(super) fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
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
    // The repository root is part of the security boundary. A root or parent
    // symlink would make a lexical `repo.join(relative)` path ambiguous.
    repository_identity(&repo)?;
    Ok(repo)
}

pub(super) fn bind_conflict(repo: &Path, conflict_id: &str) -> CoreResult<ConflictBinding> {
    if conflict_id.trim().is_empty() {
        return Err(CoreError::conflict("conflict id is required"));
    }

    let repository_identity = repository_identity(repo)?;
    let conflict_relative = Path::new(conflict_id);
    validate_repo_relative_path(conflict_relative)?;
    ensure_repository_target(repo, conflict_relative)?;
    let conflicted_path = repo.join(conflict_relative);
    reject_placeholder_path(&conflicted_path)?;
    ensure_existing_regular_file(&conflicted_path)?;
    if !is_conflicted_copy(&conflicted_path) {
        return Err(CoreError::conflict(conflict_id.to_owned()));
    }

    let original_path = original_path_for_conflicted_copy(&conflicted_path);
    let original_relative_path = match original_path.as_deref() {
        Some(path) => match fs::symlink_metadata(path) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(CoreError::conflict(path.display().to_string()))
            }
            Ok(metadata) if metadata.is_file() => Some(relative_path(repo, path)?),
            Ok(_) => return Err(CoreError::conflict(path.display().to_string())),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(error) => return Err(map_io_error(error)),
        },
        None => return Err(CoreError::conflict("original version cannot be inferred")),
    };

    Ok(ConflictBinding {
        conflict_id: conflict_id.to_owned(),
        repository_path: repo.to_path_buf(),
        repository_identity,
        original_relative_path,
        conflicted_relative_path: conflict_id.to_owned(),
        original_path,
        conflicted_path,
    })
}

pub(super) fn version_states(binding: &ConflictBinding) -> CoreResult<Vec<VersionState>> {
    // Re-check the root and all ancestors on every read. This prevents a
    // preview/apply pair from silently crossing a replaced repository root.
    if repository_identity(&binding.repository_path)? != binding.repository_identity {
        return Err(CoreError::conflict(binding.conflict_id.clone()));
    }

    let mut versions = Vec::new();
    if let (Some(path), Some(relative_path)) = (
        binding.original_path.as_ref(),
        binding.original_relative_path.as_ref(),
    ) {
        ensure_repository_target(&binding.repository_path, Path::new(relative_path))?;
        versions.push(version_state(
            path,
            relative_path,
            ICloudConflictVersionRole::Original,
        )?);
    }
    ensure_repository_target(
        &binding.repository_path,
        Path::new(&binding.conflicted_relative_path),
    )?;
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
    ensure_existing_regular_file(conflicted_path)?;
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
    ensure_existing_regular_file(path)?;

    let ancestor_identity = directory_identity(path.parent().unwrap_or(path))?;
    let mut file = File::open(path).map_err(map_io_error)?;
    let before = file.metadata().map_err(map_io_error)?;
    ensure_regular_metadata(&before, relative_path)?;
    let hash_sha256 = sha256_reader(&mut file)?;
    let after = file.metadata().map_err(map_io_error)?;
    let path_after = fs::symlink_metadata(path).map_err(map_io_error)?;
    let ancestor_after = directory_identity(path.parent().unwrap_or(path))?;
    if ancestor_after != ancestor_identity
        || !same_file_identity(&before, &after)
        || !same_file_identity(&before, &path_after)
        || before.len() != after.len()
        || modified_nanos(&before)? != modified_nanos(&after)?
        || path_after.file_type().is_symlink()
        || !path_after.is_file()
    {
        return Err(CoreError::conflict(relative_path.to_owned()));
    }

    Ok(VersionState {
        role,
        relative_path: relative_path.to_owned(),
        absolute_path: path.to_path_buf(),
        modified_at: modified_at_from_metadata(&after)?,
        modified_at_nanos: modified_nanos(&after)?,
        size_bytes: after.len() as i64,
        hash_sha256,
        file_identity: metadata_identity(&after),
        ancestor_identity,
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
    let relative = original_path
        .strip_prefix(repo)
        .map_err(|error| CoreError::conflict(error.to_string()))?;
    ensure_repository_target(repo, relative)?;
    directory_identity(
        original_path
            .parent()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?,
    )?;
    match fs::symlink_metadata(original_path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            Err(CoreError::conflict(original_path.display().to_string()))
        }
        Ok(metadata) if metadata.is_file() => Ok((
            Some(relative_path(repo, original_path)?),
            Some(modified_at_from_metadata(&metadata)?),
            None,
        )),
        Ok(_) => Err(CoreError::conflict(original_path.display().to_string())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Ok((None, None, Some("original version not found".to_owned())))
        }
        Err(error) => Err(map_io_error(error)),
    }
}

fn ensure_existing_regular_file(path: &Path) -> CoreResult<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            Err(CoreError::conflict(path.display().to_string()))
        }
        Ok(metadata) if metadata.is_file() => {
            let parent = path
                .parent()
                .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
            directory_identity(parent).map(|_| ())
        }
        Ok(_) => Err(CoreError::conflict(path.display().to_string())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Err(CoreError::conflict(path.display().to_string()))
        }
        Err(error) => Err(map_io_error(error)),
    }
}

fn ensure_regular_metadata(metadata: &fs::Metadata, relative_path: &str) -> CoreResult<()> {
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        Err(CoreError::conflict(relative_path.to_owned()))
    } else {
        Ok(())
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
    let metadata = fs::symlink_metadata(path).map_err(map_io_error)?;
    if metadata.file_type().is_symlink() {
        return Err(CoreError::conflict(path.display().to_string()));
    }
    modified_at_from_metadata(&metadata)
}

fn modified_at_from_metadata(metadata: &fs::Metadata) -> CoreResult<i64> {
    Ok((modified_nanos(metadata)? / 1_000_000_000) as i64)
}

fn modified_nanos(metadata: &fs::Metadata) -> CoreResult<u128> {
    let modified = metadata.modified().map_err(map_io_error)?;
    let duration = modified
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::io(error.to_string()))?;
    Ok(duration.as_nanos())
}

fn sha256_reader(file: &mut File) -> CoreResult<String> {
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; HASH_BUFFER_BYTES];
    loop {
        let read = file.read(&mut buffer).map_err(map_io_error)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

#[cfg(unix)]
fn same_file_identity(left: &fs::Metadata, right: &fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;

    left.dev() == right.dev() && left.ino() == right.ino()
}

#[cfg(not(unix))]
fn same_file_identity(left: &fs::Metadata, right: &fs::Metadata) -> bool {
    left.len() == right.len() && modified_nanos(left).ok() == modified_nanos(right).ok()
}

#[cfg(unix)]
fn metadata_identity(metadata: &fs::Metadata) -> String {
    use std::os::unix::fs::MetadataExt;

    format!("unix:{}:{}", metadata.dev(), metadata.ino())
}

#[cfg(not(unix))]
fn metadata_identity(metadata: &fs::Metadata) -> String {
    format!(
        "portable:{}:{}",
        metadata.len(),
        modified_nanos(metadata).unwrap_or_default()
    )
}

/// Returns a stable identity for every existing directory in `path`'s chain.
/// Only the fixed macOS `/tmp` and `/var` aliases may be symlink ancestors;
/// repository-owned descendants are rejected instead of being followed.
/// The returned string is intentionally opaque to callers.
pub(super) fn directory_identity(path: &Path) -> CoreResult<String> {
    reject_untrusted_lexical_symlinks(path)?;
    let canonical = fs::canonicalize(path).map_err(map_io_error)?;
    let mut ancestors = canonical.ancestors().collect::<Vec<_>>();
    ancestors.reverse();
    let mut identity = String::new();
    for ancestor in ancestors {
        if ancestor.as_os_str().is_empty() {
            continue;
        }
        let metadata = fs::symlink_metadata(ancestor).map_err(map_io_error)?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(CoreError::conflict(ancestor.display().to_string()));
        }
        identity.push_str(&ancestor.to_string_lossy());
        identity.push('\0');
        identity.push_str(&metadata_identity(&metadata));
        identity.push('\0');
    }
    Ok(identity)
}

fn reject_untrusted_lexical_symlinks(path: &Path) -> CoreResult<()> {
    let mut ancestors = path.ancestors().collect::<Vec<_>>();
    ancestors.reverse();
    for ancestor in ancestors {
        let metadata = match fs::symlink_metadata(ancestor) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(map_io_error(error)),
        };
        if metadata.file_type().is_symlink() && !is_allowed_system_alias(ancestor) {
            return Err(CoreError::conflict(ancestor.display().to_string()));
        }
    }
    Ok(())
}

fn is_allowed_system_alias(path: &Path) -> bool {
    #[cfg(unix)]
    {
        let text = path.to_string_lossy();
        if text != "/tmp" && text != "/var" {
            return false;
        }
        // macOS exposes these aliases as links into `/private`.  Permit only
        // that fixed system mapping; a test or user-controlled link with the
        // same lexical name must not widen the repository trust boundary.
        fs::canonicalize(path)
            .map(|target| target.starts_with("/private"))
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        false
    }
}

fn repository_identity(repo: &Path) -> CoreResult<String> {
    let metadata = fs::symlink_metadata(repo).map_err(map_io_error)?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(CoreError::conflict(repo.display().to_string()));
    }
    let canonical = fs::canonicalize(repo).map_err(map_io_error)?;
    Ok(format!(
        "canonical={}\0chain={}",
        canonical.to_string_lossy(),
        directory_identity(repo)?
    ))
}

fn ensure_repository_target(repo: &Path, relative: &Path) -> CoreResult<()> {
    validate_repo_relative_path(relative)?;
    let mut current = repo.to_path_buf();
    for component in relative.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::conflict(relative.display().to_string()));
        };
        current.push(part);
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(CoreError::conflict(current.display().to_string()))
            }
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
            Err(error) => return Err(map_io_error(error)),
        }
    }
    let canonical_repo = fs::canonicalize(repo).map_err(map_io_error)?;
    if let Ok(canonical_target) = fs::canonicalize(repo.join(relative)) {
        if !canonical_target.starts_with(&canonical_repo) {
            return Err(CoreError::conflict(relative.display().to_string()));
        }
    }
    Ok(())
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
