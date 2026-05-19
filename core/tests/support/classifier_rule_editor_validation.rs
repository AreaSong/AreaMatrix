use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest, ClassifierRuleUpdate,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub(crate) struct ClassifierConfig {
    pub(crate) default: String,
    pub(crate) categories: Vec<CategoryConfig>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CategoryConfig {
    pub(crate) slug: String,
    #[serde(default)]
    pub(crate) display_name: BTreeMap<String, String>,
    #[serde(default)]
    pub(crate) description: BTreeMap<String, String>,
    #[serde(default)]
    pub(crate) extensions: Vec<String>,
    #[serde(default)]
    pub(crate) keywords: Vec<String>,
    #[serde(default)]
    pub(crate) priority: i64,
    pub(crate) naming_template: Option<String>,
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct ValidationSnapshot {
    pub(crate) classifier_yaml: String,
    pub(crate) file_rows: Vec<(i64, String, String, String)>,
    pub(crate) user_visible_files: BTreeMap<PathBuf, Vec<u8>>,
    pub(crate) generated_paths: Vec<PathBuf>,
    pub(crate) change_log_count: i64,
    pub(crate) notes_count: i64,
    pub(crate) tags_count: i64,
    pub(crate) undo_count: i64,
    pub(crate) saved_search_count: i64,
}

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
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

fn classifier_path(repo: &Path) -> PathBuf {
    repo.join(".areamatrix/classifier.yaml")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn update_request() -> ClassifierRuleUpdate {
    ClassifierRuleUpdate {
        rule_id: "finance".to_owned(),
        slug: "contracts".to_owned(),
        display_name: "Contracts".to_owned(),
        description: "Signed client contracts".to_owned(),
        extensions: vec!["pdf".to_owned(), "docx".to_owned()],
        keywords: vec!["agreement".to_owned(), "合同".to_owned()],
        priority: 30,
        naming_template: Some("{stem}-{date}".to_owned()),
        preview_confirmed: true,
    }
}

pub(crate) fn create_request() -> ClassifierRuleCreateRequest {
    ClassifierRuleCreateRequest {
        slug: "tax".to_owned(),
        display_name: "Tax".to_owned(),
        description: "Tax documents".to_owned(),
        extensions: vec!["pdf".to_owned()],
        keywords: vec!["tax".to_owned()],
        priority: 20,
        naming_template: Some("{stem}".to_owned()),
    }
}

pub(crate) fn delete_request(rule_id: &str) -> ClassifierRuleDeleteRequest {
    ClassifierRuleDeleteRequest {
        rule_id: rule_id.to_owned(),
        replacement_category: Some("inbox".to_owned()),
        preview_confirmed: true,
    }
}

pub(crate) fn insert_active_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"classifier rule editor validation fixture")
        .expect("write fixture file");

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path includes filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 41,
                ?4, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

pub(crate) fn read_classifier(repo: &Path) -> ClassifierConfig {
    let yaml = fs::read_to_string(classifier_path(repo)).expect("read classifier config");
    serde_yaml::from_str(&yaml).expect("parse classifier config")
}

pub(crate) fn category<'a>(config: &'a ClassifierConfig, slug: &str) -> &'a CategoryConfig {
    config
        .categories
        .iter()
        .find(|category| category.slug == slug)
        .expect("classifier category exists")
}

pub(crate) fn snapshot(repo: &Path) -> ValidationSnapshot {
    ValidationSnapshot {
        classifier_yaml: fs::read_to_string(classifier_path(repo)).expect("read classifier yaml"),
        file_rows: file_rows(repo),
        user_visible_files: user_visible_files(repo),
        generated_paths: generated_paths(repo),
        change_log_count: table_count(repo, "change_log"),
        notes_count: table_count(repo, "notes"),
        tags_count: table_count(repo, "tags"),
        undo_count: table_count(repo, "undo_actions"),
        saved_search_count: table_count(repo, "saved_searches"),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count metadata rows")
}

fn user_visible_files(repo: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut files = BTreeMap::new();
    collect_user_visible_files(repo, repo, &mut files);
    files
}

fn collect_user_visible_files(root: &Path, current: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let path = entry.expect("read repository entry").path();
        if path.file_name().and_then(|name| name.to_str()) == Some(".areamatrix") {
            continue;
        }
        if path.is_dir() {
            collect_user_visible_files(root, &path, files);
            continue;
        }
        let relative = path
            .strip_prefix(root)
            .expect("path remains under repository root")
            .to_path_buf();
        files.insert(relative, fs::read(&path).expect("read user-visible file"));
    }
}

fn generated_paths(repo: &Path) -> Vec<PathBuf> {
    let generated = repo.join(".areamatrix/generated");
    if !generated.is_dir() {
        return Vec::new();
    }
    let mut paths = Vec::new();
    collect_paths(&generated, &generated, &mut paths);
    paths.sort();
    paths
}

fn collect_paths(root: &Path, current: &Path, paths: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(current).expect("read generated directory") {
        let path = entry.expect("read generated entry").path();
        let relative = path
            .strip_prefix(root)
            .expect("path remains under generated root")
            .to_path_buf();
        paths.push(relative);
        if path.is_dir() {
            collect_paths(root, &path, paths);
        }
    }
}

pub(crate) fn assert_no_classifier_temp_files(repo: &Path) {
    let temp_files: Vec<_> = fs::read_dir(repo.join(".areamatrix"))
        .expect("read metadata directory")
        .map(|entry| entry.expect("read metadata entry").file_name())
        .filter(|name| {
            name.to_str().is_some_and(|value| {
                value.starts_with(".classifier.yaml.") && value.ends_with(".tmp")
            })
        })
        .collect();
    assert_eq!(temp_files, Vec::<std::ffi::OsString>::new());
}

pub(crate) fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}
