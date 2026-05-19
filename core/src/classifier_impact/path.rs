use std::{
    ffi::OsStr,
    path::{Component, Path, PathBuf},
};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(super) fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative)?;
    Ok(repo.join(relative))
}

pub(super) fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|_| CoreError::db("classifier impact metadata path is invalid"))
        .map(|relative| relative.to_string_lossy().into_owned())
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() || path.as_os_str().is_empty() {
        return Err(CoreError::db("classifier impact metadata path is invalid"));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::db("classifier impact metadata path is invalid"));
        };
        if part == OsStr::new(AREA_MATRIX_DIR) {
            return Err(CoreError::db("classifier impact metadata path is invalid"));
        }
    }
    Ok(())
}
