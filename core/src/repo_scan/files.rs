use std::{
    fs::File,
    io::{self, Read},
    path::Path,
};

use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::{db::FileIndexInput, CoreError, CoreResult};

use super::{
    ignore::{has_icloud_placeholder_marker, IgnoreMatcher},
    types::{AdoptFile, ScanPlan},
};

pub(super) fn collect_scan_files(
    repo_path: &Path,
    resume_after: Option<&str>,
) -> CoreResult<ScanPlan> {
    let matcher = IgnoreMatcher::load(repo_path)?;
    let mut files = Vec::new();
    let mut skipped = 0;

    for entry in WalkDir::new(repo_path)
        .follow_links(false)
        .same_file_system(true)
        .into_iter()
        .filter_entry(|entry| should_descend(repo_path, entry.path(), &matcher))
    {
        let entry = entry.map_err(map_walkdir_error)?;
        let path = entry.path();
        if path == repo_path || entry.file_type().is_dir() {
            continue;
        }

        let relative_path = relative_repo_path(repo_path, path)?;
        if has_icloud_placeholder_marker(&relative_path) {
            if should_process_after_resume(&relative_path, resume_after) {
                skipped += 1;
            }
            continue;
        }
        if matcher.is_ignored(&relative_path, entry.file_type().is_dir()) {
            if should_process_after_resume(&relative_path, resume_after) {
                skipped += 1;
            }
            continue;
        }
        if !entry.file_type().is_file() {
            if should_process_after_resume(&relative_path, resume_after) {
                skipped += 1;
            }
            continue;
        }
        if !should_process_after_resume(&relative_path, resume_after) {
            continue;
        }

        files.push(AdoptFile {
            path: path.to_path_buf(),
            relative_path,
        });
    }

    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(ScanPlan { files, skipped })
}

pub(super) fn index_input_for_file(
    path: &Path,
    relative_path: String,
) -> CoreResult<FileIndexInput> {
    let metadata = path.metadata().map_err(map_io_error)?;
    let current_name = file_name(path)?;
    Ok(FileIndexInput {
        category: category_for_relative_path(&relative_path),
        path: relative_path,
        original_name: current_name.clone(),
        current_name,
        size_bytes: metadata.len() as i64,
        hash_sha256: sha256_file(path)?,
    })
}

pub(super) fn map_io_error(error: io::Error) -> CoreError {
    map_io_kind(error.kind())
}

fn should_process_after_resume(relative_path: &str, resume_after: Option<&str>) -> bool {
    match resume_after {
        Some(last_path) if !last_path.is_empty() => relative_path > last_path,
        _ => true,
    }
}

fn should_descend(repo_path: &Path, path: &Path, matcher: &IgnoreMatcher) -> bool {
    if path == repo_path {
        return true;
    }
    if !path.is_dir() {
        return true;
    }
    match relative_repo_path(repo_path, path) {
        Ok(relative_path) => !matcher.is_ignored(&relative_path, true),
        Err(_) => false,
    }
}

fn relative_repo_path(repo_path: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo_path)
        .map_err(|error| CoreError::invalid_path(error.to_string()))?;
    Ok(relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/"))
}

fn category_for_relative_path(relative_path: &str) -> String {
    match relative_path.split_once('/') {
        Some((top_level, _)) if !top_level.is_empty() => top_level.to_owned(),
        _ => "__root__".to_owned(),
    }
}

fn file_name(path: &Path) -> CoreResult<String> {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .filter(|name| !name.is_empty())
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

fn sha256_file(path: &Path) -> CoreResult<String> {
    let mut file = File::open(path).map_err(map_io_error)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 8192];
    loop {
        let bytes_read = file.read(&mut buffer).map_err(map_io_error)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn map_walkdir_error(error: walkdir::Error) -> CoreError {
    error
        .io_error()
        .map(|error| map_io_kind(error.kind()))
        .unwrap_or_else(|| CoreError::io("io error"))
}

fn map_io_kind(kind: io::ErrorKind) -> CoreError {
    match kind {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}
