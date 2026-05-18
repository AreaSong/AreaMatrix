use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_files, predict_category, save_classifier_rule, ClassifierRule, ClassifyReason,
    CoreError, CoreResult, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde::Deserialize;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-13-classifier-rule-save.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_RULES_RS: &str = include_str!("../src/classifier_rules.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

#[derive(Debug, Deserialize)]
struct ClassifierConfig {
    categories: Vec<CategoryConfig>,
}

#[derive(Debug, Deserialize)]
struct CategoryConfig {
    slug: String,
    #[serde(default)]
    keywords: Vec<String>,
    #[serde(default)]
    priority: i64,
}

#[derive(Debug, Eq, PartialEq)]
struct ValidationSnapshot {
    classifier_yaml: String,
    file_rows: Vec<(i64, String, String, String)>,
    user_visible_paths: Vec<String>,
    generated_paths: Vec<String>,
    change_log_count: i64,
    notes_count: i64,
    tags_count: i64,
    undo_count: i64,
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn classifier_path(repo: &Path) -> std::path::PathBuf {
    repo.join(".areamatrix/classifier.yaml")
}

fn save_rule(keyword: &str) -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec![keyword.to_owned()],
        extensions: Vec::new(),
        priority: 30,
    }
}

fn insert_active_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"classifier rule validation fixture").expect("write fixture file");
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
                ?1, ?2, ?2, ?3, 34,
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

fn read_classifier(repo: &Path) -> ClassifierConfig {
    let yaml = fs::read_to_string(classifier_path(repo)).expect("read classifier config");
    serde_yaml::from_str(&yaml).expect("parse classifier config")
}

fn category<'a>(config: &'a ClassifierConfig, slug: &str) -> &'a CategoryConfig {
    config
        .categories
        .iter()
        .find(|category| category.slug == slug)
        .expect("classifier category exists")
}

fn snapshot(repo: &Path) -> ValidationSnapshot {
    ValidationSnapshot {
        classifier_yaml: fs::read_to_string(classifier_path(repo)).expect("read classifier yaml"),
        file_rows: file_rows(repo),
        user_visible_paths: user_visible_paths(repo),
        generated_paths: generated_paths(repo),
        change_log_count: table_count(repo, "change_log"),
        notes_count: table_count(repo, "notes"),
        tags_count: table_count(repo, "tags"),
        undo_count: table_count(repo, "undo_actions"),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)))
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

fn default_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: Some(false),
        imported_after: None,
        imported_before: None,
        limit: 50,
        offset: 0,
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn classifier_rule_save_validation_persists_rule_for_future_classification_only() {
    let repo = initialized_repo();
    let existing_file_id = insert_active_file(repo.path(), "docs/clientx-old.txt", "docs");
    let before = snapshot(repo.path());

    let saved =
        save_classifier_rule(path_string(repo.path()), save_rule("clientx")).expect("save rule");

    assert_eq!(saved, save_rule("clientx"));
    let config = read_classifier(repo.path());
    let finance = category(&config, "finance");
    assert!(finance.keywords.iter().any(|keyword| keyword == "clientx"));
    assert_eq!(finance.priority, 30);

    let future = predict_category(path_string(repo.path()), "clientx-new.txt".to_owned())
        .expect("saved keyword participates in future classification");
    assert_eq!(future.category, "finance");
    assert_eq!(future.reason, ClassifyReason::Keyword);

    let files = list_files(path_string(repo.path()), default_filter()).expect("list files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, existing_file_id);
    assert_eq!(files[0].category, "docs");

    let after = snapshot(repo.path());
    assert_ne!(after.classifier_yaml, before.classifier_yaml);
    assert_eq!(after.file_rows, before.file_rows);
    assert_eq!(after.user_visible_paths, before.user_visible_paths);
    assert_eq!(after.generated_paths, before.generated_paths);
    assert_eq!(after.change_log_count, before.change_log_count);
    assert_eq!(after.notes_count, before.notes_count);
    assert_eq!(after.tags_count, before.tags_count);
    assert_eq!(after.undo_count, before.undo_count);
}

#[test]
fn classifier_rule_save_validation_rejects_failures_without_writing_rule_or_side_effects() {
    let repo = initialized_repo();
    insert_active_file(repo.path(), "docs/clientx-old.txt", "docs");
    let before = snapshot(repo.path());

    let cases = [
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: Vec::new(),
            extensions: Vec::new(),
            priority: 0,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec!["invoice".to_owned()],
            extensions: Vec::new(),
            priority: 0,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: Vec::new(),
            extensions: vec!["pdf".to_owned()],
            priority: 0,
        },
        ClassifierRule {
            target_category: "missing".to_owned(),
            keywords: vec!["clientx".to_owned()],
            extensions: Vec::new(),
            priority: 0,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec!["clientx".to_owned()],
            extensions: vec![".pdf".to_owned()],
            priority: 0,
        },
    ];

    for rule in cases {
        assert!(matches!(
            save_classifier_rule(path_string(repo.path()), rule),
            Err(CoreError::Config { .. })
        ));
        assert_eq!(snapshot(repo.path()), before);
    }
}

#[test]
fn classifier_rule_save_validation_locks_core_api_udl_and_rust_alignment() {
    fn assert_signature(_: fn(String, ClassifierRule) -> CoreResult<ClassifierRule>) {}
    assert_signature(save_classifier_rule);

    assert_capability_and_control_map_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_contract_alignment();
    assert_testing_doc_alignment();
}

fn assert_capability_and_control_map_alignment() {
    for fragment in [
        "# C2-13 classifier-rule-save",
        "- S2-17 classifier-save-rule",
        "计划新增：`save_classifier_rule(repo_path, rule) -> ClassifierRule`",
        "关键词、扩展名、目标分类、优先级。",
        "保存后的规则。",
        "原子更新 classifier 配置。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Io`",
        "过宽规则必须 warning 或阻止。",
        "重复规则有结构化反馈。",
        "保存前不应用到历史文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-17 | classifier-save-rule | C2-13 | save rule | classifier config",
        "| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读",
        "分类规则保存和影响预览分离；未预览不得大面积应用。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "ClassifierRule save_classifier_rule(string repo_path, ClassifierRule rule);",
        "dictionary ClassifierRule",
        "string target_category;",
        "sequence<string> keywords;",
        "sequence<string> extensions;",
        "i64 priority;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "C2-13 的分类规则保存入口",
        "`S2-17 classifier-save-rule`",
        "不是 keyword AND extension 复合规则",
        "只允许原子更新 classifier 配置",
        "保存规则只影响未来分类",
        "不实现 C2-14 impact preview、C2-15 rule CRUD",
        "Config",
        "PermissionDenied",
        "Io",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_contract_alignment() {
    for fragment in [
        "pub use classifier_rules::{save_classifier_rule, ClassifierRule};",
        "pub fn save_classifier_rule(repo_path: String, rule: ClassifierRule)",
        "classifier_rules::save_classifier_rule(repo_path, rule)",
    ] {
        assert!(LIB_RS.contains(fragment) || API_RS.contains(fragment));
    }

    for fragment in [
        "Classifier rule payload shared by S2-17, S2-18, and C2-13",
        "does not model path, source-folder, enabled flags, compound AND rules",
        "Saves one C2-13 classifier rule request",
        "existing classifier category in `.areamatrix/classifier.yaml`",
        "reclassify, move, rename, delete, preview impact",
        "write_classifier_config_atomically",
        "reject_duplicate_rule",
        "reject_unpreviewed_broad_rule",
        "CoreError::Config",
        "CoreError::PermissionDenied",
        "CoreError::Io",
    ] {
        assert_contains(CLASSIFIER_RULES_RS, fragment);
    }
}

fn assert_testing_doc_alignment() {
    for fragment in [
        "测试金字塔",
        "`core/classify`",
        "集成测试目录",
        "`core/tests/`，每个文件独立编译",
        "关键测试场景",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
}
