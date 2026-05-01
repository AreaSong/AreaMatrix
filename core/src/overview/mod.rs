//! Minimal generated overview support for empty repositories.

use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::Path,
};

use crate::{CoreError, CoreResult};

const BEGIN_TAG: &str =
    "<!-- AREAMATRIX:BEGIN auto-generated content; do NOT edit between markers -->";
const END_TAG: &str = "<!-- AREAMATRIX:END -->";

pub(crate) fn write_generated_root(generated_dir: &Path, locale: &str) -> CoreResult<()> {
    fs::create_dir_all(generated_dir).map_err(map_io_error)?;
    write_new_file(&generated_dir.join("root.md"), &root_overview(locale))
}

pub(crate) fn write_root_areamatrix_file(repo_path: &Path, locale: &str) -> CoreResult<()> {
    write_new_file(&repo_path.join("AREAMATRIX.md"), &root_overview(locale))
}

fn root_overview(locale: &str) -> String {
    let (
        title,
        description,
        summary_label,
        node_label,
        file_count,
        size_label,
        latest_label,
        empty_files,
    ) = if locale == "zh-Hans" {
        (
            "AreaMatrix 资料库",
            "自动维护，请勿删除 .areamatrix/ 目录。",
            "总览",
            "节点",
            "文件数",
            "大小",
            "最近导入",
            "0 个文件",
        )
    } else {
        (
            "AreaMatrix Repository",
            "Auto-managed. Do not delete the .areamatrix/ directory.",
            "Overview",
            "Node",
            "Files",
            "Size",
            "Latest import",
            "0 files",
        )
    };

    format!(
        "# {title}\n\n> {description}\n\n{BEGIN_TAG}\n\n\
         **{summary_label}**: {empty_files} · 0 B · 0 {node_label}\n\n\
         | {node_label} | {file_count} | {size_label} | {latest_label} |\n\
         |---|---|---|---|\n\n{END_TAG}\n"
    )
}

fn write_new_file(path: &Path, content: &str) -> CoreResult<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(map_io_error)?;
    match file.write_all(content.as_bytes()) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _ = fs::remove_file(path);
            Err(map_io_error(error))
        }
    }
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::AlreadyExists => CoreError::Config,
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}
