use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_files, map_core_error, save_classifier_rule, ClassifierRule, CoreError,
    ErrorKind, ErrorMappingInput, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;

#[derive(Debug, Eq, PartialEq)]
struct RuleFailureSnapshot {
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
        },
    )
    .expect("initialize repository");
    repo
}

fn classifier_path(repo: &Path) -> PathBuf {
    repo.join(".areamatrix/classifier.yaml")
}

fn keyword_rule(keyword: &str) -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec![keyword.to_owned()],
        extensions: Vec::new(),
        priority: 20,
        preview_confirmed: false,
    }
}

fn snapshot(repo: &Path) -> RuleFailureSnapshot {
    RuleFailureSnapshot {
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

fn assert_error_kind(error: CoreError, expected: ErrorKind) {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, expected);
    assert_eq!(map_core_error(mapping_input(&error)).kind, expected);
}

fn mapping_input(error: &CoreError) -> ErrorMappingInput {
    let raw_context = error.to_error_mapping().raw_context;
    match error.kind() {
        ErrorKind::Io | ErrorKind::Db | ErrorKind::Internal => ErrorMappingInput {
            kind: error.kind(),
            path: None,
            reason: None,
            message: Some(raw_context),
        },
        ErrorKind::Config | ErrorKind::Classify => ErrorMappingInput {
            kind: error.kind(),
            path: None,
            reason: Some(raw_context),
            message: None,
        },
        ErrorKind::Conflict
        | ErrorKind::DuplicateFile
        | ErrorKind::FileNotFound
        | ErrorKind::ExpiredAction
        | ErrorKind::RepoNotInitialized
        | ErrorKind::InvalidPath
        | ErrorKind::ICloudPlaceholder
        | ErrorKind::StagingRecoveryRequired
        | ErrorKind::PermissionDenied => ErrorMappingInput {
            kind: error.kind(),
            path: Some(raw_context),
            reason: None,
            message: None,
        },
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

fn default_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: Some(false),
        imported_after: None,
        imported_before: None,
        limit: 50,
        offset: 0,
    }
}

#[test]
fn classifier_rule_save_failure_recovery_empty_and_invalid_inputs_are_config_without_writes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before = snapshot(repo.path());

    for rule in [
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: Vec::new(),
            extensions: Vec::new(),
            priority: 0,
            preview_confirmed: false,
        },
        ClassifierRule {
            target_category: "Finance".to_owned(),
            keywords: vec!["newkw".to_owned()],
            extensions: Vec::new(),
            priority: 0,
            preview_confirmed: false,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec!["newkw".to_owned()],
            extensions: vec![".pdf".to_owned()],
            priority: 0,
            preview_confirmed: false,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec!["newkw".to_owned()],
            extensions: Vec::new(),
            priority: 1001,
            preview_confirmed: false,
        },
    ] {
        let error = save_classifier_rule(path_string(repo.path()), rule)
            .expect_err("invalid classifier rule should fail");
        assert_error_kind(error, ErrorKind::Config);
    }

    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_save_failure_recovery_unknown_duplicate_broad_and_schema_fail_cleanly() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let cases = [
        ClassifierRule {
            target_category: "unknown".to_owned(),
            keywords: vec!["newkw".to_owned()],
            extensions: Vec::new(),
            priority: 0,
            preview_confirmed: false,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: vec!["invoice".to_owned()],
            extensions: Vec::new(),
            priority: 0,
            preview_confirmed: false,
        },
        ClassifierRule {
            target_category: "finance".to_owned(),
            keywords: Vec::new(),
            extensions: vec!["pdf".to_owned()],
            priority: 0,
            preview_confirmed: false,
        },
    ];
    for rule in cases {
        let error = save_classifier_rule(path_string(repo.path()), rule)
            .expect_err("invalid semantic classifier rule should fail");
        assert_error_kind(error, ErrorKind::Config);
        assert_eq!(snapshot(repo.path()), before);
    }

    fs::write(
        classifier_path(repo.path()),
        "version: 1\ndefault: missing\ncategories:\n  - slug: finance\n",
    )
    .expect("write invalid classifier config");
    let invalid_schema = snapshot(repo.path());

    let error = save_classifier_rule(path_string(repo.path()), keyword_rule("newkw"))
        .expect_err("invalid classifier schema should fail");

    assert_error_kind(error, ErrorKind::Config);
    assert_eq!(snapshot(repo.path()), invalid_schema);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_save_failure_recovery_classifier_path_directory_is_io_without_writes() {
    let repo = initialized_repo();
    let before_user_files = user_visible_files(repo.path());
    fs::remove_file(classifier_path(repo.path())).expect("remove classifier file");
    fs::create_dir(classifier_path(repo.path())).expect("replace classifier with directory");
    let before = metadata_entries(repo.path());

    let error = save_classifier_rule(path_string(repo.path()), keyword_rule("newkw"))
        .expect_err("directory classifier path should fail");

    assert_error_kind(error, ErrorKind::Io);
    assert_eq!(metadata_entries(repo.path()), before);
    assert_eq!(user_visible_files(repo.path()), before_user_files);
    assert!(classifier_path(repo.path()).is_dir());
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_save_failure_recovery_corrupted_db_is_explicit_without_file_writes() {
    let repo = initialized_repo();
    fs::write(
        repo.path().join(".areamatrix/index.db"),
        b"not-a-sqlite-database",
    )
    .expect("corrupt repository database");
    let before = snapshot(repo.path());

    let error = list_files(path_string(repo.path()), default_filter())
        .expect_err("corrupted DB should fail explicitly");

    assert_error_kind(error, ErrorKind::Db);
    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_save_failure_recovery_no_ai_network_or_user_file_side_effects() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before_user_files = user_visible_files(repo.path());

    let saved = save_classifier_rule(path_string(repo.path()), keyword_rule("clientz"))
        .expect("save valid keyword rule");

    assert_eq!(saved, keyword_rule("clientz"));
    assert_eq!(user_visible_files(repo.path()), before_user_files);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/ai.log").exists());
    assert!(!repo.path().join(".areamatrix/network.log").exists());
    assert!(!repo
        .path()
        .join(".areamatrix/generated")
        .join("ai")
        .exists());
    assert_no_classifier_temp_files(repo.path());
}

#[cfg(unix)]
#[test]
fn classifier_rule_save_failure_recovery_permission_denied_keeps_original_config() {
    use std::{io, os::unix::fs::PermissionsExt};

    let repo = initialized_repo();
    let classifier = classifier_path(repo.path());
    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o555);
    fs::set_permissions(&metadata_dir, blocked_permissions).expect("make metadata readonly");

    let probe = metadata_dir.join("permission-probe.tmp");
    match fs::write(&probe, b"probe") {
        Ok(()) => {
            fs::remove_file(&probe).expect("remove permission probe");
            fs::set_permissions(&metadata_dir, original_permissions)
                .expect("restore metadata permissions");
            return;
        }
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {}
        Err(_) => {
            fs::set_permissions(&metadata_dir, original_permissions)
                .expect("restore metadata permissions");
            return;
        }
    }
    let before = fs::read_to_string(&classifier).expect("read classifier before failure");

    let result = save_classifier_rule(path_string(repo.path()), keyword_rule("readonlykw"));

    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");

    let error = result.expect_err("readonly metadata directory should fail");
    assert_error_kind(error, ErrorKind::PermissionDenied);
    assert_eq!(
        fs::read_to_string(&classifier).expect("read classifier after failure"),
        before
    );
    assert_no_classifier_temp_files(repo.path());
}
