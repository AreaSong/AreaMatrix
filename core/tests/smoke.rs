use area_matrix_core::{
    get_version, load_config, ClassifyReason, CoreError, DuplicateStrategy, ImportDestination,
    ImportOptions, OverviewOutput, RepoConfig, StorageMode,
};
use pretty_assertions::assert_eq;
use serde_yaml::Value;

#[test]
fn version_is_readable() {
    assert_eq!(get_version(), env!("CARGO_PKG_VERSION"));
}

#[test]
fn public_types_can_be_constructed() {
    let config = RepoConfig {
        repo_path: "/tmp/area".to_owned(),
        default_mode: StorageMode::Copied,
        overview_output: OverviewOutput::GeneratedOnly,
        ai_enabled: false,
        locale: "zh-Hans".to_owned(),
        icloud_warn: true,
    };

    let options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Ask,
    };

    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(options.override_category.as_deref(), Some("docs"));
    assert_eq!(ClassifyReason::Default, ClassifyReason::Default);
}

#[test]
fn placeholder_api_returns_internal_error() {
    let error = load_config("/tmp/not-a-real-repo".to_owned()).expect_err("stub should fail");

    assert_eq!(error, CoreError::Internal);
}

#[test]
fn bundled_classifier_yaml_is_valid_yaml() {
    let yaml = include_str!("../resources/classifier.yaml");
    let value: Value = serde_yaml::from_str(yaml).expect("default classifier yaml is valid");
    let categories = value["categories"]
        .as_sequence()
        .expect("categories should be a sequence");

    assert_eq!(value["version"].as_i64(), Some(1));
    assert_eq!(value["default"].as_str(), Some("inbox"));
    assert!(categories.iter().any(|category| category["slug"] == "docs"));
    assert!(categories
        .iter()
        .any(|category| category["slug"] == "inbox"));
}
