use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, update_ai_config, AiConfig, AiFeatureConfig, AiFeatureKind, AiProviderPreference,
    OverviewOutput, RepoInitMode, RepoInitOptions, SearchFilter, SearchPagination, SearchScope,
    SearchTagMatchMode, SemanticIndexScope, SemanticSearchRoute,
};
use rusqlite::{params, Connection};

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

pub fn default_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: Vec::new(),
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: None,
        include_deleted: Some(false),
    }
}

pub fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

pub fn semantic_scope() -> SemanticIndexScope {
    SemanticIndexScope {
        filter: default_filter(),
        route: Some(SemanticSearchRoute::Local),
        privacy_policy_ref: None,
        confirmed: true,
    }
}

pub fn enable_local_semantic_search(repo: &Path) {
    let repo_path = path_string(repo);
    update_ai_config(repo_path.clone(), ai_config(repo_path, true, None))
        .expect("enable semantic search");
}

pub fn insert_file(repo: &Path, relative_path: &str, category: &str, note: Option<&str>) -> i64 {
    insert_file_with_body(
        repo,
        relative_path,
        category,
        note,
        "semantic search fixture",
    )
}

pub fn insert_file_with_body(
    repo: &Path,
    relative_path: &str,
    category: &str,
    note: Option<&str>,
    body: &str,
) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create parent directory");
    fs::write(&file_path, body).expect("write file fixture");
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 23,
                ?4, 'copied', 'imported', NULL,
                100, 110, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert active file row");
    let file_id = connection.last_insert_rowid();
    if let Some(content) = note {
        connection
            .execute(
                "INSERT INTO notes (file_id, content_md, updated_at) VALUES (?1, ?2, 120)",
                params![file_id, content],
            )
            .expect("insert note row");
    }
    file_id
}

pub fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 130)",
            params![file_id, tag],
        )
        .expect("insert tag row");
}

pub fn save_privacy_rules(repo: &Path, rules_json: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO repo_config (key, value, updated_at)
             VALUES ('ai_privacy_rules', ?1, 140)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            params![rules_json],
        )
        .expect("save privacy rules");
}

pub fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub fn ai_log_row(repo: &Path, id: i64) -> (String, Option<String>, String, Option<String>) {
    open_db(repo)
        .query_row(
            "SELECT status, route, sent_fields_json, error_code FROM ai_call_log WHERE id = ?1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read AI call log row")
}

pub fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .ok()
}

fn ai_config(repo_path: String, feature_enabled: bool, privacy_ref: Option<String>) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: AiProviderPreference::LocalFirst,
        local_ai_enabled: true,
        remote_ai_allowed: false,
        privacy_gate_enabled: true,
        privacy_policy_ref: privacy_ref,
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
                allow_remote: false,
            },
        ],
    }
}
