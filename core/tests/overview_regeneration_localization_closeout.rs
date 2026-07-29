use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    commit_overview_regeneration, get_overview_language_status, init_repo,
    prepare_overview_regeneration, start_overview_regeneration, ContentLocale,
    OverviewLanguageState, OverviewOutput, OverviewRegenerationPlan,
    OverviewRegenerationStartRequest, OverviewRegenerationStatus, RepoInitMode, RepoInitOptions,
    RepositoryLocalePolicy,
};
use rusqlite::Connection;

const GENERATED_TARGETS: [&str; 7] = [
    ".areamatrix/generated/nodes/code.md",
    ".areamatrix/generated/nodes/design.md",
    ".areamatrix/generated/nodes/docs.md",
    ".areamatrix/generated/nodes/finance.md",
    ".areamatrix/generated/nodes/inbox.md",
    ".areamatrix/generated/nodes/media.md",
    ".areamatrix/generated/root.md",
];

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialize_fixture() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create repository fixture");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: true,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: RepositoryLocalePolicy::FollowInterface,
            content_locale: ContentLocale::En,
        },
    )
    .expect("initialize repository fixture");

    fs::write(repo.path().join("README.md"), b"user-owned readme\n").expect("write README fixture");
    fs::write(repo.path().join("AREAMATRIX.md"), b"user-owned overview\n")
        .expect("write root AREAMATRIX fixture");
    fs::write(repo.path().join("ordinary.txt"), b"ordinary user bytes\n")
        .expect("write ordinary file fixture");
    let nested = repo.path().join("nested/user/content");
    fs::create_dir_all(&nested).expect("create nested user directory");
    fs::write(nested.join("notes.md"), b"nested user bytes\n")
        .expect("write nested user file fixture");
    repo
}

fn collect_files(root: &Path, current: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
    if !current.exists() {
        return;
    }
    for entry in fs::read_dir(current).expect("read snapshot directory") {
        let entry = entry.expect("read snapshot entry");
        let path = entry.path();
        if current == root && entry.file_name() == ".areamatrix" {
            continue;
        }
        let file_type = entry.file_type().expect("read snapshot file type");
        if file_type.is_dir() {
            collect_files(root, &path, files);
        } else if file_type.is_file() {
            let relative = path
                .strip_prefix(root)
                .expect("snapshot path stays under root")
                .to_path_buf();
            files.insert(relative, fs::read(path).expect("read snapshot file"));
        }
    }
}

fn user_file_snapshot(repo: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut files = BTreeMap::new();
    collect_files(repo, repo, &mut files);
    files
}

fn tree_snapshot(repo: &Path, relative_root: &str) -> BTreeMap<PathBuf, Vec<u8>> {
    let root = repo.join(relative_root);
    let mut files = BTreeMap::new();
    collect_files(&root, &root, &mut files);
    files
}

fn generated_target_snapshot(repo: &Path) -> BTreeMap<&'static str, Vec<u8>> {
    GENERATED_TARGETS
        .iter()
        .map(|relative| {
            (
                *relative,
                fs::read(repo.join(relative)).expect("read generated target"),
            )
        })
        .collect()
}

fn start_request(plan: &OverviewRegenerationPlan) -> OverviewRegenerationStartRequest {
    OverviewRegenerationStartRequest {
        operation_id: plan.operation_id.clone(),
        plan_token: plan.plan_token.clone(),
        expected_repository_revision: plan.repository_revision,
        confirmed: true,
    }
}

fn journal_paths(repo: &Path, operation_id: &str) -> Vec<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare(
            "SELECT relative_path FROM overview_regeneration_items
             WHERE operation_id = ?1 ORDER BY relative_path",
        )
        .expect("prepare journal query");
    statement
        .query_map([operation_id], |row| row.get(0))
        .expect("query journal paths")
        .map(|row| row.expect("read journal path"))
        .collect()
}

fn assert_database_integrity(repo: &Path) {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let integrity: String = connection
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("run SQLite integrity check");
    assert_eq!(integrity, "ok");
}

#[test]
fn bilingual_regeneration_commits_all_generated_targets_without_touching_user_files() {
    let repo = initialize_fixture();
    let user_files_before = user_file_snapshot(repo.path());
    let expected_paths = GENERATED_TARGETS.map(str::to_owned).to_vec();

    for locale in [ContentLocale::ZhHans, ContentLocale::En] {
        let generated_before = generated_target_snapshot(repo.path());
        let staging_before = tree_snapshot(repo.path(), ".areamatrix/staging/overview");

        let plan = prepare_overview_regeneration(path_string(repo.path()), locale.clone())
            .expect("prepare localized overview regeneration");
        assert_eq!(plan.target_count, 7);
        assert!(!plan.includes_root_areamatrix_file);
        assert_eq!(generated_target_snapshot(repo.path()), generated_before);
        assert_eq!(
            tree_snapshot(repo.path(), ".areamatrix/staging/overview"),
            staging_before
        );

        let staged = start_overview_regeneration(path_string(repo.path()), start_request(&plan))
            .expect("start localized overview regeneration");
        assert_eq!(staged.status, OverviewRegenerationStatus::ReadyToCommit);
        assert_eq!(staged.target_count, 7);
        assert_eq!(staged.staged_count, 7);
        assert_eq!(generated_target_snapshot(repo.path()), generated_before);
        assert_eq!(
            journal_paths(repo.path(), &plan.operation_id),
            expected_paths
        );

        let completed =
            commit_overview_regeneration(path_string(repo.path()), plan.operation_id.clone())
                .expect("commit localized overview regeneration");
        assert_eq!(completed.status, OverviewRegenerationStatus::Completed);
        assert_eq!(completed.target_count, 7);
        assert_eq!(completed.applied_count, 7);

        let language_status = get_overview_language_status(path_string(repo.path()), locale)
            .expect("read overview language status");
        assert_eq!(language_status.state, OverviewLanguageState::Synchronized);
        assert_eq!(language_status.target_count, 7);
        assert_eq!(language_status.known_target_count, 7);
        assert_eq!(user_file_snapshot(repo.path()), user_files_before);
        assert_database_integrity(repo.path());
    }
}
