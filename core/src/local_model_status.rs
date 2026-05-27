//! C3-02 local model status contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{AiFeatureKind, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_MODEL_ID_LEN: usize = 128;

/// Local model lifecycle state displayed by S3-02.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum LocalModelAvailability {
    /// No current status has been checked or cached yet.
    Unknown,
    /// The local model is ready for supported AI features.
    Ready,
    /// The model is not installed at the configured location.
    NotInstalled,
    /// The configured model location cannot be read.
    PathUnreadable,
    /// The installed model version is not compatible with AreaMatrix.
    VersionIncompatible,
    /// A status check is running.
    Checking,
    /// Model manifest and metadata verification is running.
    Verifying,
    /// Runtime startup is in progress.
    Loading,
    /// Model files or local metadata are corrupted.
    Corrupted,
    /// The model runtime failed to start.
    RuntimeFailed,
    /// A non-specific status error occurred.
    Error,
}

/// Single primary recovery action recommended for the current status.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum LocalModelRecommendedAction {
    /// No recovery action is needed.
    None,
    /// Run the first status check.
    CheckStatus,
    /// Retry status detection.
    RetryStatusCheck,
    /// Open local model installation help.
    OpenInstallHelp,
    /// Reveal the configured model folder.
    OpenModelLocation,
    /// Run a lightweight runtime and manifest health check.
    RunHealthCheck,
    /// Rebuild AreaMatrix-owned model metadata.
    RepairMetadata,
    /// Open the local diagnostics panel.
    OpenDiagnostics,
    /// Fall back to non-AI behavior such as rules, inbox, or ordinary search.
    UseNonAiFallback,
}

/// Per-feature local model support row consumed by S3-02.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LocalModelFeatureStatus {
    /// AI feature represented by this row.
    pub feature: AiFeatureKind,
    /// Whether the local model can currently serve the feature.
    pub available: bool,
    /// Stable reason shown when the feature is unavailable.
    pub unavailable_reason: Option<String>,
}

/// Cached local model status accepted as read-only input.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LocalModelCachedStatus {
    /// Stable local model identifier.
    pub model_id: String,
    /// Configured model storage location.
    pub storage_location: String,
    /// Cached availability state.
    pub availability: LocalModelAvailability,
    /// Cached model version, when known.
    pub version: Option<String>,
    /// Cached model disk usage in bytes, when known.
    pub size_bytes: Option<i64>,
    /// Last cached local-model error, sanitized for UI and diagnostics.
    pub last_error: Option<String>,
    /// Cached primary recovery action.
    pub recommended_action: LocalModelRecommendedAction,
    /// Unix timestamp for the last status check, when known.
    pub last_checked_at: Option<i64>,
    /// Sanitized diagnostics summary. It must not contain user file contents,
    /// API keys, remote provider config, or full user-file path listings.
    pub diagnostics_summary: String,
}

/// Request for a C3-02 local model status refresh.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LocalModelStatusRequest {
    /// Stable local model identifier.
    pub model_id: String,
    /// Configured local model storage location.
    pub storage_location: String,
    /// Optional cached snapshot used for initial display or failure entry.
    pub cached_status: Option<LocalModelCachedStatus>,
}

/// Status snapshot returned to S3-02.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LocalModelStatusSnapshot {
    /// Stable local model identifier.
    pub model_id: String,
    /// Configured local model storage location.
    pub storage_location: String,
    /// Current availability state.
    pub availability: LocalModelAvailability,
    /// Installed model version, when known.
    pub version: Option<String>,
    /// Disk usage in bytes, when known.
    pub size_bytes: Option<i64>,
    /// Last local-model error, sanitized for UI and diagnostics.
    pub last_error: Option<String>,
    /// Primary recovery action for the current state.
    pub recommended_action: LocalModelRecommendedAction,
    /// Unix timestamp for the last status check, when known.
    pub last_checked_at: Option<i64>,
    /// Sanitized diagnostics summary for the local diagnostics panel.
    pub diagnostics_summary: String,
    /// Local model support for the AI features shown by S3-02.
    pub feature_statuses: Vec<LocalModelFeatureStatus>,
}

/// Request for locating the configured local model folder.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LocalModelFolderRequest {
    /// Stable local model identifier.
    pub model_id: String,
    /// Configured local model storage location.
    pub storage_location: String,
}

/// Read-only folder location result for S3-02.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LocalModelFolderLocation {
    /// Stable local model identifier.
    pub model_id: String,
    /// Folder path that the platform layer may reveal.
    pub folder_path: String,
    /// Whether the folder currently exists.
    pub exists: bool,
    /// Whether the folder can be inspected.
    pub readable: bool,
    /// Whether the platform layer may attempt to reveal it.
    pub openable: bool,
    /// Stable reason when the folder cannot be revealed.
    pub unavailable_reason: Option<String>,
}

pub(crate) fn get_local_model_status(
    repo_path: String,
    request: LocalModelStatusRequest,
) -> CoreResult<LocalModelStatusSnapshot> {
    validate_repo_path(&repo_path)?;
    validate_status_request(&request)?;
    Err(CoreError::config(
        "local model status implementation is not available yet",
    ))
}

pub(crate) fn locate_local_model_folder(
    repo_path: String,
    request: LocalModelFolderRequest,
) -> CoreResult<LocalModelFolderLocation> {
    validate_repo_path(&repo_path)?;
    validate_model_identity(&request.model_id, &request.storage_location)?;
    Err(CoreError::config(
        "local model folder location implementation is not available yet",
    ))
}

fn validate_status_request(request: &LocalModelStatusRequest) -> CoreResult<()> {
    validate_model_identity(&request.model_id, &request.storage_location)?;
    if let Some(cached) = request.cached_status.as_ref() {
        validate_cached_status(request, cached)?;
    }
    Ok(())
}

fn validate_cached_status(
    request: &LocalModelStatusRequest,
    cached: &LocalModelCachedStatus,
) -> CoreResult<()> {
    if cached.model_id != request.model_id || cached.storage_location != request.storage_location {
        return Err(CoreError::config(
            "local model cached status does not match request",
        ));
    }
    if cached.size_bytes.is_some_and(|size| size < 0) {
        return Err(CoreError::config("local model size must not be negative"));
    }
    if cached
        .last_checked_at
        .is_some_and(|last_checked_at| last_checked_at < 0)
    {
        return Err(CoreError::config(
            "local model last_checked_at must not be negative",
        ));
    }
    if cached.diagnostics_summary.contains('\0') || looks_sensitive(&cached.diagnostics_summary) {
        return Err(CoreError::config(
            "local model diagnostics summary contains disallowed content",
        ));
    }
    Ok(())
}

fn validate_model_identity(model_id: &str, storage_location: &str) -> CoreResult<()> {
    if model_id.trim() != model_id
        || model_id.is_empty()
        || model_id.len() > MAX_MODEL_ID_LEN
        || model_id.contains('\0')
        || !model_id.chars().all(is_model_id_char)
    {
        return Err(CoreError::config("local model id is invalid"));
    }
    if storage_location.trim().is_empty() || storage_location.contains('\0') {
        return Err(CoreError::config("local model storage location is invalid"));
    }
    Ok(())
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config(
            "local model status repository path is invalid",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "local model status repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn is_model_id_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, '-' | '_' | '.' | ':')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}

fn looks_sensitive(summary: &str) -> bool {
    let normalized = summary.to_ascii_lowercase();
    let direct_tokens = [
        "api key",
        "api_key",
        "apikey",
        "authorization:",
        "bearer ",
        "provider_config",
        "remote_provider",
        "token=",
        "-----begin",
    ];
    direct_tokens.iter().any(|token| normalized.contains(token))
        || normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains(" sk-")
        || normalized.contains(" sk_")
}
