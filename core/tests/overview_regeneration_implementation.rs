use std::{fs, path::Path};

use area_matrix_core::{
    cancel_overview_regeneration, commit_overview_regeneration, get_overview_language_status,
    get_overview_regeneration, init_repo, prepare_overview_regeneration,
    recover_overview_regeneration_on_startup, resume_overview_regeneration,
    start_overview_regeneration, update_repo_config, ContentLocale, CoreError,
    OverviewLanguageState, OverviewOutput, OverviewRegenerationReason,
    OverviewRegenerationStartRequest, OverviewRegenerationStatus, RepoConfigPatch, RepoInitMode,
    RepoInitOptions, RepositoryLocalePolicy,
};
use rusqlite::Connection;
use sha2::Digest;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo(output: OverviewOutput) -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create repository fixture");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: true,
            overview_output: output,
            locale_policy: RepositoryLocalePolicy::FollowInterface,
            content_locale: ContentLocale::En,
        },
    )
    .expect("initialize repository fixture");
    repo
}

fn start_request(
    plan: &area_matrix_core::OverviewRegenerationPlan,
) -> OverviewRegenerationStartRequest {
    OverviewRegenerationStartRequest {
        operation_id: plan.operation_id.clone(),
        plan_token: plan.plan_token.clone(),
        expected_repository_revision: plan.repository_revision,
        confirmed: true,
    }
}

fn complete_regeneration(repo: &Path, locale: ContentLocale) -> String {
    let plan = prepare_overview_regeneration(path_string(repo), locale)
        .expect("prepare overview regeneration");
    start_overview_regeneration(path_string(repo), start_request(&plan))
        .expect("prepare overview regeneration output");
    commit_overview_regeneration(path_string(repo), plan.operation_id.clone())
        .expect("commit overview regeneration");
    plan.operation_id
}

fn operation_item_paths(repo: &Path, operation_id: &str) -> Vec<(String, String, Option<String>)> {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    let mut statement = connection
        .prepare(
            "SELECT relative_path, staging_relative_path, backup_relative_path
             FROM overview_regeneration_items WHERE operation_id = ?1 ORDER BY relative_path",
        )
        .expect("prepare journal query");
    let rows = statement
        .query_map([operation_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })
        .expect("query journal items");
    rows.map(|row| row.expect("read journal item")).collect()
}

fn force_operation_status(repo: &Path, operation_id: &str, status: &str) {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    connection
        .execute(
            "UPDATE recoverable_operations SET status = ?2 WHERE operation_id = ?1",
            (operation_id, status),
        )
        .expect("update operation status");
}

#[test]
fn full_regeneration_records_provenance_and_preserves_readme() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme = repo.path().join("README.md");
    fs::write(&readme, b"user-owned readme\n").expect("write README fixture");
    let connection = Connection::open(repo.path().join(".areamatrix/index.db"))
        .expect("open repository database");
    connection
        .execute("DELETE FROM overview_provenance", [])
        .expect("remove legacy provenance");
    drop(connection);

    let before = get_overview_language_status(path_string(repo.path()), ContentLocale::En)
        .expect("read legacy status");
    assert_eq!(before.state, OverviewLanguageState::Unknown);

    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare full regeneration");
    assert_eq!(
        plan.create_count + plan.replace_count + plan.delete_count,
        plan.target_count
    );
    assert!(plan.replace_count >= 1);
    assert!(!repo.path().join(".areamatrix/staging/overview").exists());
    let session = start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("start full regeneration");
    assert_eq!(
        session.status,
        area_matrix_core::OverviewRegenerationStatus::ReadyToCommit
    );
    let session = commit_overview_regeneration(path_string(repo.path()), plan.operation_id.clone())
        .expect("commit full regeneration");
    assert_eq!(
        session.status,
        area_matrix_core::OverviewRegenerationStatus::Completed
    );
    assert_eq!(session.applied_count, session.target_count);
    assert_eq!(
        fs::read(&readme).expect("read README"),
        b"user-owned readme\n"
    );

    let after = get_overview_language_status(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("read synchronized status");
    assert_eq!(after.state, OverviewLanguageState::Synchronized);
    assert_eq!(after.known_target_count, after.target_count);
    assert_eq!(after.missing_target_count, 0);
    assert_eq!(after.known_format_versions, vec![1]);

    let needs_regeneration =
        get_overview_language_status(path_string(repo.path()), ContentLocale::En)
            .expect("read mismatched-language status");
    assert_eq!(
        needs_regeneration.state,
        OverviewLanguageState::NeedsRegeneration
    );
    assert_eq!(
        needs_regeneration.reasons,
        vec![OverviewRegenerationReason::LocaleMismatch]
    );
}

#[test]
fn overview_language_status_distinguishes_not_generated_from_unknown() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    fs::remove_dir_all(repo.path().join(".areamatrix/generated"))
        .expect("remove generated fixture output");

    let status = get_overview_language_status(path_string(repo.path()), ContentLocale::En)
        .expect("read not-generated status");

    assert_eq!(status.state, OverviewLanguageState::NotGenerated);
    assert_eq!(status.known_target_count, 0);
    assert_eq!(status.missing_target_count, status.target_count);
}

#[test]
fn stale_plan_revision_has_zero_generated_file_writes() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let generated_root = repo.path().join(".areamatrix/generated/root.md");
    let before = fs::read(&generated_root).expect("read generated root before conflict");
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare full regeneration");

    update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: plan.repository_revision,
            icloud_warn: Some(false),
            ..RepoConfigPatch::default()
        },
    )
    .expect("advance repository revision");

    let error = start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect_err("stale plan must fail");
    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(
        fs::read(generated_root).expect("read generated root after conflict"),
        before
    );
    assert!(!repo.path().join(".areamatrix/staging/overview").exists());
}

#[test]
fn full_regeneration_removes_only_obsolete_regular_generated_nodes() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let nodes = repo.path().join(".areamatrix/generated/nodes");
    fs::create_dir_all(&nodes).expect("create generated nodes directory");
    let obsolete = nodes.join("obsolete.md");
    fs::write(&obsolete, b"old generated output\n").expect("write obsolete output");
    let readme = repo.path().join("README.md");
    fs::write(&readme, b"never touch\n").expect("write README fixture");

    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::En)
        .expect("prepare full regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regenerated overviews");
    commit_overview_regeneration(path_string(repo.path()), plan.operation_id)
        .expect("commit regenerated overviews");

    assert!(!obsolete.exists());
    assert_eq!(fs::read(readme).expect("read README"), b"never touch\n");
}

#[cfg(unix)]
#[test]
fn symlink_generated_node_fails_closed() {
    use std::os::unix::fs::symlink;

    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let outside = tempfile::NamedTempFile::new().expect("create external target");
    let nodes = repo.path().join(".areamatrix/generated/nodes");
    fs::create_dir_all(&nodes).expect("create nodes directory");
    symlink(outside.path(), nodes.join("unsafe.md")).expect("create unsafe symlink");

    let error = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::En)
        .expect_err("symlink target must fail closed");
    assert!(matches!(error, CoreError::Config { .. }));
}

#[cfg(unix)]
#[test]
fn symlink_staging_parent_never_writes_outside_repository() {
    use std::os::unix::fs::symlink;

    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let outside = tempfile::tempdir().expect("create external directory");
    symlink(
        outside.path(),
        repo.path().join(".areamatrix/staging/overview"),
    )
    .expect("create staging symlink");
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");

    let error = start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect_err("staging symlink must fail closed");
    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(
        fs::read_dir(outside.path())
            .expect("read external directory")
            .count(),
        0
    );
}

#[test]
fn cancel_after_staging_preserves_all_old_output() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let root = repo.path().join(".areamatrix/generated/root.md");
    let before = fs::read(&root).expect("read original root");
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    let staged = start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    assert_eq!(staged.status, OverviewRegenerationStatus::ReadyToCommit);

    let canceled = cancel_overview_regeneration(path_string(repo.path()), plan.operation_id)
        .expect("cancel staged regeneration");
    assert_eq!(canceled.status, OverviewRegenerationStatus::Canceled);
    assert_eq!(fs::read(root).expect("read canceled root"), before);
}

#[test]
fn target_hash_drift_blocks_commit_without_overwriting_external_bytes() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    let target = repo.path().join(".areamatrix/generated/root.md");
    fs::write(&target, b"external drift\n").expect("write external drift");

    let error = commit_overview_regeneration(path_string(repo.path()), plan.operation_id.clone())
        .expect_err("drifted target must block commit");
    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(
        fs::read(&target).expect("read drifted target"),
        b"external drift\n"
    );
    let session = get_overview_regeneration(path_string(repo.path()), plan.operation_id)
        .expect("load blocked session");
    assert_eq!(session.status, OverviewRegenerationStatus::RollbackRequired);
}

#[test]
fn corrupt_staging_and_backup_leave_recovery_blocked_and_preserve_target() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let root = repo.path().join(".areamatrix/generated/root.md");
    let before = fs::read(&root).expect("read original root");
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    let root_item = operation_item_paths(repo.path(), &plan.operation_id)
        .into_iter()
        .find(|item| item.0 == ".areamatrix/generated/root.md")
        .expect("find root journal item");
    fs::write(repo.path().join(root_item.1), b"corrupt staged bytes").expect("corrupt staged file");
    fs::write(
        repo.path().join(root_item.2.expect("root backup path")),
        b"corrupt backup bytes",
    )
    .expect("corrupt backup file");

    commit_overview_regeneration(path_string(repo.path()), plan.operation_id.clone())
        .expect_err("unverifiable evidence must block commit");
    assert_eq!(fs::read(root).expect("read preserved root"), before);
    let session = get_overview_regeneration(path_string(repo.path()), plan.operation_id)
        .expect("load blocked session");
    assert_eq!(session.status, OverviewRegenerationStatus::RollbackRequired);
}

#[test]
fn crash_recovery_rolls_forward_a_verified_partially_applied_plan() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    let first = operation_item_paths(repo.path(), &plan.operation_id)
        .into_iter()
        .find(|item| item.0 == ".areamatrix/generated/root.md")
        .expect("find root item");
    let staged = fs::read(repo.path().join(first.1)).expect("read staged root");
    fs::write(repo.path().join(first.0), staged).expect("simulate partial commit");
    force_operation_status(repo.path(), &plan.operation_id, "committing");

    let recovered =
        resume_overview_regeneration(path_string(repo.path()), plan.operation_id.clone())
            .expect("recover committing operation");
    assert_eq!(recovered.status, OverviewRegenerationStatus::Completed);
    assert_eq!(
        get_overview_language_status(path_string(repo.path()), ContentLocale::ZhHans)
            .expect("read recovered language status")
            .state,
        OverviewLanguageState::Synchronized
    );
}

#[test]
fn startup_recovery_discovers_and_rolls_forward_without_operation_id() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");

    let recovered = recover_overview_regeneration_on_startup(path_string(repo.path()))
        .expect("recover active regeneration")
        .expect("active regeneration session");

    assert_eq!(recovered.context.operation_id, plan.operation_id);
    assert_eq!(recovered.status, OverviewRegenerationStatus::Completed);
    assert!(
        recover_overview_regeneration_on_startup(path_string(repo.path()))
            .expect("repeat startup recovery")
            .is_none()
    );
}

#[test]
fn startup_recovery_fails_closed_when_multiple_active_operations_exist() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    let connection = Connection::open(repo.path().join(".areamatrix/index.db"))
        .expect("open repository database");
    connection
        .execute(
            "INSERT INTO recoverable_operations (
               operation_id, retry_of_operation_id, operation_code, operation_payload_json,
               content_locale, repository_revision, format_contract_version, target_set_hash,
               status, run_sequence, created_at, updated_at, finished_at, error_code
             )
             SELECT ?1, retry_of_operation_id, operation_code, operation_payload_json,
                    content_locale, repository_revision, format_contract_version, target_set_hash,
                    status, run_sequence, created_at + 1, updated_at + 1, finished_at, error_code
             FROM recoverable_operations WHERE operation_id = ?2",
            (
                "00000000-0000-4000-8000-000000000001",
                plan.operation_id.as_str(),
            ),
        )
        .expect("inject conflicting active operation");

    let error = recover_overview_regeneration_on_startup(path_string(repo.path()))
        .expect_err("ambiguous active operations must fail closed");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(
        get_overview_regeneration(path_string(repo.path()), plan.operation_id)
            .expect("original operation remains active")
            .status,
        OverviewRegenerationStatus::ReadyToCommit
    );
}

#[test]
fn crash_recovery_rolls_back_when_staged_plan_is_invalid_but_backup_is_valid() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    complete_regeneration(repo.path(), ContentLocale::En);
    let root = repo.path().join(".areamatrix/generated/root.md");
    let before = fs::read(&root).expect("read synchronized root");
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    let first = operation_item_paths(repo.path(), &plan.operation_id)
        .into_iter()
        .find(|item| item.0 == ".areamatrix/generated/root.md")
        .expect("find root item");
    fs::write(repo.path().join(first.1), b"corrupt staged bytes").expect("corrupt staged root");
    force_operation_status(repo.path(), &plan.operation_id, "committing");

    let recovered = resume_overview_regeneration(path_string(repo.path()), plan.operation_id)
        .expect("recover through rollback");
    assert_eq!(recovered.status, OverviewRegenerationStatus::RolledBack);
    assert_eq!(fs::read(root).expect("read rolled-back root"), before);
    assert_eq!(
        get_overview_language_status(path_string(repo.path()), ContentLocale::En)
            .expect("read restored provenance")
            .state,
        OverviewLanguageState::Synchronized
    );
}

#[test]
fn startup_recovery_discovers_and_rolls_back_from_verified_backup() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    complete_regeneration(repo.path(), ContentLocale::En);
    let root = repo.path().join(".areamatrix/generated/root.md");
    let before = fs::read(&root).expect("read synchronized root");
    let plan = prepare_overview_regeneration(path_string(repo.path()), ContentLocale::ZhHans)
        .expect("prepare regeneration");
    start_overview_regeneration(path_string(repo.path()), start_request(&plan))
        .expect("prepare regeneration output");
    let first = operation_item_paths(repo.path(), &plan.operation_id)
        .into_iter()
        .find(|item| item.0 == ".areamatrix/generated/root.md")
        .expect("find root item");
    fs::write(repo.path().join(first.1), b"corrupt staged bytes").expect("corrupt staged root");
    force_operation_status(repo.path(), &plan.operation_id, "committing");

    let recovered = recover_overview_regeneration_on_startup(path_string(repo.path()))
        .expect("recover active regeneration")
        .expect("active regeneration session");

    assert_eq!(recovered.status, OverviewRegenerationStatus::RolledBack);
    assert_eq!(fs::read(root).expect("read restored root"), before);
}

#[test]
fn language_status_reports_mixed_missing_obsolete_and_hash_drift_without_guessing() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let operation_id = complete_regeneration(repo.path(), ContentLocale::En);
    let db_path = repo.path().join(".areamatrix/index.db");
    let connection = Connection::open(&db_path).expect("open database");
    connection
        .execute(
            "UPDATE overview_provenance SET content_locale = 'zh-Hans'
             WHERE relative_path = (
               SELECT relative_path FROM overview_provenance
               WHERE relative_path LIKE '.areamatrix/generated/nodes/%' LIMIT 1
             )",
            [],
        )
        .expect("create mixed provenance");
    drop(connection);
    assert_eq!(
        get_overview_language_status(path_string(repo.path()), ContentLocale::En)
            .expect("read mixed status")
            .state,
        OverviewLanguageState::Mixed
    );

    complete_regeneration(repo.path(), ContentLocale::En);
    let root = repo.path().join(".areamatrix/generated/root.md");
    fs::remove_file(&root).expect("remove generated target");
    let missing = get_overview_language_status(path_string(repo.path()), ContentLocale::En)
        .expect("read missing status");
    assert_eq!(missing.state, OverviewLanguageState::NeedsRegeneration);
    assert_eq!(
        missing.reasons,
        vec![OverviewRegenerationReason::MissingTargets]
    );

    complete_regeneration(repo.path(), ContentLocale::En);
    fs::write(&root, b"hash drift\n").expect("change generated target");
    assert_eq!(
        get_overview_language_status(path_string(repo.path()), ContentLocale::En)
            .expect("read hash drift status")
            .state,
        OverviewLanguageState::Unknown
    );

    complete_regeneration(repo.path(), ContentLocale::En);
    let obsolete = repo.path().join(".areamatrix/generated/nodes/obsolete.md");
    fs::write(&obsolete, b"obsolete\n").expect("write obsolete target");
    let hash = format!("{:x}", sha2::Sha256::digest(b"obsolete\n"));
    let connection = Connection::open(db_path).expect("reopen database");
    connection
        .execute(
            "INSERT INTO overview_provenance (
               relative_path, operation_id, content_locale, format_contract_version,
               repository_revision, content_sha256, generated_at
             ) VALUES (?1, ?2, 'en', 1, 1, ?3, 1)",
            (
                ".areamatrix/generated/nodes/obsolete.md",
                operation_id,
                hash,
            ),
        )
        .expect("insert obsolete provenance");
    let obsolete_status = get_overview_language_status(path_string(repo.path()), ContentLocale::En)
        .expect("read obsolete status");
    assert_eq!(
        obsolete_status.state,
        OverviewLanguageState::NeedsRegeneration
    );
    assert_eq!(
        obsolete_status.reasons,
        vec![OverviewRegenerationReason::ObsoleteTargets]
    );
}
