//! Minimal repository tree JSON for initialized empty repositories.

use std::{
    fs, io,
    path::{Path, PathBuf},
};

use serde_json::json;

use crate::{db, CoreError, CoreResult};

pub(crate) fn list_tree_json(repo_path: String, _locale: String) -> CoreResult<String> {
    let repo = PathBuf::from(repo_path);
    db::ensure_initialized(&repo)?;
    let children = top_level_directory_nodes(&repo)?;
    Ok(json!({ "children": children }).to_string())
}

fn top_level_directory_nodes(repo: &Path) -> CoreResult<Vec<serde_json::Value>> {
    let mut nodes = Vec::new();
    for entry in fs::read_dir(repo).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !is_initial_tree_entry(&name, &entry.path())? {
            continue;
        }
        nodes.push(json!({
            "name": name,
            "path": name,
            "children": [],
        }));
    }
    nodes.sort_by(|left, right| {
        left["name"]
            .as_str()
            .unwrap_or_default()
            .cmp(right["name"].as_str().unwrap_or_default())
    });
    Ok(nodes)
}

fn is_initial_tree_entry(name: &str, path: &Path) -> CoreResult<bool> {
    if name.starts_with('.') || name == "AREAMATRIX.md" {
        return Ok(false);
    }
    path.metadata()
        .map(|metadata| metadata.is_dir())
        .map_err(map_io_error)
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}
