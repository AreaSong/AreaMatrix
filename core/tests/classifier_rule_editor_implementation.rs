use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    create_classifier_rule, delete_classifier_rule, init_repo, list_classifier_rules,
    load_repo_config, predict_category, update_classifier_rule, update_repo_config,
    ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest, ClassifierRuleObservedState,
    ClassifierRuleUpdate, ClassifyReason, ContentLocale, CoreError, OverviewOutput,
    RepoConfigPatch, RepoInitMode, RepoInitOptions, RepositoryLocalePolicy,
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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    load_repo_config(path_string(repo.path())).expect("prime repository config read state");
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
        repository_locale_policy: "system".to_owned(),
        editing_locale: ContentLocale::En,
        rule_id: "finance".to_owned(),
        observed: observed_finance_rule(),
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

fn observed_finance_rule() -> ClassifierRuleObservedState {
    ClassifierRuleObservedState {
        rule_id: "finance".to_owned(),
        slug: "finance".to_owned(),
        display_name: "Finance".to_owned(),
        description: String::new(),
        extensions: Vec::new(),
        keywords: vec![
            "invoice".to_owned(),
            "receipt".to_owned(),
            "tax".to_owned(),
            "contract".to_owned(),
            "发票".to_owned(),
            "收据".to_owned(),
            "税务".to_owned(),
            "合同".to_owned(),
            "报销".to_owned(),
        ],
        priority: 10,
        naming_template: None,
    }
}

fn create_request() -> ClassifierRuleCreateRequest {
    ClassifierRuleCreateRequest {
        repository_locale_policy: "system".to_owned(),
        editing_locale: ContentLocale::En,
        slug: "tax".to_owned(),
        display_name: "Tax".to_owned(),
        description: "Tax documents".to_owned(),
        extensions: vec!["pdf".to_owned()],
        keywords: vec!["tax".to_owned()],
        priority: 20,
        naming_template: Some("{stem}".to_owned()),
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

fn locale_value<'a>(
    values: &'a [area_matrix_core::ClassifierLocaleValue],
    locale: &str,
) -> Option<&'a str> {
    values
        .iter()
        .find(|entry| entry.locale == locale)
        .map(|entry| entry.value.as_str())
}

#[test]
fn classifier_rule_editor_implementation_lists_persisted_classifier_rows() {
    let repo = initialized_repo();

    let snapshot = list_classifier_rules(path_string(repo.path()), Some(ContentLocale::En))
        .expect("list rules");

    assert_eq!(snapshot.default_rule_id, "inbox");
    assert_eq!(snapshot.updated_rule_id, None);
    assert_eq!(snapshot.warning, None);
    assert!(snapshot.rules.iter().any(|rule| {
        rule.rule_id == "finance"
            && rule.slug == "finance"
            && locale_value(&rule.display_names, "en") == Some("Finance")
            && rule.keywords.iter().any(|keyword| keyword == "invoice")
            && !rule.is_default
    }));
    assert!(snapshot
        .rules
        .iter()
        .any(|rule| rule.rule_id == "inbox" && rule.is_default));
}

#[test]
fn classifier_rule_editor_implementation_creates_rule_for_future_classification_only() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before = snapshot(repo.path());

    let saved = create_classifier_rule(path_string(repo.path()), create_request())
        .expect("create classifier rule");

    assert_eq!(saved.updated_rule_id.as_deref(), Some("tax"));
    assert_eq!(saved.warning, None);
    assert!(saved.rules.iter().any(|rule| {
        rule.rule_id == "tax"
            && locale_value(&rule.display_names, "en") == Some("Tax")
            && locale_value(&rule.descriptions, "en") == Some("Tax documents")
            && rule.extensions == ["pdf"]
            && rule.keywords == ["tax"]
            && rule.priority == 20
            && rule.naming_template.as_deref() == Some("{stem}")
            && !rule.is_default
    }));

    let config = read_classifier(repo.path());
    assert_eq!(config.default, "inbox");
    let tax = category(&config, "tax");
    assert_eq!(tax.display_name.get("en").map(String::as_str), Some("Tax"));
    assert_eq!(
        tax.description.get("en").map(String::as_str),
        Some("Tax documents")
    );
    assert_eq!(tax.extensions, vec!["pdf"]);
    assert_eq!(tax.keywords, vec!["tax"]);
    assert_eq!(tax.priority, 20);
    assert_eq!(tax.naming_template.as_deref(), Some("{stem}"));

    let predicted = predict_category(path_string(repo.path()), "tax.pdf".to_owned())
        .expect("new rule participates in future classification");
    assert_eq!(predicted.category, "tax");
    assert_eq!(predicted.reason, ClassifyReason::Keyword);
    assert_eq!(user_visible_files(repo.path()), before.user_visible_files);
    assert_no_classifier_temp_files(repo.path());
    assert_ne!(
        fs::read_to_string(classifier_path(repo.path())).expect("read classifier yaml"),
        before.classifier_yaml
    );
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
            && locale_value(&rule.display_names, "en") == Some("Contracts")
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
fn classifier_rule_editor_implementation_edits_zh_map_under_explicit_en_policy() {
    let repo = initialized_repo();
    let config_snapshot =
        load_repo_config(path_string(repo.path())).expect("load repository config");
    update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: config_snapshot.revision,
            locale_policy: Some(RepositoryLocalePolicy::En),
            ..RepoConfigPatch::default()
        },
    )
    .expect("switch repository policy to English");

    let listed = list_classifier_rules(path_string(repo.path()), Some(ContentLocale::ZhHans))
        .expect("list Chinese classifier draft under English policy");
    assert_eq!(listed.repository_locale_policy, "en");
    assert_eq!(listed.editing_locale, Some(ContentLocale::ZhHans));

    let config = read_classifier(repo.path());
    let finance = category(&config, "finance");
    let request = ClassifierRuleUpdate {
        repository_locale_policy: "en".to_owned(),
        editing_locale: ContentLocale::ZhHans,
        rule_id: "finance".to_owned(),
        observed: ClassifierRuleObservedState {
            display_name: "财务".to_owned(),
            description: String::new(),
            ..observed_finance_rule()
        },
        slug: "finance".to_owned(),
        display_name: "财务资料".to_owned(),
        description: "用户维护的中文分类说明".to_owned(),
        extensions: finance.extensions.clone(),
        keywords: finance.keywords.clone(),
        priority: finance.priority,
        naming_template: finance.naming_template.clone(),
        preview_confirmed: false,
    };

    let saved = update_classifier_rule(path_string(repo.path()), request)
        .expect("patch Chinese classifier entry");
    let finance_record = saved
        .rules
        .iter()
        .find(|rule| rule.rule_id == "finance")
        .expect("finance rule remains available");
    assert_eq!(
        locale_value(&finance_record.display_names, "en"),
        Some("Finance")
    );
    assert_eq!(
        locale_value(&finance_record.display_names, "zh-Hans"),
        Some("财务资料")
    );
    assert_eq!(
        locale_value(&finance_record.descriptions, "zh-Hans"),
        Some("用户维护的中文分类说明")
    );

    let persisted = read_classifier(repo.path());
    let persisted_finance = category(&persisted, "finance");
    assert_eq!(
        persisted_finance.display_name.get("en").map(String::as_str),
        Some("Finance")
    );
    assert_eq!(
        persisted_finance
            .display_name
            .get("zh-Hans")
            .map(String::as_str),
        Some("财务资料")
    );
}

#[test]
fn classifier_rule_editor_implementation_rejects_stale_observed_rule_without_writing() {
    let repo = initialized_repo();
    let stale_request = update_request();

    let mut concurrent_request = update_request();
    concurrent_request.slug = "finance".to_owned();
    concurrent_request.display_name = "Finance latest".to_owned();
    concurrent_request.description = "Changed in another window".to_owned();
    concurrent_request.extensions = Vec::new();
    concurrent_request.keywords = observed_finance_rule().keywords;
    concurrent_request.priority = 10;
    concurrent_request.naming_template = None;
    concurrent_request.preview_confirmed = false;
    update_classifier_rule(path_string(repo.path()), concurrent_request)
        .expect("persist concurrent English edit");
    let after_concurrent_edit = snapshot(repo.path());

    let result = update_classifier_rule(path_string(repo.path()), stale_request);

    assert!(matches!(
        result,
        Err(CoreError::Conflict { path }) if path == "classifier_rule_observed_state"
    ));
    assert_eq!(snapshot(repo.path()), after_concurrent_edit);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_implementation_reports_removed_observed_rule_as_conflict() {
    let repo = initialized_repo();
    let stale_request = update_request();
    delete_classifier_rule(path_string(repo.path()), delete_request("finance"))
        .expect("remove rule in another window");
    let after_concurrent_delete = snapshot(repo.path());

    let result = update_classifier_rule(path_string(repo.path()), stale_request);

    assert!(matches!(
        result,
        Err(CoreError::Conflict { path }) if path == "classifier_rule_observed_state"
    ));
    assert_eq!(snapshot(repo.path()), after_concurrent_delete);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_implementation_ignores_other_locale_change_and_preserves_it() {
    let repo = initialized_repo();
    let config = read_classifier(repo.path());
    let finance = category(&config, "finance");
    let mut zh_observed = observed_finance_rule();
    zh_observed.display_name = "财务".to_owned();
    let zh_request = ClassifierRuleUpdate {
        repository_locale_policy: "system".to_owned(),
        editing_locale: ContentLocale::ZhHans,
        rule_id: "finance".to_owned(),
        observed: zh_observed,
        slug: "finance".to_owned(),
        display_name: "财务资料".to_owned(),
        description: "另一窗口保存的中文说明".to_owned(),
        extensions: finance.extensions.clone(),
        keywords: finance.keywords.clone(),
        priority: finance.priority,
        naming_template: finance.naming_template.clone(),
        preview_confirmed: false,
    };
    update_classifier_rule(path_string(repo.path()), zh_request)
        .expect("persist Chinese-only concurrent edit");

    let mut english_request = update_request();
    english_request.slug = "finance".to_owned();
    english_request.extensions = finance.extensions.clone();
    english_request.keywords = finance.keywords.clone();
    english_request.priority = finance.priority;
    english_request.naming_template = finance.naming_template.clone();
    english_request.preview_confirmed = false;
    let saved = update_classifier_rule(path_string(repo.path()), english_request)
        .expect("English save ignores Chinese-only change");

    let finance_record = saved
        .rules
        .iter()
        .find(|rule| rule.rule_id == "finance")
        .expect("finance rule remains available");
    assert_eq!(
        locale_value(&finance_record.display_names, "zh-Hans"),
        Some("财务资料")
    );
    assert_eq!(
        locale_value(&finance_record.descriptions, "zh-Hans"),
        Some("另一窗口保存的中文说明")
    );
    assert_eq!(
        locale_value(&finance_record.display_names, "en"),
        Some("Contracts")
    );
    assert_no_classifier_temp_files(repo.path());
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
