//! C3-01 AI settings contract types.

use std::{
    collections::HashSet,
    path::{Component, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_PRIVACY_POLICY_REF_LEN: usize = 128;

/// Preferred provider route for AI features.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiProviderPreference {
    /// Prefer local models and use remote only when a later gate allows it.
    LocalFirst,
    /// Do not use remote providers for this repository.
    LocalOnly,
    /// Prefer remote providers after explicit provider consent and privacy gates.
    RemoteFirst,
}

/// AI feature switch tracked by the C3-01 settings contract.
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum AiFeatureKind {
    /// AI classification suggestions.
    ClassificationSuggestions,
    /// AI summary drafts.
    AutoSummaries,
    /// AI tag suggestions.
    AutoTags,
    /// Semantic search and embedding-backed matching.
    SemanticSearch,
}

/// Per-feature settings shown by the AI settings page.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiFeatureConfig {
    /// Feature controlled by this row.
    pub feature: AiFeatureKind,
    /// Whether the feature is enabled in settings.
    pub enabled: bool,
    /// Whether this feature may use a remote provider after later gates pass.
    pub allow_remote: bool,
}

/// Repository AI settings payload accepted by C3-01.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiConfig {
    /// Repository root path the payload belongs to.
    pub repo_path: String,
    /// Master AI switch. Defaults to false.
    pub ai_enabled: bool,
    /// Preferred provider route when more than one route is available.
    pub provider_preference: AiProviderPreference,
    /// Whether local AI routes are allowed by repository settings.
    pub local_ai_enabled: bool,
    /// Whether remote routes are allowed after C3-03 and C3-09 gates pass.
    pub remote_ai_allowed: bool,
    /// Global remote privacy gate setting consumed by S3-09.
    pub privacy_gate_enabled: bool,
    /// Optional stable privacy policy reference. It is not a rules payload.
    pub privacy_policy_ref: Option<String>,
    /// Per-feature switches owned by this settings contract.
    pub feature_toggles: Vec<AiFeatureConfig>,
}

/// Derived capability row that lets pages render settings without local-only fields.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCapabilityState {
    /// Feature represented by this row.
    pub feature: AiFeatureKind,
    /// Whether settings currently allow the feature at all.
    pub enabled: bool,
    /// Whether a local route may be considered by later provider checks.
    pub local_allowed: bool,
    /// Whether a remote route may be considered by later provider and privacy checks.
    pub remote_allowed: bool,
    /// Stable disabled reason for UI and accessibility labels.
    pub disabled_reason: Option<String>,
}

/// Full AI settings snapshot returned by C3-01.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiConfigSnapshot {
    /// Current AI settings payload.
    pub config: AiConfig,
    /// Derived capability rows for S3-01 and S3-09 consumers.
    pub capabilities: Vec<AiCapabilityState>,
    /// Last persisted update timestamp, when implementation storage provides one.
    pub updated_at: Option<i64>,
}

pub(crate) fn load_ai_config(repo_path: String) -> CoreResult<AiConfigSnapshot> {
    validate_repo_path(&repo_path)?;
    let repo = PathBuf::from(&repo_path);
    let Some((serialized, updated_at)) =
        db::load_ai_config_record(&repo).map_err(map_storage_error)?
    else {
        return Ok(snapshot(default_ai_config(repo_path), None));
    };
    let config = deserialize_config(&serialized)?;
    validate_payload(&repo_path, &config)?;
    Ok(snapshot(config, Some(updated_at)))
}

pub(crate) fn update_ai_config(
    repo_path: String,
    new_config: AiConfig,
) -> CoreResult<AiConfigSnapshot> {
    validate_repo_path(&repo_path)?;
    validate_payload(&repo_path, &new_config)?;

    let serialized = serialize_config(&new_config)?;
    let repo = PathBuf::from(&repo_path);
    let updated_at = db::update_ai_config_record(&repo, &serialized, new_config.ai_enabled)
        .map_err(map_storage_error)?;
    Ok(snapshot(new_config, Some(updated_at)))
}

fn default_ai_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: false,
        provider_preference: AiProviderPreference::LocalFirst,
        local_ai_enabled: true,
        remote_ai_allowed: false,
        privacy_gate_enabled: false,
        privacy_policy_ref: None,
        feature_toggles: default_feature_toggles(),
    }
}

fn default_feature_toggles() -> Vec<AiFeatureConfig> {
    all_features()
        .into_iter()
        .map(|feature| AiFeatureConfig {
            feature,
            enabled: false,
            allow_remote: false,
        })
        .collect()
}

fn snapshot(config: AiConfig, updated_at: Option<i64>) -> AiConfigSnapshot {
    let capabilities = capabilities_from_config(&config);
    AiConfigSnapshot {
        config,
        capabilities,
        updated_at,
    }
}

fn capabilities_from_config(config: &AiConfig) -> Vec<AiCapabilityState> {
    config
        .feature_toggles
        .iter()
        .map(|toggle| capability_state(config, toggle))
        .collect()
}

fn capability_state(config: &AiConfig, toggle: &AiFeatureConfig) -> AiCapabilityState {
    let enabled = config.ai_enabled && toggle.enabled;
    let local_allowed = enabled && config.local_ai_enabled;
    let remote_allowed = enabled
        && remote_route_enabled(config)
        && toggle.allow_remote
        && config.privacy_gate_enabled;
    AiCapabilityState {
        feature: toggle.feature.clone(),
        enabled,
        local_allowed,
        remote_allowed,
        disabled_reason: disabled_reason(config, toggle),
    }
}

fn disabled_reason(config: &AiConfig, toggle: &AiFeatureConfig) -> Option<String> {
    if !config.ai_enabled {
        Some("AI is off".to_owned())
    } else if !toggle.enabled {
        Some("Feature is off".to_owned())
    } else if config.local_ai_enabled
        || (remote_route_enabled(config) && toggle.allow_remote && config.privacy_gate_enabled)
    {
        None
    } else {
        Some("No AI route is enabled".to_owned())
    }
}

fn remote_route_enabled(config: &AiConfig) -> bool {
    !matches!(config.provider_preference, AiProviderPreference::LocalOnly)
        && config.remote_ai_allowed
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config("AI config repository path is invalid"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "AI config repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_payload(repo_path: &str, config: &AiConfig) -> CoreResult<()> {
    if config.repo_path != repo_path {
        return Err(CoreError::config("AI config payload repo_path mismatch"));
    }
    if let Some(reference) = config.privacy_policy_ref.as_deref() {
        validate_privacy_policy_ref(reference)?;
    }
    validate_feature_toggles(&config.feature_toggles)
}

fn validate_privacy_policy_ref(reference: &str) -> CoreResult<()> {
    if reference.trim() != reference
        || reference.is_empty()
        || reference.len() > MAX_PRIVACY_POLICY_REF_LEN
        || reference.contains('\0')
        || reference.contains('/')
        || reference.contains('\\')
    {
        return Err(CoreError::config("AI privacy policy reference is invalid"));
    }
    if !reference.chars().all(is_privacy_policy_ref_char) {
        return Err(CoreError::config("AI privacy policy reference is invalid"));
    }
    if looks_like_secret_reference(reference) {
        return Err(CoreError::config(
            "AI privacy policy reference must not contain secrets",
        ));
    }
    Ok(())
}

fn is_privacy_policy_ref_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, '-' | '_' | '.' | ':')
}

fn looks_like_secret_reference(reference: &str) -> bool {
    let normalized = reference.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains("api_key")
        || normalized.contains("apikey")
        || normalized.contains("bearer")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("-----begin")
}

fn validate_feature_toggles(toggles: &[AiFeatureConfig]) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for toggle in toggles {
        if !seen.insert(toggle.feature.clone()) {
            return Err(CoreError::config("AI feature toggles must be unique"));
        }
    }
    if seen.len() != all_features().len() {
        return Err(CoreError::config(
            "AI feature toggles must include every C3-01 feature",
        ));
    }
    Ok(())
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}

fn serialize_config(config: &AiConfig) -> CoreResult<String> {
    serde_json::to_string(config).map_err(|_| CoreError::config("AI config metadata is invalid"))
}

fn deserialize_config(serialized: &str) -> CoreResult<AiConfig> {
    serde_json::from_str(serialized).map_err(|_| CoreError::config("AI config metadata is invalid"))
}

fn map_storage_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } => CoreError::config("AI config metadata persistence failed"),
        CoreError::InvalidPath { .. } => CoreError::config("AI config repository path is invalid"),
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI config requires initialized repository metadata")
        }
        other => other,
    }
}

fn all_features() -> Vec<AiFeatureKind> {
    vec![
        AiFeatureKind::ClassificationSuggestions,
        AiFeatureKind::AutoSummaries,
        AiFeatureKind::AutoTags,
        AiFeatureKind::SemanticSearch,
    ]
}
