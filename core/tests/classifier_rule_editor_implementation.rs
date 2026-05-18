use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    delete_classifier_rule, init_repo, list_classifier_rules, predict_category,
    update_classifier_rule, ClassifierRuleDeleteRequest, ClassifierRuleUpdate, ClassifyReason,
    CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct ClassifierConfig {
    default: String,
    categories: Vec<CategoryConfig>,
}

#[derive(Debug, Deserialize)]
struct CategoryConfig {
    slug: String,
    #[serde(default)]
    display_name: BTreeMap<String, String>,
    #[serde(default)]
    description: BTreeMap<String, String>,
    #[serde(default)]
    extensions: Vec<String>,
    #[serde(default)]
    keywords: Vec<String>,
    #[serde(default)]
    priority: i64,
    naming_template: Option<String>,
}

#[derive(Debug, Eq, PartialEq)]
struct EditorSnapshot {
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

fn update_request() -> ClassifierRuleUpdate {
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

fn delete_request(rule_id: &str) -> ClassifierRuleDeleteRequest {
    ClassifierRuleDeleteRequest {
        rule_id: rule_id.to_owned(),
        replacement_category: Some("inbox".to_owned()),
        preview_confirmed: true,
    }
}

fn snapshot(repo: &Path) -> EditorSnapshot {
    EditorSnapshot {
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

fn assert_no_classifier_temp_files(repo: &Path) {
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

#[test]
fn classifier_rule_editor_implementation_lists_persisted_classifier_rows() {
    let repo = initialized_repo();

    let snapshot = list_classifier_rules(path_string(repo.path())).expect("list rules");

    assert_eq!(snapshot.default_rule_id, "inbox");
    assert_eq!(snapshot.updated_rule_id, None);
    assert_eq!(snapshot.warning, None);
    assert!(snapshot.rules.iter().any(|rule| {
        rule.rule_id == "finance"
            && rule.slug == "finance"
            && rule.display_name == "Finance"
            && rule.keywords.iter().any(|keyword| keyword == "invoice")
            && !rule.is_default
    }));
    assert!(snapshot
        .rules
        .iter()
        .any(|rule| rule.rule_id == "inbox" && rule.is_default));
}

#[test]
fn classifier_rule_editor_implementation_updates_rule_for_future_classification_only() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before = snapshot(repo.path());

    let saved = update_classifier_rule(path_string(repo.path()), update_request())
        .expect("update classifier rule");

    assert_eq!(saved.updated_rule_id.as_deref(), Some("contracts"));
    assert!(saved.rules.iter().any(|rule| {
        rule.rule_id == "contracts"
            && rule.display_name == "Contracts"
            && rule.extensions == ["pdf", "docx"]
            && rule.keywords == ["agreement", "合同"]
            && rule.priority == 30
            && rule.naming_template.as_deref() == Some("{stem}-{date}")
    }));

    let config = read_classifier(repo.path());
    assert_eq!(config.default, "inbox");
    let contracts = category(&config, "contracts");
    assert_eq!(
        contracts.display_name.get("en").map(String::as_str),
        Some("Contracts")
    );
    assert_eq!(
        contracts.description.get("en").map(String::as_str),
        Some("Signed client contracts")
    );
    assert_eq!(contracts.extensions, vec!["pdf", "docx"]);
    assert_eq!(contracts.keywords, vec!["agreement", "合同"]);
    assert_eq!(contracts.priority, 30);
    assert_eq!(contracts.naming_template.as_deref(), Some("{stem}-{date}"));

    let predicted = predict_category(path_string(repo.path()), "agreement.pdf".to_owned())
        .expect("updated rule participates in future classification");
    assert_eq!(predicted.category, "contracts");
    assert_eq!(predicted.reason, ClassifyReason::Keyword);
    assert_eq!(user_visible_files(repo.path()), before.user_visible_files);
    assert_no_classifier_temp_files(repo.path());
    assert_ne!(
        fs::read_to_string(classifier_path(repo.path())).expect("read classifier yaml"),
        before.classifier_yaml
    );
}

#[test]
fn classifier_rule_editor_implementation_deletes_rule_without_touching_history() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before = snapshot(repo.path());

    let saved = delete_classifier_rule(path_string(repo.path()), delete_request("finance"))
        .expect("delete classifier rule");

    assert_eq!(saved.updated_rule_id.as_deref(), Some("inbox"));
    assert!(!saved.rules.iter().any(|rule| rule.rule_id == "finance"));
    let config = read_classifier(repo.path());
    assert!(config
        .categories
        .iter()
        .all(|category| category.slug != "finance"));
    assert_eq!(config.default, "inbox");
    assert_eq!(user_visible_files(repo.path()), before.user_visible_files);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_implementation_rejects_unpreviewed_impactful_changes_cleanly() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let mut unpreviewed_update = update_request();
    unpreviewed_update.preview_confirmed = false;
    assert!(matches!(
        update_classifier_rule(path_string(repo.path()), unpreviewed_update),
        Err(CoreError::Config { .. })
    ));

    let mut unpreviewed_delete = delete_request("finance");
    unpreviewed_delete.preview_confirmed = false;
    assert!(matches!(
        delete_classifier_rule(path_string(repo.path()), unpreviewed_delete),
        Err(CoreError::Config { .. })
    ));

    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_implementation_rejects_invalid_schema_without_writing() {
    let repo = initialized_repo();
    fs::write(
        classifier_path(repo.path()),
        "version: 1\ndefault: missing\ncategories:\n  - slug: finance\n",
    )
    .expect("write invalid classifier config");
    let before = snapshot(repo.path());

    assert!(matches!(
        update_classifier_rule(path_string(repo.path()), update_request()),
        Err(CoreError::Config { .. })
    ));

    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}

#[cfg(unix)]
#[test]
fn classifier_rule_editor_implementation_restores_old_config_when_final_sync_fails() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let classifier = classifier_path(repo.path());
    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata permissions")
        .permissions();
    let before = fs::read_to_string(&classifier).expect("read classifier before failure");

    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o333);
    fs::set_permissions(&metadata_dir, blocked_permissions)
        .expect("make metadata writable but not readable");

    let result = update_classifier_rule(path_string(repo.path()), update_request());

    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");

    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert_eq!(
        fs::read_to_string(&classifier).expect("read classifier after failed update"),
        before
    );
    assert_no_classifier_temp_files(repo.path());
}
