//! Restart-safe full overview regeneration and language provenance.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    db, ContentLocale, CoreError, CoreResult, RecoverableOperationContext,
    RecoverableOperationStatus,
};

mod execution;
mod plan;

use execution::{
    cleanup_operation_directory, commit_ready, create_journal, execute_precommit, fail_operation,
    recover_committing, rollback_internal,
};
use plan::{
    decode_token, encode_token, hash_target_set, language_status_for_targets, render_targets,
};

pub(super) const FORMAT_CONTRACT_VERSION: i64 = 1;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum OverviewLanguageState {
    NotGenerated,
    Synchronized,
    NeedsRegeneration,
    Mixed,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
pub enum OverviewRegenerationReason {
    LocaleMismatch,
    FormatMismatch,
    MissingTargets,
    ObsoleteTargets,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum OverviewRegenerationStatus {
    Running,
    Staging,
    ReadyToCommit,
    Committing,
    Completed,
    RollbackRequired,
    RolledBack,
    Failed,
    Canceled,
}

impl From<RecoverableOperationStatus> for OverviewRegenerationStatus {
    fn from(value: RecoverableOperationStatus) -> Self {
        match value {
            RecoverableOperationStatus::Running => Self::Running,
            RecoverableOperationStatus::Staging => Self::Staging,
            RecoverableOperationStatus::ReadyToCommit => Self::ReadyToCommit,
            RecoverableOperationStatus::Committing => Self::Committing,
            RecoverableOperationStatus::Completed => Self::Completed,
            RecoverableOperationStatus::RollbackRequired => Self::RollbackRequired,
            RecoverableOperationStatus::RolledBack => Self::RolledBack,
            RecoverableOperationStatus::Failed => Self::Failed,
            RecoverableOperationStatus::Canceled => Self::Canceled,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct OverviewLanguageStatus {
    pub state: OverviewLanguageState,
    pub content_locale: ContentLocale,
    pub target_count: i64,
    pub known_target_count: i64,
    pub missing_target_count: i64,
    pub obsolete_target_count: i64,
    pub known_locales: Vec<ContentLocale>,
    pub known_format_versions: Vec<i64>,
    pub reasons: Vec<OverviewRegenerationReason>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct OverviewRegenerationPlan {
    pub operation_id: String,
    pub plan_token: String,
    pub repository_revision: i64,
    pub content_locale: ContentLocale,
    pub format_contract_version: i64,
    pub target_set_hash: String,
    pub target_count: i64,
    pub create_count: i64,
    pub replace_count: i64,
    pub delete_count: i64,
    pub includes_root_areamatrix_file: bool,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct OverviewRegenerationStartRequest {
    pub operation_id: String,
    pub plan_token: String,
    pub expected_repository_revision: i64,
    pub confirmed: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct OverviewRegenerationSession {
    pub context: RecoverableOperationContext,
    pub status: OverviewRegenerationStatus,
    pub target_count: i64,
    pub staged_count: i64,
    pub applied_count: i64,
    pub restored_count: i64,
    pub cancellation_allowed: bool,
    pub error_code: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    pub finished_at: Option<i64>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(super) struct PlanPayload {
    pub(super) operation_id: String,
    pub(super) repository_revision: i64,
    pub(super) content_locale: ContentLocale,
    pub(super) format_contract_version: i64,
    pub(super) target_set_hash: String,
}

pub(super) struct RenderedTarget {
    pub(super) relative_path: String,
    pub(super) target_kind: String,
    pub(super) old_content: Option<Vec<u8>>,
    pub(super) new_content: Option<Vec<u8>>,
}

pub fn prepare(
    repo_path: String,
    content_locale: ContentLocale,
) -> CoreResult<OverviewRegenerationPlan> {
    let repo = validated_repo(&repo_path)?;
    ensure_generation_policy(&repo)?;
    let snapshot = db::load_repo_config_snapshot_or_default(repo_path)?;
    let targets = render_targets(&repo, &content_locale, snapshot.overview_output.clone())?;
    let target_set_hash = hash_target_set(&targets);
    let payload = PlanPayload {
        operation_id: Uuid::new_v4().to_string(),
        repository_revision: snapshot.revision,
        content_locale: content_locale.clone(),
        format_contract_version: FORMAT_CONTRACT_VERSION,
        target_set_hash: target_set_hash.clone(),
    };
    let status = language_status_for_targets(&repo, &content_locale, &targets)?;
    let warnings = match status.state {
        OverviewLanguageState::NotGenerated => vec!["overview_not_generated".to_owned()],
        OverviewLanguageState::Synchronized => Vec::new(),
        OverviewLanguageState::NeedsRegeneration => {
            vec!["overview_needs_regeneration".to_owned()]
        }
        OverviewLanguageState::Mixed => vec!["overview_language_mixed".to_owned()],
        OverviewLanguageState::Unknown => vec!["overview_language_unknown".to_owned()],
    };
    let create_count = targets
        .iter()
        .filter(|target| target.old_content.is_none() && target.new_content.is_some())
        .count() as i64;
    let replace_count = targets
        .iter()
        .filter(|target| target.old_content.is_some() && target.new_content.is_some())
        .count() as i64;
    let delete_count = targets
        .iter()
        .filter(|target| target.old_content.is_some() && target.new_content.is_none())
        .count() as i64;
    Ok(OverviewRegenerationPlan {
        operation_id: payload.operation_id.clone(),
        plan_token: encode_token(&payload)?,
        repository_revision: payload.repository_revision,
        content_locale,
        format_contract_version: FORMAT_CONTRACT_VERSION,
        target_set_hash,
        target_count: targets.len() as i64,
        create_count,
        replace_count,
        delete_count,
        includes_root_areamatrix_file: targets
            .iter()
            .any(|target| target.relative_path == "AREAMATRIX.md"),
        warnings,
    })
}

pub fn start(
    repo_path: String,
    request: OverviewRegenerationStartRequest,
) -> CoreResult<OverviewRegenerationSession> {
    if !request.confirmed || request.expected_repository_revision < 1 {
        return Err(CoreError::config(
            "overview regeneration confirmation is required",
        ));
    }
    let repo = validated_repo(&repo_path)?;
    let payload = decode_token(&request.plan_token)?;
    if payload.operation_id != request.operation_id
        || payload.repository_revision != request.expected_repository_revision
        || payload.format_contract_version != FORMAT_CONTRACT_VERSION
    {
        return Err(CoreError::conflict("overview regeneration plan is stale"));
    }
    ensure_generation_policy(&repo)?;
    let snapshot = db::load_repo_config_snapshot_or_default(repo_path)?;
    if snapshot.revision != payload.repository_revision {
        return Err(CoreError::conflict(
            "repository configuration revision changed",
        ));
    }
    let targets = render_targets(&repo, &payload.content_locale, snapshot.overview_output)?;
    if hash_target_set(&targets) != payload.target_set_hash {
        return Err(CoreError::conflict("overview regeneration targets changed"));
    }
    create_journal(&repo, &payload, &targets)?;
    execute_precommit(&repo, &payload, &targets)?;
    get(repo.to_string_lossy().into_owned(), payload.operation_id)
}

pub fn commit(repo_path: String, operation_id: String) -> CoreResult<OverviewRegenerationSession> {
    let repo = validated_repo(&repo_path)?;
    commit_ready(&repo, &operation_id)?;
    get(repo_path, operation_id)
}

pub fn get(repo_path: String, operation_id: String) -> CoreResult<OverviewRegenerationSession> {
    let repo = validated_repo(&repo_path)?;
    let (operation, items) = db::load_overview_regeneration(&repo, &operation_id)?;
    if operation.context.operation_code != "overview_regeneration" {
        return Err(CoreError::config("operation is not overview regeneration"));
    }
    let count = |state: &str| items.iter().filter(|item| item.state == state).count() as i64;
    Ok(OverviewRegenerationSession {
        context: operation.context,
        cancellation_allowed: matches!(
            operation.status,
            RecoverableOperationStatus::Running
                | RecoverableOperationStatus::Staging
                | RecoverableOperationStatus::ReadyToCommit
        ),
        status: operation.status.into(),
        target_count: items.len() as i64,
        staged_count: count("staged") + count("applied") + count("restored"),
        applied_count: count("applied"),
        restored_count: count("restored"),
        error_code: operation.error_code,
        created_at: operation.created_at,
        updated_at: operation.updated_at,
        finished_at: operation.finished_at,
    })
}

pub fn recover_on_startup(repo_path: String) -> CoreResult<Option<OverviewRegenerationSession>> {
    let repo = validated_repo(&repo_path)?;
    let Some(operation_id) = db::load_unsettled_overview_regeneration_id(&repo)? else {
        return Ok(None);
    };
    resume(repo_path, operation_id).map(Some)
}

pub fn resume(repo_path: String, operation_id: String) -> CoreResult<OverviewRegenerationSession> {
    let repo = validated_repo(&repo_path)?;
    let (operation, _) = db::load_overview_regeneration(&repo, &operation_id)?;
    match operation.status {
        RecoverableOperationStatus::Running | RecoverableOperationStatus::Staging => {
            db::update_overview_operation_status(
                &repo,
                &operation_id,
                RecoverableOperationStatus::Staging,
                None,
                true,
            )?;
            let locale = operation
                .context
                .content_locale
                .clone()
                .ok_or_else(|| CoreError::db("overview operation locale is missing"))?;
            let snapshot = db::load_repo_config_snapshot_or_default(repo_path.clone())?;
            if snapshot.revision != operation.context.repository_revision {
                fail_operation(&repo, &operation_id, "repo_config_revision_conflict")?;
                return get(repo_path, operation_id);
            }
            let targets = render_targets(&repo, &locale, snapshot.overview_output)?;
            if Some(hash_target_set(&targets)) != operation.context.target_set_hash {
                fail_operation(&repo, &operation_id, "overview_target_set_conflict")?;
                return get(repo_path, operation_id);
            }
            let payload = PlanPayload {
                operation_id: operation_id.clone(),
                repository_revision: operation.context.repository_revision,
                content_locale: locale,
                format_contract_version: operation.context.format_contract_version,
                target_set_hash: operation.context.target_set_hash.unwrap_or_default(),
            };
            execute_precommit(&repo, &payload, &targets)?;
            let (refreshed, _) = db::load_overview_regeneration(&repo, &operation_id)?;
            if refreshed.status == RecoverableOperationStatus::ReadyToCommit {
                commit_ready(&repo, &operation_id)?;
            }
        }
        RecoverableOperationStatus::ReadyToCommit => commit_ready(&repo, &operation_id)?,
        RecoverableOperationStatus::Committing | RecoverableOperationStatus::RollbackRequired => {
            recover_committing(&repo, &operation_id)?
        }
        RecoverableOperationStatus::Completed
        | RecoverableOperationStatus::RolledBack
        | RecoverableOperationStatus::Failed
        | RecoverableOperationStatus::Canceled => {}
    }
    get(repo_path, operation_id)
}

pub fn cancel(repo_path: String, operation_id: String) -> CoreResult<OverviewRegenerationSession> {
    let repo = validated_repo(&repo_path)?;
    let (operation, _) = db::load_overview_regeneration(&repo, &operation_id)?;
    if !matches!(
        operation.status,
        RecoverableOperationStatus::Running
            | RecoverableOperationStatus::Staging
            | RecoverableOperationStatus::ReadyToCommit
    ) {
        return Err(CoreError::conflict(
            "overview regeneration cannot be canceled",
        ));
    }
    db::update_overview_operation_status(
        &repo,
        &operation_id,
        RecoverableOperationStatus::Canceled,
        None,
        false,
    )?;
    cleanup_operation_directory(&repo, &operation_id)?;
    get(repo_path, operation_id)
}

pub fn rollback(
    repo_path: String,
    operation_id: String,
) -> CoreResult<OverviewRegenerationSession> {
    let repo = validated_repo(&repo_path)?;
    let (operation, _) = db::load_overview_regeneration(&repo, &operation_id)?;
    if !matches!(
        operation.status,
        RecoverableOperationStatus::RollbackRequired | RecoverableOperationStatus::Failed
    ) {
        return Err(CoreError::conflict(
            "overview regeneration cannot be rolled back",
        ));
    }
    rollback_internal(&repo, &operation_id)?;
    get(repo_path, operation_id)
}

pub fn language_status(
    repo_path: String,
    content_locale: ContentLocale,
) -> CoreResult<OverviewLanguageStatus> {
    let repo = validated_repo(&repo_path)?;
    let snapshot = db::load_repo_config_snapshot_or_default(repo_path)?;
    let targets = render_targets(&repo, &content_locale, snapshot.overview_output)?;
    language_status_for_targets(&repo, &content_locale, &targets)
}

fn ensure_generation_policy(repo: &Path) -> CoreResult<()> {
    db::ensure_repository_locale_allows_normal_mutation(repo)
}

fn validated_repo(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::config("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    db::ensure_initialized(&repo)?;
    Ok(repo)
}
