use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, load_config, update_config, ContentLocale, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use rusqlite::Connection;

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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

fn regenerate_overview(
    repo: &Path,
    configured_locale: &str,
    operation_locale: ContentLocale,
) -> String {
    let repo_path = path_string(repo);
    let mut config = load_config(repo_path.clone()).expect("load repository config");
    config.locale = configured_locale.to_owned();
    update_config(repo_path.clone(), config).expect("update repository content locale");

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
            content_locale: operation_locale,
        },
    )
    .expect("import fixture and regenerate overview");

    fs::read_to_string(repo.join(".areamatrix/generated/root.md")).expect("read generated overview")
}

#[test]
fn operation_content_locale_is_explicit_and_does_not_read_mutable_global_state() {
    let system_english_repo = initialize_repo();
    let readme = system_english_repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README fixture");
    let english = regenerate_overview(system_english_repo.path(), "system", ContentLocale::En);
    assert!(english.starts_with("# AreaMatrix Repository"));
    assert!(english.contains("用户资料.txt"));
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README after generation"),
        "user readme\n"
    );

    let system_chinese_repo = initialize_repo();
    let chinese = regenerate_overview(
        system_chinese_repo.path(),
        "system",
        ContentLocale::ZhHans,
    );
    assert!(chinese.starts_with("# AreaMatrix 资料库"));

    let explicit_chinese_repo = initialize_repo();
    let explicit_chinese = regenerate_overview(
        explicit_chinese_repo.path(),
        "zh-Hans",
        ContentLocale::En,
    );
    assert!(explicit_chinese.starts_with("# AreaMatrix Repository"));

    let explicit_english_repo = initialize_repo();
    let explicit_english = regenerate_overview(
        explicit_english_repo.path(),
        "en",
        ContentLocale::ZhHans,
    );
    assert!(explicit_english.starts_with("# AreaMatrix 资料库"));
}

#[test]
fn unsupported_repository_locale_fails_before_import_side_effects() {
    let repo = initialize_repo();
    Connection::open(repo.path().join(".areamatrix/index.db"))
        .expect("open repository metadata")
        .execute(
            "UPDATE repo_config SET value = 'legacy-unsupported' WHERE key = 'locale'",
            [],
        )
        .expect("install unsupported legacy locale fixture");
    let source_root = tempfile::tempdir().expect("create source directory");
    let source = source_root.path().join("source.txt");
    fs::write(&source, "unchanged user content").expect("write source fixture");
    let root_before = fs::read(repo.path().join(".areamatrix/generated/root.md"))
        .expect("read initial generated root");

    let error = import_file(
        path_string(repo.path()),
        path_string(&source),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::AutoClassify,
            target_directory: None,
            override_category: Some("docs".to_owned()),
            override_filename: None,
            duplicate_strategy: DuplicateStrategy::Skip,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect_err("unsupported repository locale must fail closed");

    assert!(matches!(error, CoreError::Config { .. }));
    assert!(source.exists());
    assert!(!repo.path().join("docs/source.txt").exists());
    assert_eq!(
        fs::read(repo.path().join(".areamatrix/generated/root.md"))
            .expect("read generated root after rejected import"),
        root_before
    );
}
