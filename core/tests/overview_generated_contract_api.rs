use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, load_config, update_config, CoreError, CoreResult, DuplicateStrategy,
    FileEntry, ImportDestination, ImportOptions, OverviewOutput, RepoConfig, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options(overview_output: OverviewOutput) -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output,
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn overview_generated_contract_api_exposes_documented_signatures_inputs_and_errors() {
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}
    fn assert_update(_: fn(String, RepoConfig) -> CoreResult<()>) {}

    assert_init(init_repo);
    assert_import(import_file);
    assert_update(update_config);

    let init_options = create_empty_options(OverviewOutput::RootAreaMatrixFile);
    assert_eq!(
        init_options.overview_output,
        OverviewOutput::RootAreaMatrixFile
    );

    let import_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    };
    assert_eq!(import_options.destination, ImportDestination::AutoClassify);

    let documented_errors = [
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::config("configuration error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}
#[test]
fn overview_generated_contract_api_core_api_and_udl_stay_aligned() {
    for fragment in [
        "void init_repo(string repo_path, RepoInitOptions options);",
        "FileEntry import_file(",
        "void update_config(string repo_path, RepoConfig new_config);",
        "dictionary RepoConfig",
        "OverviewOutput overview_output;",
        "dictionary RepoInitOptions",
        "enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };",
        "PermissionDenied(string path);",
        "Io(string message);",
        "Config(string reason);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn overview_generated_contract_api_documents_side_effects_errors_and_scope() {
    for fragment in [
        "`PermissionDenied { path }`",
        "`Io { message }`",
        "`Config { reason }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "generated overview uses `RepoInitOptions::overview_output`",
        "`OverviewOutput::GeneratedOnly` writes the generated root",
        "`RootAreaMatrixFile` also",
        "root-level `AREAMATRIX.md`",
        "`README.md`",
        "For generated overview, this is the contract boundary",
        "later overview-regeneration triggers",
        "file side effects",
        "generated overview uses a successful import as a generated-overview trigger",
        "no extra FFI input",
        "current [`RepoConfig::overview_output`]",
        "`.areamatrix/generated/`",
        "`AREAMATRIX.md`",
        "`README.md` remains user-authored content",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Where generated overview output is written.",
        "Write generated overviews under `.areamatrix/generated/`.",
        "Also maintain the root-level `AREAMATRIX.md` file.",
        "Overview output location.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}

#[test]
fn overview_generated_contract_api_init_outputs_match_overview_policy() {
    let generated_repo = tempfile::tempdir().expect("create GeneratedOnly repository");
    init_repo(
        path_string(generated_repo.path()),
        create_empty_options(OverviewOutput::GeneratedOnly),
    )
    .expect("initialize GeneratedOnly repository");

    let generated_root = generated_repo.path().join(".areamatrix/generated/root.md");
    assert!(generated_root.is_file());
    assert_contains(
        &fs::read_to_string(generated_root).expect("read generated root overview"),
        "AREAMATRIX:BEGIN",
    );
    assert!(!generated_repo.path().join("README.md").exists());
    assert!(!generated_repo.path().join("AREAMATRIX.md").exists());

    let root_file_repo = tempfile::tempdir().expect("create RootAreaMatrixFile repository");
    init_repo(
        path_string(root_file_repo.path()),
        create_empty_options(OverviewOutput::RootAreaMatrixFile),
    )
    .expect("initialize RootAreaMatrixFile repository");

    assert!(root_file_repo
        .path()
        .join(".areamatrix/generated/root.md")
        .is_file());
    assert!(root_file_repo.path().join("AREAMATRIX.md").is_file());
    assert!(!root_file_repo.path().join("README.md").exists());
}

#[test]
fn overview_generated_contract_api_update_config_persists_policy_without_touching_readme() {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        create_empty_options(OverviewOutput::GeneratedOnly),
    )
    .expect("initialize repository");
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("persist overview output policy");

    let reloaded = load_config(path_string(repo.path())).expect("reload config");
    assert_eq!(reloaded.overview_output, OverviewOutput::RootAreaMatrixFile);
    assert_eq!(
        fs::read_to_string(readme_path).expect("read preserved README"),
        "user readme\n"
    );
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}
