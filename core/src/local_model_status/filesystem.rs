//! Local model filesystem inspection helpers.

use std::{fs, io, path::Path};

use crate::{CoreError, CoreResult};

pub(super) struct FolderInspection {
    pub(super) exists: bool,
    pub(super) readable: bool,
    pub(super) openable: bool,
    pub(super) unavailable_reason: Option<String>,
}

pub(super) fn inspect_folder(path: &Path) -> CoreResult<FolderInspection> {
    if !path_exists(path)? {
        return Ok(FolderInspection {
            exists: false,
            readable: false,
            openable: false,
            unavailable_reason: Some("Model folder does not exist".to_owned()),
        });
    }
    let metadata = metadata(path)?;
    if !metadata.is_dir() {
        return Ok(FolderInspection {
            exists: true,
            readable: false,
            openable: false,
            unavailable_reason: Some("Model location is not a directory".to_owned()),
        });
    }
    if !metadata_allows_read(&metadata) {
        return Ok(FolderInspection {
            exists: true,
            readable: false,
            openable: false,
            unavailable_reason: Some("Model folder is not readable".to_owned()),
        });
    }
    Ok(FolderInspection {
        exists: true,
        readable: true,
        openable: true,
        unavailable_reason: None,
    })
}

pub(super) fn read_text_if_exists(path: &Path) -> CoreResult<Option<String>> {
    if path_exists(path)? {
        fs::read_to_string(path)
            .map(Some)
            .map_err(map_model_io_error)
    } else {
        Ok(None)
    }
}

pub(super) fn directory_size(path: &Path) -> CoreResult<i64> {
    let mut total = 0_i64;
    for entry in fs::read_dir(path).map_err(map_model_io_error)? {
        let entry = entry.map_err(map_model_io_error)?;
        let file_type = entry.file_type().map_err(map_model_io_error)?;
        if file_type.is_dir() {
            total = total
                .checked_add(directory_size(&entry.path())?)
                .ok_or_else(|| CoreError::io("local model size exceeds supported range"))?;
        } else if file_type.is_file() {
            let metadata = entry.metadata().map_err(map_model_io_error)?;
            let length = i64::try_from(metadata.len())
                .map_err(|_| CoreError::io("local model size exceeds supported range"))?;
            total = total
                .checked_add(length)
                .ok_or_else(|| CoreError::io("local model size exceeds supported range"))?;
        }
    }
    Ok(total)
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(map_model_io_error)
}

fn metadata(path: &Path) -> CoreResult<fs::Metadata> {
    path.metadata().map_err(map_model_io_error)
}

fn map_model_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::config("local model path is invalid"),
        _ => CoreError::io("local model metadata inspection failed"),
    }
}

#[cfg(unix)]
fn metadata_allows_read(metadata: &fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o444 != 0
}

#[cfg(not(unix))]
fn metadata_allows_read(metadata: &fs::Metadata) -> bool {
    !metadata.permissions().readonly()
}
