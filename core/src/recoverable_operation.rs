//! Durable identity and frozen context for restart-safe operations.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ContentLocale, CoreError, CoreResult};

/// Durable lifecycle used by restart-safe operations and file journals.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RecoverableOperationStatus {
    /// The operation exists and may start or resume work.
    Running,
    /// AreaMatrix-owned staging is being prepared.
    Staging,
    /// Every target is staged and the revision gate may run.
    ReadyToCommit,
    /// The short non-cancellable filesystem commit is active.
    Committing,
    /// New output and provenance were committed.
    Completed,
    /// Recovery must restore old bytes before normal writes resume.
    RollbackRequired,
    /// Old bytes and provenance were restored.
    RolledBack,
    /// The operation failed without a pending rollback.
    Failed,
    /// The user canceled before commit and old output remains active.
    Canceled,
}

impl RecoverableOperationStatus {
    pub(crate) fn as_str(&self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Staging => "staging",
            Self::ReadyToCommit => "ready_to_commit",
            Self::Committing => "committing",
            Self::Completed => "completed",
            Self::RollbackRequired => "rollback_required",
            Self::RolledBack => "rolled_back",
            Self::Failed => "failed",
            Self::Canceled => "canceled",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "running" => Some(Self::Running),
            "staging" => Some(Self::Staging),
            "ready_to_commit" => Some(Self::ReadyToCommit),
            "committing" => Some(Self::Committing),
            "completed" => Some(Self::Completed),
            "rollback_required" => Some(Self::RollbackRequired),
            "rolled_back" => Some(Self::RolledBack),
            "failed" => Some(Self::Failed),
            "canceled" => Some(Self::Canceled),
            _ => None,
        }
    }

    pub(crate) fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::Completed | Self::RolledBack | Self::Failed | Self::Canceled
        )
    }
}

/// Data-minimized context frozen before the first side effect or remote call.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RecoverableOperationContext {
    /// UUID for one user-triggered attempt.
    pub operation_id: String,
    /// Previous terminal attempt when this operation is an explicit retry.
    pub retry_of_operation_id: Option<String>,
    /// Stable capability code, never translated.
    pub operation_code: String,
    /// Canonical operation-specific JSON without display strings or secrets.
    pub operation_payload_json: String,
    /// Concrete generated-content locale, when the operation produces language.
    pub content_locale: Option<ContentLocale>,
    /// Repository config revision observed at the operation boundary.
    pub repository_revision: i64,
    /// Deterministic persisted-output format contract version.
    pub format_contract_version: i64,
    /// Hash of the frozen target set, when applicable.
    pub target_set_hash: Option<String>,
    /// Internal execution entry count; resume increments it without changing identity.
    pub run_sequence: i64,
}

impl RecoverableOperationContext {
    pub(crate) fn validate(&self) -> CoreResult<()> {
        validate_uuid(&self.operation_id, "operation_id")?;
        if let Some(retry_of) = self.retry_of_operation_id.as_deref() {
            validate_uuid(retry_of, "retry_of_operation_id")?;
            if retry_of == self.operation_id {
                return Err(CoreError::config(
                    "recoverable operation cannot retry itself",
                ));
            }
        }
        if self.operation_code.is_empty()
            || !self
                .operation_code
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
        {
            return Err(CoreError::config("recoverable operation code is invalid"));
        }
        let payload: serde_json::Value = serde_json::from_str(&self.operation_payload_json)
            .map_err(|_| CoreError::config("recoverable operation payload is invalid"))?;
        if !payload.is_object() {
            return Err(CoreError::config(
                "recoverable operation payload must be an object",
            ));
        }
        if self.repository_revision < 0 || self.format_contract_version < 1 || self.run_sequence < 1
        {
            return Err(CoreError::config(
                "recoverable operation numeric context is invalid",
            ));
        }
        if let Some(hash) = self.target_set_hash.as_deref() {
            if hash.len() != 64 || !hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                return Err(CoreError::config(
                    "recoverable operation target hash is invalid",
                ));
            }
        }
        Ok(())
    }
}

fn validate_uuid(value: &str, field: &str) -> CoreResult<()> {
    let parsed = Uuid::parse_str(value)
        .map_err(|_| CoreError::config(format!("recoverable operation {field} is invalid")))?;
    if parsed.to_string() == value {
        Ok(())
    } else {
        Err(CoreError::config(format!(
            "recoverable operation {field} must be canonical"
        )))
    }
}
