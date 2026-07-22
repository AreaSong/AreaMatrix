use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, load_config, update_config, DuplicateStrategy, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
#[path = "support/domain_contract_source.rs"]
mod domain_contract_source;

use domain_contract_source::DOMAIN_RS;
const STORAGE_IMPORT_RS: &str = include_str!("../src/storage/import.rs");
const OVERVIEW_RS: &str = include_str!("../src/overview/mod.rs");
const ATOMIC_WRITE_RS: &str = include_str!("../src/overview/atomic_write.rs");
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

fn copied_options(category: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn source_file(name: &str, content: &[u8]) -> tempfile::TempDir {
    let source_root = tempfile::tempdir().expect("create source directory");
    fs::write(source_root.path().join(name), content).expect("write source file");
    source_root
}

fn import_doc(repo: &Path, name: &str, content: &[u8]) {
    let source_root = source_file(name, content);
    import_file(
        path_string(repo),
        path_string(&source_root.path().join(name)),
        copied_options("docs"),
    )
    .expect("import file and regenerate overview");
}

fn read_file(path: &Path) -> String {
    fs::read_to_string(path).expect("read file")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected `{needle}` in:\n{haystack}"
    );
}
#[test]
fn overview_generated_integration_verify_api_udl_and_rust_wiring_are_real() {
    for fragment in [
        "void set_app_interface_locale(string locale);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "FileEntry import_file(",
        "void update_config(string repo_path, RepoConfig new_config);",
        "OverviewOutput overview_output;",
        "enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn set_app_interface_locale(locale: String) -> CoreResult<()>",
        "generated overview uses `RepoInitOptions::overview_output`",
        "later overview-regeneration triggers read the",
        "generated overview uses a successful import as a generated-overview trigger",
        "`.areamatrix/generated/`",
        "`README.md` remains user-authored content",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Where generated overview output is written.",
        "Write generated overviews under `.areamatrix/generated/`.",
        "Also maintain the root-level `AREAMATRIX.md` file.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "finish_overview_regeneration",
        "overview::regenerate_after_import",
    ] {
        assert_contains(STORAGE_IMPORT_RS, fragment);
    }

    for fragment in [
        "write_plans_with_rollback",
        "regenerate_for_node(repo, &entry.category)",
        "repo.join(\"AREAMATRIX.md\")",
        "merge_managed_block",
        "write_atomic_replace",
    ] {
        assert_contains(OVERVIEW_RS, fragment);
    }
    assert_contains(ATOMIC_WRITE_RS, "restore_snapshots");
}

#[test]
fn overview_generated_integration_verify_settings_policy_round_trip_and_regeneration() {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        create_empty_options(OverviewOutput::GeneratedOnly),
    )
    .expect("initialize repository");

    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    assert_eq!(
        load_config(path_string(repo.path()))
            .expect("load initial config")
            .overview_output,
        OverviewOutput::GeneratedOnly
    );
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());
    assert!(!repo.path().join("AREAMATRIX.md").exists());

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("persist root overview policy");
    assert!(!repo.path().join("AREAMATRIX.md").exists());

    import_doc(repo.path(), "root-enabled.pdf", b"root enabled");
    let root_entry_path = repo.path().join("AREAMATRIX.md");
    let root_entry = read_file(&root_entry_path);
    assert_contains(&root_entry, "AREAMATRIX:BEGIN");
    assert_contains(&root_entry, "root-enabled.pdf");
    assert_eq!(read_file(&readme_path), "user readme\n");

    let mut config = load_config(path_string(repo.path())).expect("reload config");
    config.overview_output = OverviewOutput::GeneratedOnly;
    update_config(path_string(repo.path()), config).expect("persist generated-only policy");
    import_doc(repo.path(), "generated-only.pdf", b"generated only");

    assert_eq!(read_file(&root_entry_path), root_entry);
    let generated_root = read_file(&repo.path().join(".areamatrix/generated/root.md"));
    assert_contains(&generated_root, "root-enabled.pdf");
    assert_contains(&generated_root, "generated-only.pdf");
    assert_eq!(read_file(&readme_path), "user readme\n");
}
