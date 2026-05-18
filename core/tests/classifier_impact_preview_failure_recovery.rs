use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, map_core_error, preview_classifier_rule_impact, ClassifierRule, CoreError,
    ErrorKind, ErrorMappingInput, ErrorRecoverability, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct PreviewSafetySnapshot {
    classifier_yaml: String,
    file_rows: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    undo_count: i64,
    user_visible_paths: Vec<String>,
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

fn rule() -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec!["clientx".to_owned()],
        extensions: vec!["pdf".to_owned()],
        priority: 0,
        preview_confirmed: false,
    }
}

fn insert_file_row(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"classifier impact failure fixture").expect("write fixture file");
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path includes filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 34,
                ?4, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn snapshot(repo: &Path) -> PreviewSafetySnapshot {
    PreviewSafetySnapshot {
        classifier_yaml: fs::read_to_string(repo.join(".areamatrix/classifier.yaml"))
            .expect("read classifier yaml"),
        file_rows: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        undo_count: table_count(repo, "undo_actions"),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count metadata rows")
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path remains inside repo")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn assert_config_error(result: Result<area_matrix_core::RuleImpactReport, CoreError>) {
    let error = result.expect_err("invalid impact preview input should fail");
    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Config);
}

fn assert_db_error(result: Result<area_matrix_core::RuleImpactReport, CoreError>) {
    let error = result.expect_err("metadata failure should fail");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
}

#[test]
fn classifier_impact_failure_edge_empty_repo_is_read_only_empty_state() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let report = preview_classifier_rule_impact(path_string(repo.path()), rule())
        .expect("empty impact preview should succeed");

    assert_eq!(report.affected_file_count, 0);
    assert_eq!(report.will_update_count, 0);
    assert_eq!(report.already_correct_count, 0);
    assert_eq!(report.needs_review_count, 0);
    assert_eq!(report.conflict_count, 0);
    assert!(!report.can_apply);
    assert_eq!(
        report.apply_blocked_reason.as_deref(),
        Some("No matched files need category changes")
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_failure_edge_invalid_inputs_return_config_without_mutation() {
    let repo = initialized_repo();
    insert_file_row(repo.path(), "docs/clientx.pdf", "docs");
    let before = snapshot(repo.path());

    assert_config_error(preview_classifier_rule_impact(String::new(), rule()));

    let mut bad_category = rule();
    bad_category.target_category = "bad category".to_owned();
    assert_config_error(preview_classifier_rule_impact(
        path_string(repo.path()),
        bad_category,
    ));

    let mut empty_basis = rule();
    empty_basis.keywords.clear();
    empty_basis.extensions.clear();
    assert_config_error(preview_classifier_rule_impact(
        path_string(repo.path()),
        empty_basis,
    ));

    let mut dotted_extension = rule();
    dotted_extension.extensions = vec![".pdf".to_owned()];
    assert_config_error(preview_classifier_rule_impact(
        path_string(repo.path()),
        dotted_extension,
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_failure_edge_db_errors_do_not_write_or_create_half_products() {
    let repo = initialized_repo();
    insert_file_row(repo.path(), "docs/clientx.pdf", "docs");
    let before = snapshot(repo.path());
    fs::write(
        repo.path().join(".areamatrix/index.db"),
        b"not a sqlite database",
    )
    .expect("corrupt index database for failure edge");

    assert_db_error(preview_classifier_rule_impact(
        path_string(repo.path()),
        rule(),
    ));

    assert_eq!(
        fs::read(repo.path().join("docs/clientx.pdf")).expect("read user file"),
        b"classifier impact failure fixture"
    );
    assert_eq!(user_visible_paths(repo.path()), before.user_visible_paths);
    assert_eq!(
        fs::read_to_string(repo.path().join(".areamatrix/classifier.yaml"))
            .expect("read classifier config after DB failure"),
        before.classifier_yaml
    );
}

#[test]
fn classifier_impact_failure_edge_unreadable_metadata_path_is_db_error_without_mutation() {
    let repo = initialized_repo();
    let mut invalid_path_rule = rule();
    invalid_path_rule.keywords = vec!["secret".to_owned()];
    insert_file_row(repo.path(), "docs/secret.pdf", "docs");
    open_db(repo.path())
        .execute(
            "UPDATE files SET path = '../secret.pdf' WHERE current_name = 'secret.pdf'",
            [],
        )
        .expect("make metadata path invalid");
    let before = snapshot(repo.path());

    assert_db_error(preview_classifier_rule_impact(
        path_string(repo.path()),
        invalid_path_rule,
    ));

    assert_eq!(snapshot(repo.path()), before);
    assert!(repo.path().join("docs/secret.pdf").is_file());
}

#[test]
fn classifier_impact_failure_edge_permissions_are_not_silently_downgraded() {
    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("/restricted/repo".to_owned()),
        reason: None,
        message: None,
    });

    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

#[test]
fn classifier_impact_failure_edge_no_privacy_ai_or_remote_side_effects_are_present() {
    let source = include_str!("../src/classifier_impact.rs");
    for forbidden in [
        "reqwest",
        "http::",
        "https://",
        "api_key",
        "token",
        "tracing::",
        "std::env::var",
        "write(",
        "rename(",
        "remove_file(",
    ] {
        assert!(
            !source.contains(forbidden),
            "classifier impact preview must remain local read-only and must not contain `{forbidden}`"
        );
    }
}
