use std::{fs::Metadata, path::Path};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

pub(super) fn ensure_storage_writable(repo_path: &Path) -> CoreResult<()> {
    ensure_writable_path(&repo_path.join(AREA_MATRIX_DIR))?;
    ensure_writable_path(&repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE))
}

fn ensure_writable_path(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_metadata_error)?;
    if metadata_allows_write(&metadata) {
        Ok(())
    } else {
        Err(CoreError::permission_denied("permission denied"))
    }
}

fn map_metadata_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::db("AI call log metadata unavailable"),
    }
}

#[cfg(unix)]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o222 != 0
}

#[cfg(not(unix))]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    !metadata.permissions().readonly()
}

pub(super) fn default_scope(feature: &str) -> Option<&'static str> {
    match feature {
        "classification" => Some("Classification"),
        "summary" => Some("Summary"),
        "tags" => Some("Tags"),
        "semantic_search" => Some("Semantic search"),
        "provider_test" => Some("Provider verification"),
        _ => None,
    }
}

pub(super) fn bool_to_db(value: bool) -> i64 {
    if value {
        1
    } else {
        0
    }
}

pub(super) fn db_to_bool(value: i64) -> CoreResult<bool> {
    match value {
        0 => Ok(false),
        1 => Ok(true),
        _ => Err(CoreError::db("AI call log boolean value is invalid")),
    }
}

pub(super) fn optional_column_definitions() -> [(&'static str, &'static str); 6] {
    [
        ("batch_id", "batch_id TEXT"),
        ("scope", "scope TEXT"),
        ("duration_ms", "duration_ms INTEGER"),
        (
            "privacy_rules_checked",
            "privacy_rules_checked INTEGER NOT NULL DEFAULT 0 \
             CHECK (privacy_rules_checked IN (0, 1))",
        ),
        ("privacy_rule_name", "privacy_rule_name TEXT"),
        ("matched_field_type", "matched_field_type TEXT"),
    ]
}

pub(super) fn map_open_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. }
        | CoreError::InvalidPath { .. }
        | CoreError::Config { .. }
        | CoreError::Io { .. } => CoreError::db("AI call log metadata unavailable"),
        other => other,
    }
}
