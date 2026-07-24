use std::{collections::BTreeMap, fs, path::Path};

use area_matrix_core::{
    create_default_classifier, init_repo, list_classifier_rules, predict_category,
    restore_default_classifier, restore_last_valid_classifier, save_classifier_rule,
    update_classifier_rule, ClassifierConfigHealth, ClassifierRecoveryAction, ClassifierRule,
    ClassifierRuleObservedState, ClassifierRuleUpdate, ContentLocale, OverviewOutput, RepoInitMode,
    RepoInitOptions, RepositoryLocalePolicy,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create classifier recovery fixture");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: RepositoryLocalePolicy::FollowInterface,
            content_locale: ContentLocale::En,
        },
    )
    .expect("initialize classifier recovery fixture");
    repo
}

fn classifier_path(repo: &Path) -> std::path::PathBuf {
    repo.join(".areamatrix/classifier.yaml")
}

fn user_files(repo: &Path) -> BTreeMap<String, Vec<u8>> {
    fs::read_dir(repo)
        .expect("read fixture root")
        .filter_map(Result::ok)
        .filter(|entry| entry.file_name() != ".areamatrix")
        .filter(|entry| entry.path().is_file())
        .map(|entry| {
            (
                entry.file_name().to_string_lossy().into_owned(),
                fs::read(entry.path()).expect("read fixture user file"),
            )
        })
        .collect()
}

fn finance_update() -> ClassifierRuleUpdate {
    ClassifierRuleUpdate {
        repository_locale_policy: "system".to_owned(),
        editing_locale: ContentLocale::En,
        rule_id: "finance".to_owned(),
        observed: observed_finance_rule(),
        slug: "finance".to_owned(),
        display_name: "Financial records".to_owned(),
        description: "Receipts and invoices".to_owned(),
        extensions: Vec::new(),
        keywords: finance_keywords(),
        priority: 10,
        naming_template: None,
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
        keywords: finance_keywords(),
        priority: 10,
        naming_template: None,
    }
}

fn finance_keywords() -> Vec<String> {
    [
        "invoice", "receipt", "tax", "contract", "发票", "收据", "税务", "合同", "报销",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect()
}

#[test]
fn missing_classifier_is_degraded_until_confirmed_create_default() {
    let repo = initialized_repo();
    fs::write(repo.path().join("notes.txt"), b"user bytes").expect("write user fixture");
    let before_user_files = user_files(repo.path());
    fs::remove_file(classifier_path(repo.path())).expect("remove managed classifier fixture");

    let degraded = list_classifier_rules(path_string(repo.path()), Some(ContentLocale::En))
        .expect("load missing classifier health");
    assert_eq!(degraded.health, ClassifierConfigHealth::Missing);
    assert_eq!(
        degraded.recovery_actions,
        vec![ClassifierRecoveryAction::CreateDefault]
    );
    assert!(degraded.rules.is_empty());
    assert_eq!(degraded.editing_locale, None);
    assert!(predict_category(path_string(repo.path()), "invoice.pdf".to_owned()).is_err());
    assert!(
        create_default_classifier(path_string(repo.path()), false, Some(ContentLocale::En))
            .is_err()
    );
    assert!(!classifier_path(repo.path()).exists());

    let restored =
        create_default_classifier(path_string(repo.path()), true, Some(ContentLocale::En))
            .expect("create explicitly confirmed default classifier");
    assert_eq!(restored.health, ClassifierConfigHealth::Valid);
    assert_eq!(restored.editing_locale, Some(ContentLocale::En));
    assert_eq!(user_files(repo.path()), before_user_files);
}

#[test]
fn invalid_classifier_restore_is_numbered_non_overwriting_and_last_valid_is_verified() {
    let repo = initialized_repo();
    let original = fs::read(classifier_path(repo.path())).expect("read original classifier");

    update_classifier_rule(path_string(repo.path()), finance_update())
        .expect("save classifier and preserve last-valid backup");
    let archive = repo.path().join(".areamatrix/archives/classifier");
    assert_eq!(
        fs::read(archive.join("classifier.yaml.000001.bak")).expect("read first last-valid backup"),
        original
    );

    fs::write(classifier_path(repo.path()), b"version: [invalid")
        .expect("write readable invalid classifier fixture");
    let degraded = list_classifier_rules(path_string(repo.path()), Some(ContentLocale::ZhHans))
        .expect("load invalid classifier health");
    assert_eq!(degraded.health, ClassifierConfigHealth::Invalid);
    assert_eq!(
        degraded.recovery_actions,
        vec![
            ClassifierRecoveryAction::RestoreDefault,
            ClassifierRecoveryAction::RestoreLastValid,
        ]
    );

    let restored =
        restore_last_valid_classifier(path_string(repo.path()), true, Some(ContentLocale::ZhHans))
            .expect("restore verified last-valid classifier");
    assert_eq!(restored.health, ClassifierConfigHealth::Valid);
    assert_eq!(fs::read(classifier_path(repo.path())).unwrap(), original);
    assert_eq!(
        fs::read(archive.join("classifier.yaml.000002.bak"))
            .expect("read non-overwriting invalid-byte backup"),
        b"version: [invalid"
    );
}

#[test]
fn readable_invalid_classifier_can_restore_default_but_symlink_cannot_write() {
    let repo = initialized_repo();
    fs::write(
        classifier_path(repo.path()),
        b"version: 99\ndefault: inbox\ncategories: []\n",
    )
    .expect("write schema-invalid classifier fixture");
    let restored =
        restore_default_classifier(path_string(repo.path()), true, Some(ContentLocale::En))
            .expect("restore embedded default over readable invalid bytes");
    assert_eq!(restored.health, ClassifierConfigHealth::Valid);

    let outside = tempfile::NamedTempFile::new().expect("create outside target fixture");
    fs::write(outside.path(), b"outside bytes").expect("write outside target fixture");
    fs::remove_file(classifier_path(repo.path())).expect("remove active classifier for symlink");
    std::os::unix::fs::symlink(outside.path(), classifier_path(repo.path()))
        .expect("create classifier symlink fixture");

    let degraded = list_classifier_rules(path_string(repo.path()), Some(ContentLocale::En))
        .expect("load unsafe classifier health");
    assert_eq!(degraded.health, ClassifierConfigHealth::Unreadable);
    assert!(degraded.recovery_actions.is_empty());
    assert!(
        restore_default_classifier(path_string(repo.path()), true, Some(ContentLocale::En))
            .is_err()
    );
    assert_eq!(fs::read(outside.path()).unwrap(), b"outside bytes");
}

#[test]
fn unknown_repository_policy_blocks_classification_and_every_classifier_mutation() {
    let repo = initialized_repo();
    let connection = rusqlite::Connection::open(repo.path().join(".areamatrix/index.db"))
        .expect("open fixture repository database");
    connection
        .execute("DELETE FROM repo_config WHERE key = 'locale'", [])
        .expect("remove legacy locale evidence");
    drop(connection);
    let before =
        fs::read(classifier_path(repo.path())).expect("read classifier before blocked calls");

    assert!(predict_category(path_string(repo.path()), "invoice.pdf".to_owned()).is_err());
    assert!(update_classifier_rule(path_string(repo.path()), finance_update()).is_err());
    assert!(save_classifier_rule(
        path_string(repo.path()),
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec!["new-keyword".to_owned()],
            extensions: Vec::new(),
            priority: 10,
            preview_confirmed: false,
        }
    )
    .is_err());
    assert_eq!(
        fs::read(classifier_path(repo.path())).expect("read classifier after blocked calls"),
        before
    );
}
