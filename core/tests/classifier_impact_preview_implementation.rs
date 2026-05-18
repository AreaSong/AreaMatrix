use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, preview_classifier_rule_impact, ClassifierRule, CoreError, OverviewOutput,
    RepoInitMode, RepoInitOptions, RuleImpactConflictKind, RuleImpactMatchReason, RuleImpactStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct ImpactSnapshot {
    classifier_yaml: String,
    file_rows: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    notes_count: i64,
    tags_count: i64,
    undo_count: i64,
    generated_paths: Vec<String>,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn rule() -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec!["clientx".to_owned(), "合同x".to_owned()],
        extensions: vec!["csv".to_owned()],
        priority: 20,
        preview_confirmed: false,
    }
}

fn insert_repo_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&file_path, b"classifier impact fixture").expect("write fixture file");
    insert_file_row(repo, relative_path, relative_path, category, "copied", None)
}

fn insert_indexed_file(repo: &Path, source_path: &Path, category: &str) -> i64 {
    fs::write(source_path, b"classifier impact indexed fixture").expect("write indexed source");
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
                ?1, ?2, ?2, ?3, 26,
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

fn snapshot(repo: &Path) -> ImpactSnapshot {
    ImpactSnapshot {
        classifier_yaml: fs::read_to_string(repo.join(".areamatrix/classifier.yaml"))
            .expect("read classifier yaml"),
        file_rows: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        notes_count: table_count(repo, "notes"),
        tags_count: table_count(repo, "tags"),
        undo_count: table_count(repo, "undo_actions"),
        generated_paths: generated_paths(repo),
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

fn generated_paths(repo: &Path) -> Vec<String> {
    let generated = repo.join(".areamatrix/generated");
    let mut paths: Vec<String> = fs::read_dir(generated)
        .expect("read generated directory")
        .map(|entry| {
            entry
                .expect("read generated entry")
                .path()
                .strip_prefix(repo)
                .expect("generated path remains inside repo")
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    paths.sort();
    paths
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

fn sample_status(report: &area_matrix_core::RuleImpactReport, file_id: i64) -> RuleImpactStatus {
    report
        .samples
        .iter()
        .find(|sample| sample.file_id == file_id)
        .expect("sample exists")
        .status
        .clone()
}

#[test]
fn classifier_impact_preview_implementation_reads_metadata_and_has_no_side_effects() {
    let repo = initialized_repo();
    let keyword_id = insert_repo_file(repo.path(), "docs/clientx-report.txt", "docs");
    let extension_id = insert_repo_file(repo.path(), "docs/archive.csv", "docs");
    let both_id = insert_repo_file(repo.path(), "docs/合同x.csv", "docs");
    let already_id = insert_repo_file(repo.path(), "finance/clientx-paid.txt", "finance");
    insert_repo_file(repo.path(), "docs/readme.txt", "docs");
    let before = snapshot(repo.path());

    let report =
        preview_classifier_rule_impact(path_string(repo.path()), rule()).expect("preview impact");

    assert_eq!(report.rule, rule());
    assert_eq!(report.affected_file_count, 4);
    assert_eq!(report.will_update_count, 3);
    assert_eq!(report.already_correct_count, 1);
    assert_eq!(report.needs_review_count, 0);
    assert_eq!(report.conflict_count, 0);
    assert!(report.can_apply);
    assert_eq!(report.apply_blocked_reason, None);
    assert_eq!(
        sample_status(&report, keyword_id),
        RuleImpactStatus::WillUpdate
    );
    assert_eq!(
        sample_status(&report, extension_id),
        RuleImpactStatus::WillUpdate
    );
    assert_eq!(
        sample_status(&report, both_id),
        RuleImpactStatus::WillUpdate
    );
    assert_eq!(
        sample_status(&report, already_id),
        RuleImpactStatus::AlreadyCorrect
    );

    let both = report
        .samples
        .iter()
        .find(|sample| sample.file_id == both_id)
        .expect("both-match sample exists");
    assert_eq!(
        both.match_reasons,
        vec![
            RuleImpactMatchReason::Keyword,
            RuleImpactMatchReason::Extension
        ]
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_surfaces_missing_index_only_and_conflicts() {
    let repo = initialized_repo();
    let indexed_root = tempfile::tempdir().expect("create indexed source root");
    let indexed_id = insert_indexed_file(
        repo.path(),
        &indexed_root.path().join("clientx-indexed.txt"),
        "docs",
    );
    let missing_id = insert_repo_file(repo.path(), "docs/clientx-missing.txt", "docs");
    fs::remove_file(repo.path().join("docs/clientx-missing.txt")).expect("remove backing file");
    let conflict_id = insert_repo_file(repo.path(), "docs/clientx-conflict.txt", "docs");
    fs::create_dir_all(repo.path().join("finance")).expect("create finance dir");
    fs::write(
        repo.path().join("finance/clientx-conflict.txt"),
        b"existing target",
    )
    .expect("write conflicting target");
    let before = snapshot(repo.path());

    let report =
        preview_classifier_rule_impact(path_string(repo.path()), rule()).expect("preview impact");

    assert_eq!(report.affected_file_count, 3);
    assert_eq!(report.will_update_count, 0);
    assert_eq!(report.already_correct_count, 0);
    assert_eq!(report.needs_review_count, 1);
    assert_eq!(report.conflict_count, 2);
    assert!(report.needs_review);
    assert!(!report.can_apply);
    assert_eq!(
        sample_status(&report, indexed_id),
        RuleImpactStatus::IndexOnly
    );
    assert_eq!(
        sample_status(&report, missing_id),
        RuleImpactStatus::Missing
    );
    assert_eq!(
        sample_status(&report, conflict_id),
        RuleImpactStatus::Conflict
    );
    assert!(report
        .conflicts
        .iter()
        .any(|conflict| conflict.kind == RuleImpactConflictKind::MissingFile));
    assert!(report.conflicts.iter().any(|conflict| conflict.kind
        == RuleImpactConflictKind::NameConflict
        && conflict.conflicting_path.as_deref() == Some("finance/clientx-conflict.txt")));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_warns_for_broad_rules_and_limits_samples() {
    let repo = initialized_repo();
    for index in 0..25 {
        insert_repo_file(repo.path(), &format!("docs/clientx-{index:02}.txt"), "docs");
    }

    let report =
        preview_classifier_rule_impact(path_string(repo.path()), rule()).expect("preview impact");

    assert_eq!(report.affected_file_count, 25);
    assert_eq!(report.will_update_count, 25);
    assert!(report.warning_required);
    assert!(report.warning.is_some());
    assert_eq!(report.sample_limit, 50);
    assert_eq!(report.samples.len(), 25);
}

#[test]
fn classifier_impact_preview_implementation_rejects_invalid_config_and_metadata() {
    let repo = initialized_repo();
    fs::write(
        repo.path().join(".areamatrix/classifier.yaml"),
        "version: 1\ndefault: missing\ncategories:\n  - slug: finance\n",
    )
    .expect("write invalid classifier config");

    assert!(matches!(
        preview_classifier_rule_impact(path_string(repo.path()), rule()),
        Err(CoreError::Config { .. })
    ));

    let plain_dir = tempfile::tempdir().expect("create plain directory");
    assert!(matches!(
        preview_classifier_rule_impact(path_string(plain_dir.path()), rule()),
        Err(CoreError::Db { .. })
    ));
}
