use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, ClassifierImpactPreviewMode, ClassifierImpactPreviewRequest, ClassifierRule,
    OverviewOutput, RepoInitMode, RepoInitOptions, RuleImpactStatus,
};
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct ImpactSnapshot {
    classifier_yaml: String,
    file_rows: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    notes_count: i64,
    tags_count: i64,
    undo_count: i64,
    generated_paths: Vec<String>,
    user_visible_paths: Vec<String>,
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

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn rule() -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec!["clientx".to_owned(), "合同x".to_owned()],
        extensions: vec!["csv".to_owned()],
        priority: 20,
        preview_confirmed: false,
    }
}

pub(crate) fn write_classifier_with_finance_rules(repo: &Path) {
    fs::write(
        repo.join(".areamatrix/classifier.yaml"),
        r#"version: 1
default: inbox
categories:
  - slug: docs
    display_name: { zh-Hans: 文档, en: Documents }
    extensions: [txt]
  - slug: finance
    display_name: { zh-Hans: 财务, en: Finance }
    extensions: [csv]
    keywords: [clientx, 合同x]
    priority: 10
  - slug: inbox
    display_name: { zh-Hans: 未分类, en: Inbox }
"#,
    )
    .expect("write classifier fixture");
}

pub(crate) fn write_classifier_with_priority_overlap(repo: &Path) {
    fs::write(
        repo.join(".areamatrix/classifier.yaml"),
        r#"version: 1
default: inbox
categories:
  - slug: docs
    display_name: { zh-Hans: 文档, en: Documents }
    keywords: [clientx]
    priority: 30
  - slug: finance
    display_name: { zh-Hans: 财务, en: Finance }
    keywords: []
    priority: 10
  - slug: inbox
    display_name: { zh-Hans: 未分类, en: Inbox }
"#,
    )
    .expect("write classifier priority fixture");
}

pub(crate) fn request() -> ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewRequest {
        mode: ClassifierImpactPreviewMode::RuleDraft,
        rule: rule(),
        move_files: true,
        replacement_category: None,
    }
}

pub(crate) fn request_without_move() -> ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewRequest {
        move_files: false,
        ..request()
    }
}

pub(crate) fn remove_keyword_request(keyword: &str) -> ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewRequest {
        mode: ClassifierImpactPreviewMode::RemoveKeyword,
        rule: ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec![keyword.to_owned()],
            extensions: Vec::new(),
            priority: 0,
            preview_confirmed: false,
        },
        move_files: true,
        replacement_category: None,
    }
}

pub(crate) fn remove_extension_request(extension: &str) -> ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewRequest {
        mode: ClassifierImpactPreviewMode::RemoveExtension,
        rule: ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: Vec::new(),
            extensions: vec![extension.to_owned()],
            priority: 0,
            preview_confirmed: false,
        },
        move_files: true,
        replacement_category: None,
    }
}

pub(crate) fn remove_category_request(replacement: Option<&str>) -> ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewRequest {
        mode: ClassifierImpactPreviewMode::RemoveCategory,
        rule: ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: Vec::new(),
            extensions: Vec::new(),
            priority: 0,
            preview_confirmed: false,
        },
        move_files: true,
        replacement_category: replacement.map(str::to_owned),
    }
}

pub(crate) fn insert_repo_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"classifier impact fixture").expect("write fixture file");
    insert_file_row(repo, relative_path, relative_path, category, "copied", None)
}

pub(crate) fn insert_indexed_file(repo: &Path, source_path: &Path, category: &str) -> i64 {
    fs::write(source_path, b"classifier impact indexed fixture").expect("write indexed source");
    let source = path_string(source_path);
    insert_file_row(repo, &source, &source, category, "indexed", Some(&source))
}

pub(crate) fn insert_file_row(
    repo: &Path,
    path: &str,
    name_path: &str,
    category: &str,
    storage_mode: &str,
    source_path: Option<&str>,
) -> i64 {
    let current_name = name_path
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
                ?1, ?2, ?2, ?3, 26,
                ?4, ?5, 'imported', ?6,
                100, 100, 'active'
             )",
            params![
                path,
                current_name,
                category,
                format!("{:064x}", path.len()),
                storage_mode,
                source_path,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

pub(crate) fn snapshot(repo: &Path) -> ImpactSnapshot {
    ImpactSnapshot {
        classifier_yaml: fs::read_to_string(repo.join(".areamatrix/classifier.yaml"))
            .expect("read classifier yaml"),
        file_rows: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        notes_count: table_count(repo, "notes"),
        tags_count: table_count(repo, "tags"),
        undo_count: table_count(repo, "undo_actions"),
        generated_paths: generated_paths(repo),
        user_visible_paths: user_visible_paths(repo),
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

fn generated_paths(repo: &Path) -> Vec<String> {
    let generated = repo.join(".areamatrix/generated");
    let mut paths: Vec<String> = fs::read_dir(generated)
        .expect("read generated directory")
        .map(|entry| {
            entry
                .expect("read generated entry")
                .path()
                .strip_prefix(repo)
                .expect("generated path remains inside repo")
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    paths.sort();
    paths
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path remains inside repo")
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

pub(crate) fn sample_status(
    report: &area_matrix_core::RuleImpactReport,
    file_id: i64,
) -> RuleImpactStatus {
    report
        .samples
        .iter()
        .find(|sample| sample.file_id == file_id)
        .expect("sample exists")
        .status
        .clone()
}

pub(crate) fn sample(
    report: &area_matrix_core::RuleImpactReport,
    file_id: i64,
) -> &area_matrix_core::RuleImpactSample {
    report
        .samples
        .iter()
        .find(|sample| sample.file_id == file_id)
        .expect("sample exists")
}
