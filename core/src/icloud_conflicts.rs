//! Read-only iCloud conflicted copy listing.

use std::{
    fs,
    path::{Path, PathBuf},
    time::UNIX_EPOCH,
};

use walkdir::{DirEntry, WalkDir};

use crate::{CoreError, CoreResult, ICloudConflictPair, ICloudConflictStatus};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const CONFLICTED_COPY_MARKER: &str = "conflicted copy";

struct ConflictCandidate {
    relative_path: String,
    original_relative_path: Option<String>,
    original_modified_at: Option<i64>,
    conflicted_modified_at: i64,
    uncertainty_reason: Option<String>,
}

/// Lists iCloud conflicted copy pairs without mutating repository files.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder` when a scanned candidate is still an
/// iCloud placeholder, `PermissionDenied` for blocked metadata reads, and `Io`
/// for filesystem traversal or timestamp conversion failures.
pub(crate) fn list_icloud_conflicts(repo_path: String) -> CoreResult<Vec<ICloudConflictPair>> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::io("io error"));
    }

    let repo = PathBuf::from(repo_path);
    reject_placeholder_path(&repo)?;
    let mut conflicts = Vec::new();

    for entry in WalkDir::new(&repo)
        .follow_links(false)
        .same_file_system(true)
        .into_iter()
        .filter_entry(|entry| should_descend(&repo, entry))
    {
        let entry = entry.map_err(map_walkdir_error)?;
        if !entry.file_type().is_file() {
            continue;
        }
        if !is_conflicted_copy(entry.path()) {
            continue;
        }
        conflicts.push(candidate_for_path(&repo, entry.path())?.into_pair());
    }

    conflicts.sort_by(|left, right| {
        right
            .conflicted_modified_at
            .cmp(&left.conflicted_modified_at)
            .then_with(|| left.conflicted_copy_path.cmp(&right.conflicted_copy_path))
    });
    Ok(conflicts)
}

impl ConflictCandidate {
    fn into_pair(self) -> ICloudConflictPair {
        ICloudConflictPair {
            conflict_id: self.relative_path.clone(),
            original_path: self.original_relative_path,
            conflicted_copy_path: self.relative_path,
            original_modified_at: self.original_modified_at,
            conflicted_modified_at: self.conflicted_modified_at,
            status: ICloudConflictStatus::NeedsReview,
            uncertainty_reason: self.uncertainty_reason,
        }
    }
}

fn candidate_for_path(repo: &Path, conflicted_path: &Path) -> CoreResult<ConflictCandidate> {
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

fn reject_placeholder_path(path: &Path) -> CoreResult<()> {
    if path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .to_ascii_lowercase()
            .ends_with(".icloud")
    }) {
        Err(CoreError::icloud_placeholder("icloud placeholder"))
    } else {
        Ok(())
    }
}

fn relative_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::io(error.to_string()))
        .map(|relative| relative.to_string_lossy().replace('\\', "/"))
}

fn modified_at(path: &Path) -> CoreResult<i64> {
    let metadata = fs::metadata(path).map_err(map_io_error)?;
    let modified = metadata.modified().map_err(map_io_error)?;
    let duration = modified
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::io(error.to_string()))?;
    Ok(duration.as_secs() as i64)
}

fn map_walkdir_error(error: walkdir::Error) -> CoreError {
    if let Some(source) = error.io_error() {
        map_io_error(std::io::Error::new(source.kind(), source.to_string()))
    } else {
        CoreError::io(error.to_string())
    }
}

fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("io error"),
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
