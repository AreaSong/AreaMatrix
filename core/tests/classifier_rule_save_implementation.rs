use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, predict_category, save_classifier_rule, ClassifierRule, ClassifyReason, CoreError,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde::Deserialize;

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
struct RuleSaveSnapshot {
    classifier_yaml: String,
    metadata_entries: Vec<PathBuf>,
    user_visible_files: BTreeMap<PathBuf, Vec<u8>>,
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

fn classifier_path(repo: &Path) -> PathBuf {
    repo.join(".areamatrix/classifier.yaml")
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

fn keyword_rule() -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec!["clienta".to_owned(), "合同x".to_owned()],
        extensions: Vec::new(),
        priority: 25,
    }
}

fn snapshot(repo: &Path) -> RuleSaveSnapshot {
    RuleSaveSnapshot {
        classifier_yaml: fs::read_to_string(classifier_path(repo)).expect("read classifier yaml"),
        metadata_entries: metadata_entries(repo),
        user_visible_files: user_visible_files(repo),
    }
}

fn metadata_entries(repo: &Path) -> Vec<PathBuf> {
    let metadata = repo.join(".areamatrix");
    let mut entries = Vec::new();
    collect_paths(&metadata, &metadata, &mut entries);
    entries.sort();
    entries
}

fn user_visible_files(repo: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut files = BTreeMap::new();
    collect_user_visible_files(repo, repo, &mut files);
    files
}

fn collect_paths(root: &Path, current: &Path, entries: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let path = entry.expect("read directory entry").path();
        let relative = path
            .strip_prefix(root)
            .expect("path remains under root")
            .to_path_buf();
        entries.push(relative);
        if path.is_dir() {
            collect_paths(root, &path, entries);
        }
    }
}

fn collect_user_visible_files(root: &Path, current: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let path = entry.expect("read directory entry").path();
        if path.file_name().and_then(|name| name.to_str()) == Some(".areamatrix") {
            continue;
        }
        if path.is_dir() {
            collect_user_visible_files(root, &path, files);
            continue;
        }
        let relative = path
            .strip_prefix(root)
            .expect("path remains under repo")
            .to_path_buf();
        files.insert(relative, fs::read(&path).expect("read user-visible file"));
    }
}

#[test]
fn classifier_rule_save_implementation_appends_keywords_and_affects_future_classification_only() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before = snapshot(repo.path());

    let saved = save_classifier_rule(path_string(repo.path()), keyword_rule()).expect("save rule");

    assert_eq!(saved, keyword_rule());
    let config = read_classifier(repo.path());
    let finance = category(&config, "finance");
    assert!(finance.keywords.iter().any(|keyword| keyword == "clienta"));
    assert!(finance.keywords.iter().any(|keyword| keyword == "合同x"));
    assert_eq!(finance.priority, 25);

    let predicted = predict_category(path_string(repo.path()), "clienta-note.txt".to_owned())
        .expect("new keyword participates in future classification");
    assert_eq!(predicted.category, "finance");
    assert_eq!(predicted.reason, ClassifyReason::Keyword);
    assert_eq!(user_visible_files(repo.path()), before.user_visible_files);
    assert!(repo.path().join(".areamatrix/index.db").exists());
}

#[test]
fn classifier_rule_save_implementation_rejects_duplicate_rule_without_writing() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());
    let duplicate = ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec!["invoice".to_owned()],
        extensions: Vec::new(),
        priority: 10,
    };

    let result = save_classifier_rule(path_string(repo.path()), duplicate);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_rule_save_implementation_rejects_extension_only_rule_until_preview() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());
    let broad = ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: Vec::new(),
        extensions: vec!["pdf".to_owned()],
        priority: 0,
    };

    let result = save_classifier_rule(path_string(repo.path()), broad);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_rule_save_implementation_rejects_invalid_classifier_schema_without_writing() {
    let repo = initialized_repo();
    fs::write(
        classifier_path(repo.path()),
        "version: 1\ndefault: missing\ncategories:\n  - slug: finance\n",
    )
    .expect("write invalid classifier config");
    let before = snapshot(repo.path());

    let result = save_classifier_rule(path_string(repo.path()), keyword_rule());

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_rule_save_implementation_rejects_uninitialized_repo_without_creating_metadata() {
    let repo = tempfile::tempdir().expect("create plain directory");
    let result = save_classifier_rule(path_string(repo.path()), keyword_rule());

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert!(!repo.path().join(".areamatrix").exists());
}
