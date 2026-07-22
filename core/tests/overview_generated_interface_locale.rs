use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, load_config, set_app_interface_locale, update_config,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialize_repo() -> tempfile::TempDir {
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

fn regenerate_overview(repo: &Path, content_locale: &str, interface_locale: &str) -> String {
    let repo_path = path_string(repo);
    let mut config = load_config(repo_path.clone()).expect("load repository config");
    config.locale = content_locale.to_owned();
    update_config(repo_path.clone(), config).expect("update repository content locale");
    set_app_interface_locale(interface_locale.to_owned()).expect("set app interface locale");

    let source_root = tempfile::tempdir().expect("create source directory");
    let source = source_root.path().join("用户资料.txt");
    fs::write(&source, "unchanged user content").expect("write source fixture");
    import_file(
        repo_path,
        path_string(&source),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::AutoClassify,
            target_directory: None,
            override_category: Some("docs".to_owned()),
            override_filename: None,
            duplicate_strategy: DuplicateStrategy::Skip,
        },
    )
    .expect("import fixture and regenerate overview");

    fs::read_to_string(repo.join(".areamatrix/generated/root.md")).expect("read generated overview")
}

#[test]
fn system_content_locale_follows_interface_without_overriding_explicit_locale() {
    let system_english_repo = initialize_repo();
    let readme = system_english_repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README fixture");
    let english = regenerate_overview(system_english_repo.path(), "system", "en");
    assert!(english.starts_with("# AreaMatrix Repository"));
    assert!(english.contains("用户资料.txt"));
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README after generation"),
        "user readme\n"
    );

    let system_chinese_repo = initialize_repo();
    let chinese = regenerate_overview(system_chinese_repo.path(), "system", "zh-Hans");
    assert!(chinese.starts_with("# AreaMatrix 资料库"));

    let explicit_chinese_repo = initialize_repo();
    let explicit_chinese = regenerate_overview(explicit_chinese_repo.path(), "zh-Hans", "en");
    assert!(explicit_chinese.starts_with("# AreaMatrix 资料库"));

    let explicit_english_repo = initialize_repo();
    let explicit_english = regenerate_overview(explicit_english_repo.path(), "en", "zh-Hans");
    assert!(explicit_english.starts_with("# AreaMatrix Repository"));

    assert!(set_app_interface_locale("fr".to_owned()).is_err());
}
