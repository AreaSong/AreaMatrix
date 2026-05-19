use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    create_classifier_rule, delete_classifier_rule, init_repo, list_classifier_rules,
    map_core_error, update_classifier_rule, ClassifierRuleCreateRequest,
    ClassifierRuleDeleteRequest, ClassifierRuleUpdate, CoreError, ErrorKind, ErrorMappingInput,
    ErrorRecoverability, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;

#[derive(Debug, Eq, PartialEq)]
struct EditorFailureSnapshot {
    classifier_payload: Option<Vec<u8>>,
    db_payload: Vec<u8>,
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

fn db_path(repo: &Path) -> PathBuf {
    repo.join(".areamatrix/index.db")
}

fn update_request() -> ClassifierRuleUpdate {
    ClassifierRuleUpdate {
        rule_id: "finance".to_owned(),
        slug: "contracts".to_owned(),
        display_name: "Contracts".to_owned(),
        description: "Signed client contracts".to_owned(),
        extensions: vec!["pdf".to_owned(), "docx".to_owned()],
        keywords: vec!["agreement".to_owned(), "合同".to_owned()],
        priority: 30,
        naming_template: Some("{stem}-{date}".to_owned()),
        preview_confirmed: true,
    }
}

fn create_request() -> ClassifierRuleCreateRequest {
    ClassifierRuleCreateRequest {
        slug: "tax".to_owned(),
        display_name: "Tax".to_owned(),
        description: "Tax documents".to_owned(),
        extensions: vec!["pdf".to_owned()],
        keywords: vec!["tax".to_owned()],
        priority: 20,
        naming_template: Some("{stem}".to_owned()),
    }
}

fn delete_request(rule_id: &str) -> ClassifierRuleDeleteRequest {
    ClassifierRuleDeleteRequest {
        rule_id: rule_id.to_owned(),
        replacement_category: Some("inbox".to_owned()),
        preview_confirmed: true,
    }
}

fn snapshot(repo: &Path) -> EditorFailureSnapshot {
    EditorFailureSnapshot {
        classifier_payload: fs::read(classifier_path(repo)).ok(),
        db_payload: fs::read(db_path(repo)).expect("read repository database"),
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
            .expect("path remains under metadata root")
            .to_path_buf();
        entries.push(relative);
        if path.is_dir() {
            collect_paths(root, &path, entries);
        }
    }
}

fn collect_user_visible_files(root: &Path, current: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let path = entry.expect("read repository entry").path();
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

fn assert_error_kind<T: std::fmt::Debug>(result: Result<T, CoreError>, expected: ErrorKind) {
    let error = result.expect_err("operation should fail");
    assert_eq!(error.to_error_mapping().kind, expected);
    assert_eq!(map_core_error(mapping_input(&error)).kind, expected);
    assert!(
        !error.to_error_mapping().raw_context.is_empty(),
        "classifier rule editor errors must keep observable context"
    );
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
        ErrorKind::Config | ErrorKind::Validation | ErrorKind::Classify => ErrorMappingInput {
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

#[test]
fn classifier_rule_editor_failure_edge_empty_repo_lists_without_side_effects() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let state = list_classifier_rules(path_string(repo.path())).expect("list classifier rules");

    assert_eq!(state.default_rule_id, "inbox");
    assert!(state.rules.iter().any(|rule| rule.rule_id == "inbox"));
    assert_eq!(state.updated_rule_id, None);
    assert_eq!(state.warning, None);
    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_failure_edge_invalid_inputs_are_config_without_writes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before = snapshot(repo.path());

    assert_error_kind(list_classifier_rules(String::new()), ErrorKind::Config);
    assert_error_kind(
        list_classifier_rules(path_string(&repo.path().join(".areamatrix"))),
        ErrorKind::Config,
    );

    let mut invalid_create = create_request();
    invalid_create.slug = "Bad Category".to_owned();
    assert_error_kind(
        create_classifier_rule(path_string(repo.path()), invalid_create),
        ErrorKind::Config,
    );

    let mut duplicate_create_keyword = create_request();
    duplicate_create_keyword.keywords = vec!["tax".to_owned(), "tax".to_owned()];
    assert_error_kind(
        create_classifier_rule(path_string(repo.path()), duplicate_create_keyword),
        ErrorKind::Config,
    );

    let mut empty_id = update_request();
    empty_id.rule_id.clear();
    assert_error_kind(
        update_classifier_rule(path_string(repo.path()), empty_id),
        ErrorKind::Config,
    );

    let mut invalid_slug = update_request();
    invalid_slug.slug = "Bad Category".to_owned();
    assert_error_kind(
        update_classifier_rule(path_string(repo.path()), invalid_slug),
        ErrorKind::Config,
    );

    let mut duplicate_keyword = update_request();
    duplicate_keyword.keywords = vec!["invoice".to_owned(), "invoice".to_owned()];
    assert_error_kind(
        update_classifier_rule(path_string(repo.path()), duplicate_keyword),
        ErrorKind::Config,
    );

    let mut invalid_template = update_request();
    invalid_template.naming_template = Some("{unsupported}".to_owned());
    assert_error_kind(
        update_classifier_rule(path_string(repo.path()), invalid_template),
        ErrorKind::Config,
    );

    let mut unpreviewed_update = update_request();
    unpreviewed_update.preview_confirmed = false;
    assert_error_kind(
        update_classifier_rule(path_string(repo.path()), unpreviewed_update),
        ErrorKind::Config,
    );

    let mut missing_replacement = delete_request("finance");
    missing_replacement.replacement_category = None;
    assert_error_kind(
        delete_classifier_rule(path_string(repo.path()), missing_replacement),
        ErrorKind::Config,
    );

    let mut unpreviewed_delete = delete_request("finance");
    unpreviewed_delete.preview_confirmed = false;
    assert_error_kind(
        delete_classifier_rule(path_string(repo.path()), unpreviewed_delete),
        ErrorKind::Config,
    );

    assert_error_kind(
        delete_classifier_rule(path_string(repo.path()), delete_request("inbox")),
        ErrorKind::Config,
    );

    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_failure_edge_classifier_directory_is_io_without_half_products() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    fs::remove_file(classifier_path(repo.path())).expect("remove classifier file");
    fs::create_dir(classifier_path(repo.path())).expect("replace classifier file with directory");
    let before = snapshot(repo.path());

    assert_error_kind(
        list_classifier_rules(path_string(repo.path())),
        ErrorKind::Io,
    );
    assert_error_kind(
        create_classifier_rule(path_string(repo.path()), create_request()),
        ErrorKind::Io,
    );
    assert_error_kind(
        update_classifier_rule(path_string(repo.path()), update_request()),
        ErrorKind::Io,
    );
    assert_error_kind(
        delete_classifier_rule(path_string(repo.path()), delete_request("finance")),
        ErrorKind::Io,
    );

    assert_eq!(snapshot(repo.path()), before);
    assert!(classifier_path(repo.path()).is_dir());
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_failure_edge_error_mapping_is_structured() {
    let config = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Config,
        path: None,
        reason: Some("classifier schema invalid".to_owned()),
        message: None,
    });
    assert_eq!(config.kind, ErrorKind::Config);
    assert_eq!(
        config.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let permission = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("/restricted/.areamatrix/classifier.yaml".to_owned()),
        reason: None,
        message: None,
    });
    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let io = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Io,
        path: None,
        reason: None,
        message: Some("classifier config write failed".to_owned()),
    });
    assert_eq!(io.kind, ErrorKind::Io);
    assert_eq!(io.recoverability, ErrorRecoverability::Retryable);
}

#[test]
fn classifier_rule_editor_failure_edge_no_ai_network_or_user_file_side_effects() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    let before_user_files = user_visible_files(repo.path());

    create_classifier_rule(path_string(repo.path()), create_request())
        .expect("create classifier rule");

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

    let source = [
        include_str!("../src/classifier_rule_editor.rs"),
        include_str!("../src/classifier_rule_editor/config.rs"),
    ]
    .join("\n");
    for forbidden in [
        "reqwest",
        "http::",
        "https://",
        "api_key",
        "authorization",
        "std::env::var",
        "tracing::",
        "log::",
    ] {
        assert!(
            !source.contains(forbidden),
            "classifier rule editor must stay local and must not contain `{forbidden}`"
        );
    }
}

#[cfg(unix)]
#[test]
fn classifier_rule_editor_failure_edge_permission_denied_keeps_old_config() {
    use std::{io, os::unix::fs::PermissionsExt};

    let repo = initialized_repo();
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
    let before = snapshot(repo.path());

    let result = create_classifier_rule(path_string(repo.path()), create_request());

    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");

    assert_error_kind(result, ErrorKind::PermissionDenied);
    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}
