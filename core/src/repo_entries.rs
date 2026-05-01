//! Shared repository directory-entry classification.

use std::{fs, io};

/// Returns whether a root-level entry is user content for init/path checks.
///
/// C1-02 can ignore a small allowlist of OS-created metadata files, but hidden
/// user content such as `.env` or `.git` must keep the directory non-empty so it
/// flows through the later C1-03 adopt-existing path.
pub(crate) fn is_user_content_entry(entry: &fs::DirEntry) -> io::Result<bool> {
    let name = entry.file_name();
    let name = name.to_string_lossy();
    if !is_system_hidden_file_name(&name) {
        return Ok(true);
    }

    entry.file_type().map(|file_type| !file_type.is_file())
}

fn is_system_hidden_file_name(name: &str) -> bool {
    matches!(
        name,
        ".DS_Store" | ".localized" | "Icon\r" | "Thumbs.db" | "desktop.ini"
    )
}
