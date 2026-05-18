use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, preview_classifier_rule_impact, ClassifierRule, CoreError, CoreResult,
    OverviewOutput, RepoInitMode, RepoInitOptions, RuleImpactConflictKind, RuleImpactReport,
    RuleImpactStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-14-classifier-impact-preview.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_IMPACT_RS: &str = include_str!("../src/classifier_impact.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

#[derive(Debug, Eq, PartialEq)]
struct PreviewSnapshot {
    classifier_yaml: String,
    file_rows: Vec<(i64, String, String, String)>,
    user_visible_paths: Vec<String>,
    change_log_count: i64,
    notes_count: i64,
    tags_count: i64,
    undo_count: i64,
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
        keywords: vec!["clientz".to_owned()],
        extensions: vec!["csv".to_owned()],
        priority: 15,
        preview_confirmed: false,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_repo_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"classifier impact validation fixture")
        .expect("write fixture file");
    insert_file_row(repo, relative_path, relative_path, category, "copied", None)
}

fn insert_indexed_file(repo: &Path, source_path: &Path, category: &str) -> i64 {
    fs::write(source_path, b"classifier impact indexed validation fixture")
        .expect("write indexed source");
    let source = path_string(source_path);
    insert_file_row(repo, &source, &source, category, "indexed", Some(&source))
}

fn insert_file_row(
    repo: &Path,
    path: &str,
    name_path: &str,
    category: &str,
    storage_mode: &str,
    source_path: Option<&str>,
) -> i64 {
    let current_name = name_path
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
                ?1, ?2, ?2, ?3, 36,
                ?4, ?5, 'imported', ?6,
                100, 100, 'active'
             )",
            params![
                path,
                current_name,
                category,
                format!("{:064x}", path.len()),
                storage_mode,
                source_path,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn snapshot(repo: &Path) -> PreviewSnapshot {
    PreviewSnapshot {
        classifier_yaml: fs::read_to_string(repo.join(".areamatrix/classifier.yaml"))
            .expect("read classifier yaml"),
        file_rows: file_rows(repo),
        user_visible_paths: user_visible_paths(repo),
        change_log_count: table_count(repo, "change_log"),
        notes_count: table_count(repo, "notes"),
        tags_count: table_count(repo, "tags"),
        undo_count: table_count(repo, "undo_actions"),
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

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn sample_status(report: &RuleImpactReport, file_id: i64) -> RuleImpactStatus {
    report
        .samples
        .iter()
        .find(|sample| sample.file_id == file_id)
        .expect("sample exists")
        .status
        .clone()
}

#[test]
fn classifier_impact_preview_validation_locks_api_udl_and_rust_contract() {
    fn assert_signature(_: fn(String, ClassifierRule) -> CoreResult<RuleImpactReport>) {}
    assert_signature(preview_classifier_rule_impact);

    for fragment in [
        "preview_classifier_rule_impact(repo_path, rule) -> RuleImpactReport",
        "受影响文件数量、样例、冲突、needs review。",
        "仅预览不改变文件分类。",
        "影响量超过阈值必须提示。",
        "冲突或 needs review 时不能直接批量应用。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    assert_contains(
        CONTROL_MAP,
        "| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读",
    );
    assert_contains(TESTING_DOC, "`core/classify` | ≥ 90%");

    for fragment in [
        "RuleImpactReport preview_classifier_rule_impact(string repo_path, ClassifierRule rule);",
        "dictionary RuleImpactReport",
        "i64 affected_file_count;",
        "i64 will_update_count;",
        "i64 needs_review_count;",
        "sequence<RuleImpactSample> samples;",
        "sequence<RuleImpactConflict> conflicts;",
        "boolean warning_required;",
        "boolean can_apply;",
        "string? apply_blocked_reason;",
        "enum RuleImpactStatus",
        "\"IndexOnly\"",
        "enum RuleImpactConflictKind",
        "\"NameConflict\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "Previews C2-14 classifier rule impact for S2-18.",
        "must not save the rule",
        "move files",
        "write undo/change-log state",
        "CoreError::Config",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    assert_contains(LIB_RS, "preview_classifier_rule_impact");
    assert_contains(CLASSIFIER_IMPACT_RS, "pub fn preview_classifier_rule_impact(");
}

#[test]
fn classifier_impact_preview_validation_success_is_read_only_and_warns_when_broad() {
    let repo = initialized_repo();
    for index in 0..21 {
        insert_repo_file(repo.path(), &format!("docs/clientz-{index:02}.txt"), "docs");
    }
    let before = snapshot(repo.path());

    let report =
        preview_classifier_rule_impact(path_string(repo.path()), rule()).expect("preview impact");

    assert_eq!(report.affected_file_count, 21);
    assert_eq!(report.will_update_count, 21);
    assert_eq!(report.already_correct_count, 0);
    assert_eq!(report.needs_review_count, 0);
    assert_eq!(report.conflict_count, 0);
    assert!(report.warning_required);
    assert!(report.warning.is_some());
    assert!(report.can_apply);
    assert_eq!(report.apply_blocked_reason, None);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_validation_review_and_conflicts_block_direct_apply() {
    let repo = initialized_repo();
    let indexed_root = tempfile::tempdir().expect("create indexed source root");
    let indexed_id = insert_indexed_file(
        repo.path(),
        &indexed_root.path().join("clientz-indexed.txt"),
        "docs",
    );
    let conflict_id = insert_repo_file(repo.path(), "docs/clientz-conflict.txt", "docs");
    fs::create_dir_all(repo.path().join("finance")).expect("create finance directory");
    fs::write(
        repo.path().join("finance/clientz-conflict.txt"),
        b"existing target",
    )
    .expect("write conflicting target");
    let before = snapshot(repo.path());

    let report =
        preview_classifier_rule_impact(path_string(repo.path()), rule()).expect("preview impact");

    assert_eq!(report.affected_file_count, 2);
    assert_eq!(report.will_update_count, 0);
    assert_eq!(report.needs_review_count, 1);
    assert_eq!(report.conflict_count, 1);
    assert!(report.needs_review);
    assert!(!report.can_apply);
    assert_eq!(
        sample_status(&report, indexed_id),
        RuleImpactStatus::IndexOnly
    );
    assert_eq!(
        sample_status(&report, conflict_id),
        RuleImpactStatus::Conflict
    );
    assert!(report.conflicts.iter().any(|conflict| conflict.kind
        == RuleImpactConflictKind::NameConflict
        && conflict.conflicting_path.as_deref() == Some("finance/clientz-conflict.txt")));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_validation_failure_paths_return_config_or_db_without_mutation() {
    let repo = initialized_repo();
    insert_repo_file(repo.path(), "docs/clientz.pdf", "docs");
    let before = snapshot(repo.path());

    let mut invalid_target = rule();
    invalid_target.target_category = "unknown".to_owned();
    assert!(matches!(
        preview_classifier_rule_impact(path_string(repo.path()), invalid_target),
        Err(CoreError::Config { .. })
    ));

    fs::write(
        repo.path().join(".areamatrix/index.db"),
        b"not a sqlite database",
    )
    .expect("corrupt index database");
    assert!(matches!(
        preview_classifier_rule_impact(path_string(repo.path()), rule()),
        Err(CoreError::Db { .. })
    ));
    assert_eq!(user_visible_paths(repo.path()), before.user_visible_paths);
    assert_eq!(
        fs::read_to_string(repo.path().join(".areamatrix/classifier.yaml"))
            .expect("read classifier yaml after failure"),
        before.classifier_yaml
    );
}
