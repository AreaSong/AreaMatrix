use std::{
    fs::File,
    path::{Component, Path},
};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_FILENAME_CHARS: usize = 255;
const FORBIDDEN_FILENAME_CHARS: &[char] = &['/', '\\', ':', '*', '?', '"', '<', '>', '|'];

pub(super) fn source_file(path: &Path) -> CoreResult<()> {
    if path.as_os_str().is_empty() || is_inside_area_matrix(path) {
        return Err(CoreError::invalid_path(path.to_string_lossy()));
    }
    if has_icloud_placeholder_marker(path) {
        return Err(CoreError::icloud_placeholder(path.to_string_lossy()));
    }

    let metadata = path
        .metadata()
        .map_err(|error| map_path_error(path, error))?;
    if !metadata.is_file() {
        return Err(CoreError::invalid_path(path.to_string_lossy()));
    }
    File::open(path)
        .map(|_| ())
        .map_err(|error| map_path_error(path, error))
}

pub(super) fn filename(name: &str) -> CoreResult<()> {
    if name.is_empty() || name == "." || name == ".." {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if name.chars().count() > MAX_FILENAME_CHARS {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if name
        .chars()
        .any(|character| character.is_control() || FORBIDDEN_FILENAME_CHARS.contains(&character))
    {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(())
}

pub(super) fn category_slug(category: &str) -> CoreResult<()> {
    filename(category)?;
    if category.starts_with('.') || category.contains('/') || category.contains('\\') {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(())
}

pub(super) fn relative_directory(directory: &str) -> CoreResult<()> {
    if directory.trim().is_empty() || directory.starts_with('~') {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let path = Path::new(directory);
    if path.is_absolute() {
        return Err(CoreError::invalid_path("invalid path"));
    }

    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let Some(part) = part.to_str() else {
                    return Err(CoreError::invalid_path("invalid path"));
                };
                if part == AREA_MATRIX_DIR {
                    return Err(CoreError::invalid_path("invalid path"));
                }
                filename(part)?;
            }
            _ => return Err(CoreError::invalid_path("invalid path")),
        }
    }

    Ok(())
}

pub(super) fn top_level_category(directory: &str) -> CoreResult<String> {
    let first_component = Path::new(directory)
        .components()
        .find_map(|component| match component {
            Component::Normal(part) => part.to_str().map(str::to_owned),
            _ => None,
        })
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    category_slug(&first_component)?;
    Ok(first_component)
}

fn is_inside_area_matrix(path: &Path) -> bool {
    path.components()
        .any(|component| component.as_os_str() == AREA_MATRIX_DIR)
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

fn map_path_error(path: &Path, error: std::io::Error) -> CoreError {
    let context = path.to_string_lossy();
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::file_not_found(context),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied(context),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path(context),
        _ => CoreError::io("io error"),
    }
}
