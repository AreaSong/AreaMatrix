use area_matrix_core::{
    init_repo, list_files, list_tree_json, load_config, CoreError, CoreResult, FileEntry,
    FileFilter, OverviewOutput, RepoConfig, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;

#[test]
fn init_empty_repo_contract_exports_callable_signatures() {
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}
    fn assert_list_files(_: fn(String, FileFilter) -> CoreResult<Vec<FileEntry>>) {}
    fn assert_list_tree_json(_: fn(String, String) -> CoreResult<String>) {}

    assert_init(init_repo);
    assert_load_config(load_config);
    assert_list_files(list_files);
    assert_list_tree_json(list_tree_json);
}

#[test]
fn init_empty_repo_contract_exposes_documented_inputs() {
    let options = RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: true,
        overview_output: OverviewOutput::GeneratedOnly,
    };

    assert_eq!(options.mode, RepoInitMode::CreateEmpty);
    assert!(options.create_default_categories);
    assert_eq!(options.overview_output, OverviewOutput::GeneratedOnly);
}

#[test]
fn init_empty_repo_contract_keeps_create_empty_separate_from_adopt_existing() {
    let create_empty = RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    };
    let adopt_existing = RepoInitOptions {
        mode: RepoInitMode::AdoptExisting,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    };

    assert_ne!(create_empty.mode, adopt_existing.mode);
}

#[test]
fn init_empty_repo_contract_exposes_documented_outputs() {
    let config = RepoConfig {
        repo_path: "/tmp/area-matrix-empty".to_owned(),
        default_mode: StorageMode::Copied,
        overview_output: OverviewOutput::GeneratedOnly,
        ai_enabled: false,
        locale: "zh-Hans".to_owned(),
        icloud_warn: true,
        enable_extension_rules: true,
        enable_keyword_rules: true,
        fallback_to_inbox: true,
        allow_replace_during_import: false,
    };
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        repo.path().to_string_lossy().into_owned(),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize empty repository");
    let empty_tree_json = list_tree_json(
        repo.path().to_string_lossy().into_owned(),
        "zh-Hans".to_owned(),
    )
    .expect("list initialized empty tree");
    let empty_tree: serde_json::Value =
        serde_json::from_str(&empty_tree_json).expect("parse empty tree JSON");

    assert_eq!(config.repo_path, "/tmp/area-matrix-empty");
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert_eq!(empty_tree["slug"], "__root__");
    assert!(empty_tree["children"]
        .as_array()
        .expect("empty tree children should be an array")
        .is_empty());
}

#[test]
fn init_empty_repo_contract_exposes_documented_error_codes() {
    let errors = [
        CoreError::InvalidPath,
        CoreError::PermissionDenied,
        CoreError::Config,
        CoreError::Io,
        CoreError::Db,
    ];

    assert_eq!(errors.len(), 5);
}

#[test]
fn init_empty_repo_contract_udl_matches_public_api() {
    let udl = include_str!("../area_matrix.udl");

    assert!(udl.contains("void init_repo(string repo_path, RepoInitOptions options);"));
    assert!(udl.contains("RepoConfig load_config(string repo_path);"));
    assert!(udl.contains("string list_tree_json(string repo_path, string locale);"));
    assert!(udl.contains("dictionary RepoInitOptions"));
    assert!(udl.contains("RepoInitMode mode;"));
    assert!(udl.contains("boolean create_default_categories;"));
    assert!(udl.contains("OverviewOutput overview_output;"));
    assert!(udl.contains("enum RepoInitMode { \"CreateEmpty\", \"AdoptExisting\" };"));
    assert!(udl.contains("enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };"));
}
