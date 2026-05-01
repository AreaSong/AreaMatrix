use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_files, list_tree_json, load_config, CoreError, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

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

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

#[test]
fn init_empty_repo_creates_metadata_db_config_rules_and_generated_overview() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize empty repo");

    let metadata_dir = repo.path().join(".areamatrix");
    assert!(metadata_dir.join("staging").is_dir());
    assert!(metadata_dir.join("archives").is_dir());
    assert!(metadata_dir.join("generated").is_dir());
    assert!(metadata_dir.join("classifier.yaml").is_file());
    assert!(metadata_dir.join("ignore.yaml").is_file());
    assert!(metadata_dir.join("index.db").is_file());

    let root_overview =
        fs::read_to_string(metadata_dir.join("generated/root.md")).expect("read root overview");
    assert!(root_overview.contains("AREAMATRIX:BEGIN"));
    assert!(root_overview.contains("AREAMATRIX:END"));
    assert!(!repo.path().join("README.md").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());

    let config = load_config(path_string(repo.path())).expect("load initialized repo config");
    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!config.ai_enabled);
    assert_eq!(config.locale, "zh-Hans");
    assert!(config.icloud_warn);
    assert!(config.enable_extension_rules);
    assert!(config.enable_keyword_rules);
    assert!(config.fallback_to_inbox);
    assert!(!config.allow_replace_during_import);

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list empty files");
    assert!(files.is_empty());
    assert_eq!(
        list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list empty tree"),
        r#"{"children":[]}"#
    );

    let connection =
        Connection::open(metadata_dir.join("index.db")).expect("open initialized database");
    let version: i64 = connection
        .query_row("SELECT MAX(version) FROM schema_version", [], |row| {
            row.get(0)
        })
        .expect("read schema version");
    let config_rows: i64 = connection
        .query_row("SELECT COUNT(*) FROM repo_config", [], |row| row.get(0))
        .expect("count repo_config rows");
    assert_eq!(version, 1);
    assert_eq!(config_rows, 10);
}

#[test]
fn init_empty_repo_allows_hidden_system_entries_without_deleting_them() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let ds_store = repo.path().join(".DS_Store");
    fs::write(&ds_store, "finder metadata").expect("write hidden metadata");

    init_repo(path_string(repo.path()), create_empty_options())
        .expect("initialize hidden-only repo");

    assert!(ds_store.is_file());
    assert!(repo.path().join(".areamatrix/index.db").is_file());
}

#[test]
fn init_empty_repo_rejects_hidden_user_content_without_touching_it() {
    for entry_name in [".env", ".git"] {
        let repo = tempfile::tempdir().expect("create temporary repository directory");
        let entry_path = repo.path().join(entry_name);
        if entry_name == ".git" {
            fs::create_dir(&entry_path).expect("create hidden user directory");
        } else {
            fs::write(&entry_path, "owned by user").expect("write hidden user file");
        }

        let result = init_repo(path_string(repo.path()), create_empty_options());

        assert_eq!(result, Err(CoreError::Config));
        assert!(entry_path.exists(), "{entry_name} should remain untouched");
        assert!(!repo.path().join(".areamatrix").exists());
    }
}

#[test]
fn init_empty_repo_rejects_non_empty_directory_without_touching_user_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# User project\n").expect("write user README");

    let result = init_repo(path_string(repo.path()), create_empty_options());

    assert_eq!(result, Err(CoreError::Config));
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README"),
        "# User project\n"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn init_empty_repo_rejects_adopt_existing_mode_without_creating_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let mut options = create_empty_options();
    options.mode = RepoInitMode::AdoptExisting;

    let result = init_repo(path_string(repo.path()), options);

    assert_eq!(result, Err(CoreError::Config));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn init_empty_repo_rejects_area_matrix_internal_path_without_writing_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let internal_path = repo.path().join(".areamatrix").join("staging");

    let result = init_repo(path_string(&internal_path), create_empty_options());

    assert_eq!(result, Err(CoreError::InvalidPath));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn init_empty_repo_rejects_repeated_initialization_without_destroying_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize empty repo");
    let root_overview_path = repo.path().join(".areamatrix/generated/root.md");
    let before = fs::read_to_string(&root_overview_path).expect("read initial overview");

    let result = init_repo(path_string(repo.path()), create_empty_options());

    assert_eq!(result, Err(CoreError::Config));
    let after = fs::read_to_string(&root_overview_path).expect("read overview after retry");
    assert_eq!(after, before);
    let config = load_config(path_string(repo.path())).expect("load config after retry");
    assert_eq!(config.repo_path, path_string(repo.path()));
}

#[test]
fn init_empty_repo_recovers_recoverable_stale_init_directory_before_retry() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let stale_init = repo.path().join(".areamatrix.init-stale");
    fs::create_dir(&stale_init).expect("create stale init directory");
    fs::create_dir(stale_init.join("staging")).expect("create stale staging directory");
    fs::create_dir(stale_init.join("archives")).expect("create stale archives directory");
    fs::create_dir(stale_init.join("generated")).expect("create stale generated directory");
    fs::write(stale_init.join("generated/root.md"), "partial overview")
        .expect("write stale generated overview");
    fs::write(stale_init.join("classifier.yaml"), "version: 1\n").expect("write stale classifier");
    fs::write(stale_init.join("ignore.yaml"), "version: 1\n").expect("write stale ignore");
    fs::write(stale_init.join("index.db"), "partial").expect("write stale database placeholder");

    init_repo(path_string(repo.path()), create_empty_options())
        .expect("retry init after stale internal state");

    assert!(!stale_init.exists());
    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());
}

#[test]
fn init_empty_repo_preserves_non_recoverable_stale_init_contents() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let stale_init = repo.path().join(".areamatrix.init-stale");
    fs::create_dir(&stale_init).expect("create stale init directory");
    fs::create_dir(stale_init.join("staging")).expect("create stale staging directory");
    let user_file = stale_init.join("staging/user-note.txt");
    fs::write(&user_file, "owned by user").expect("write user-owned stale content");

    let result = init_repo(path_string(repo.path()), create_empty_options());

    assert_eq!(result, Err(CoreError::Config));
    assert_eq!(
        fs::read_to_string(&user_file).expect("read preserved stale user content"),
        "owned by user"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn init_empty_repo_preserves_unknown_prefixed_directory_and_refuses_cleanup() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let user_owned = repo.path().join(".areamatrix.init-user-data");
    fs::create_dir(&user_owned).expect("create user-owned hidden directory");
    let user_file = user_owned.join("notes.txt");
    fs::write(&user_file, "owned by user").expect("write user-owned hidden file");

    let result = init_repo(path_string(repo.path()), create_empty_options());

    assert_eq!(result, Err(CoreError::Config));
    assert_eq!(
        fs::read_to_string(&user_file).expect("read preserved user-owned hidden file"),
        "owned by user"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn init_empty_repo_permission_denied_does_not_create_metadata() {
    use std::os::unix::fs::PermissionsExt;

    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let original_permissions = fs::metadata(repo.path())
        .expect("read temporary repository permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(repo.path(), readonly_permissions)
        .expect("make temporary repository read-only");

    let result = init_repo(path_string(repo.path()), create_empty_options());

    fs::set_permissions(repo.path(), original_permissions)
        .expect("restore temporary repository permissions");
    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn init_empty_repo_can_create_default_category_directories() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let mut options = create_empty_options();
    options.create_default_categories = true;

    init_repo(path_string(repo.path()), options).expect("initialize with categories");

    for slug in ["docs", "code", "design", "media", "finance", "inbox"] {
        assert!(repo.path().join(slug).is_dir(), "missing category {slug}");
    }
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());

    let tree_json =
        list_tree_json(path_string(repo.path()), "zh-Hans".to_owned()).expect("list category tree");
    let tree: Value = serde_json::from_str(&tree_json).expect("parse tree json");
    let children = tree["children"]
        .as_array()
        .expect("tree children should be an array");
    let names = children
        .iter()
        .filter_map(|child| child["name"].as_str())
        .collect::<Vec<_>>();
    assert_eq!(
        names,
        vec!["code", "design", "docs", "finance", "inbox", "media"]
    );
}

#[test]
fn init_empty_repo_root_areamatrix_output_is_explicit_and_does_not_create_readme() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let mut options = create_empty_options();
    options.overview_output = OverviewOutput::RootAreaMatrixFile;

    init_repo(path_string(repo.path()), options).expect("initialize with root overview entry");

    let root_entry =
        fs::read_to_string(repo.path().join("AREAMATRIX.md")).expect("read root AREAMATRIX.md");
    assert!(root_entry.contains("AREAMATRIX:BEGIN"));
    assert!(root_entry.contains("AREAMATRIX:END"));
    assert!(!repo.path().join("README.md").exists());
}
