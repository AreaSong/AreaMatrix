use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, predict_category, ClassifyReason, CoreError, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn classifier_path(repo: &Path) -> PathBuf {
    repo.join(".areamatrix/classifier.yaml")
}

fn write_classifier(repo: &Path, content: &str) {
    fs::write(classifier_path(repo), content).expect("write classifier fixture");
}

fn snapshot_files(root: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut files = BTreeMap::new();
    collect_files(root, root, &mut files);
    files
}

fn collect_files(root: &Path, current: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
    for entry in fs::read_dir(current).expect("read snapshot directory") {
        let path = entry.expect("read snapshot entry").path();
        if path.is_dir() {
            collect_files(root, &path, files);
            continue;
        }

        let relative = path
            .strip_prefix(root)
            .expect("snapshot path under root")
            .to_path_buf();
        let content = fs::read(&path).expect("read snapshot file content");
        files.insert(relative, content);
    }
}

#[test]
fn classify_preview_validation_success_keyword_wins_over_high_priority_extension() {
    let repo = initialized_repo();
    write_classifier(
        repo.path(),
        r#"version: 1
default: inbox
categories:
  - slug: docs
    extensions: [pdf]
    priority: 100
  - slug: invoices
    keywords: [invoice]
    priority: -100
  - slug: inbox
"#,
    );

    let before = snapshot_files(repo.path());

    let result = predict_category(path_string(repo.path()), "Invoice_2026.pdf".to_owned())
        .expect("predict category with custom classifier");

    assert_eq!(result.category, "invoices");
    assert_eq!(result.suggested_name, "Invoice_2026.pdf");
    assert_eq!(result.reason, ClassifyReason::Keyword);
    assert_eq!(result.confidence, 0.9);
    assert_eq!(snapshot_files(repo.path()), before);
}

#[test]
fn classify_preview_validation_missing_classifier_uses_default_without_writes() {
    let repo = initialized_repo();
    let classifier = classifier_path(repo.path());
    fs::remove_file(&classifier).expect("remove classifier fixture");
    let before = snapshot_files(repo.path());

    let result = predict_category(path_string(repo.path()), "Receipt_2026.pdf".to_owned())
        .expect("predict category from bundled default classifier");

    assert_eq!(result.category, "finance");
    assert_eq!(result.reason, ClassifyReason::Keyword);
    assert!(!classifier.exists());
    assert_eq!(snapshot_files(repo.path()), before);
}

#[test]
fn classify_preview_validation_invalid_schema_returns_config_without_writes() {
    let repo = initialized_repo();
    write_classifier(
        repo.path(),
        "version: 1\ndefault: missing\ncategories:\n  - slug: docs\n    extensions: [pdf]\n",
    );
    let before = snapshot_files(repo.path());

    let result = predict_category(path_string(repo.path()), "report.pdf".to_owned());

    assert_eq!(result, Err(CoreError::Config));
    assert_eq!(snapshot_files(repo.path()), before);
}

#[test]
fn classify_preview_validation_unreadable_rule_source_returns_classify_without_writes() {
    let repo = initialized_repo();
    let classifier = classifier_path(repo.path());
    fs::remove_file(&classifier).expect("remove classifier file");
    fs::create_dir(&classifier).expect("replace classifier with directory");
    let before = snapshot_files(repo.path());

    let result = predict_category(path_string(repo.path()), "invoice.pdf".to_owned());

    assert_eq!(result, Err(CoreError::Classify));
    assert!(classifier.is_dir());
    assert_eq!(snapshot_files(repo.path()), before);
}
