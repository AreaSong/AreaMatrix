use std::{fs, path::Path};

use area_matrix_core::{
    semantic_search, AiConfig, AiFeatureConfig, AiFeatureKind, AiProviderPreference,
};
use rusqlite::params;

use crate::semantic_search_common::{default_filter, first_page, open_db, path_string};

pub fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

pub fn table_count(repo: &Path, table: &str) -> i64 {
    if !table_exists(repo, table) {
        return 0;
    }
    open_db(repo)
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .expect("count table rows")
}

pub fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(true),
        )
        .unwrap_or(false)
}

pub fn ai_config(
    repo_path: String,
    ai_enabled: bool,
    local_enabled: bool,
    remote_allowed: bool,
    provider_preference: AiProviderPreference,
    feature_enabled: bool,
    feature_remote_allowed: bool,
) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled,
        provider_preference,
        local_ai_enabled: local_enabled,
        remote_ai_allowed: remote_allowed,
        privacy_gate_enabled: true,
        privacy_policy_ref: None,
        feature_toggles: vec![
            AiFeatureConfig {
                feature: AiFeatureKind::ClassificationSuggestions,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoSummaries,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoTags,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::SemanticSearch,
                enabled: feature_enabled,
                allow_remote: feature_remote_allowed,
            },
        ],
    }
}

pub fn update_ai_config(repo: &Path, config: AiConfig) {
    area_matrix_core::update_ai_config(path_string(repo), config).expect("update AI config");
}

pub fn assert_no_secret_material(value: &str) {
    for fragment in [
        "sk-secret",
        "api_key",
        "bearer",
        "token=",
        "secure-storage:",
        "keychain:",
    ] {
        assert!(
            !value.to_ascii_lowercase().contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

pub fn combined_log_text(repo: &Path) -> String {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(provider, ''), COALESCE(model, ''), COALESCE(result_summary, ''),
                    COALESCE(error_code, ''), sent_fields_json
               FROM ai_call_log
              ORDER BY id",
        )
        .expect("prepare AI log text query");
    statement
        .query_map([], |row| {
            Ok(format!(
                "{} {} {} {} {}",
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .expect("query AI log text")
        .map(|row| row.expect("read AI log text"))
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn active_file_path(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT path FROM files WHERE id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read active file path")
}

pub fn install_abort_trigger(repo: &Path, name: &str, timing: &str) {
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER {name}
             {timing}
             BEGIN
               SELECT RAISE(ABORT, 'forced semantic search failure');
             END;"
        ))
        .expect("install abort trigger");
}

pub fn ensure_ai_call_log_table(repo: &Path) {
    semantic_search(
        path_string(repo),
        "warmup".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("create AI call log table through normal fallback");
    open_db(repo)
        .execute("DELETE FROM ai_call_log", [])
        .expect("clear warmup AI call log row");
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repo")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

#[cfg(unix)]
pub struct ReadOnlyGuard {
    path: std::path::PathBuf,
    original_mode: u32,
}

#[cfg(unix)]
impl ReadOnlyGuard {
    pub fn new(path: &Path) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let metadata = fs::metadata(path).expect("read file metadata");
        let original_mode = metadata.permissions().mode();
        let mut permissions = metadata.permissions();
        permissions.set_mode(0o000);
        fs::set_permissions(path, permissions).expect("make file unreadable");
        Self {
            path: path.to_path_buf(),
            original_mode,
        }
    }
}

#[cfg(unix)]
impl Drop for ReadOnlyGuard {
    fn drop(&mut self) {
        use std::os::unix::fs::PermissionsExt;

        let mut permissions = fs::metadata(&self.path)
            .expect("read file metadata")
            .permissions();
        permissions.set_mode(self.original_mode);
        fs::set_permissions(&self.path, permissions).expect("restore file permissions");
    }
}

#[cfg(not(unix))]
pub struct ReadOnlyGuard;

#[cfg(not(unix))]
impl ReadOnlyGuard {
    pub fn new(_path: &Path) -> Self {
        Self
    }
}
