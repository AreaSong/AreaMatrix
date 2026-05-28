//! Persisted C3-03 provider state read and disable flows.

use std::path::PathBuf;

use crate::{
    db,
    remote_provider_config::{
        map_storage_error, RemoteProviderConfigSnapshot, RemoteProviderDisableRequest,
        StoredRemoteProviderConfig,
    },
    AiFeatureKind, CoreError, CoreResult,
};

pub(crate) fn load_remote_ai_provider_config(
    repo_path: String,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    super::validate_repo_path(&repo_path)?;
    let repo = PathBuf::from(&repo_path);
    let Some((serialized, updated_at)) =
        db::load_remote_provider_config_record(&repo).map_err(map_storage_error)?
    else {
        return Ok(empty_snapshot());
    };
    let config = deserialize_stored_config(&serialized)?;
    Ok(snapshot_from_stored_config(config, Some(updated_at)))
}

pub(crate) fn disable_remote_ai_provider(
    repo_path: String,
    request: RemoteProviderDisableRequest,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    super::validate_repo_path(&repo_path)?;
    let repo = PathBuf::from(&repo_path);
    let Some((serialized, _)) =
        db::load_remote_provider_config_record(&repo).map_err(map_storage_error)?
    else {
        return Ok(empty_snapshot());
    };

    let mut config = deserialize_stored_config(&serialized)?;
    config.remote_provider_enabled = false;
    if request.remove_stored_credential {
        config.key_reference.clear();
        config.provider_verified = false;
    }

    let updated = serialize_stored_config(&config)?;
    let updated_at =
        db::update_remote_provider_config_record(&repo, &updated).map_err(map_storage_error)?;
    Ok(snapshot_from_stored_config(config, Some(updated_at)))
}

pub(crate) fn load_enabled_remote_provider_runtime(
    repo_path: &std::path::Path,
    feature: AiFeatureKind,
) -> CoreResult<Option<StoredRemoteProviderConfig>> {
    let Some((serialized, _)) =
        db::load_remote_provider_config_record(repo_path).map_err(map_storage_error)?
    else {
        return Ok(None);
    };
    let config = deserialize_stored_config(&serialized)?;
    if provider_configured(&config)
        && config.provider_verified
        && config.remote_provider_enabled
        && config.feature_scope.contains(&feature)
    {
        Ok(Some(config))
    } else {
        Ok(None)
    }
}

pub(super) fn snapshot_from_stored_config(
    config: StoredRemoteProviderConfig,
    updated_at: Option<i64>,
) -> RemoteProviderConfigSnapshot {
    let disabled_reason = disabled_reason(&config);
    RemoteProviderConfigSnapshot {
        provider_configured: provider_configured(&config),
        provider_verified: config.provider_verified,
        remote_provider_enabled: config.remote_provider_enabled,
        provider: Some(config.provider),
        model_id: Some(config.model_id),
        endpoint_url: config.endpoint_url,
        credential_configured: !config.key_reference.is_empty(),
        feature_scope: config.feature_scope,
        updated_at,
        disabled_reason,
    }
}

pub(super) fn serialize_stored_config(config: &StoredRemoteProviderConfig) -> CoreResult<String> {
    serde_json::to_string(config)
        .map_err(|_| CoreError::internal("remote provider metadata is invalid"))
}

fn empty_snapshot() -> RemoteProviderConfigSnapshot {
    RemoteProviderConfigSnapshot {
        provider_configured: false,
        provider_verified: false,
        remote_provider_enabled: false,
        provider: None,
        model_id: None,
        endpoint_url: None,
        credential_configured: false,
        feature_scope: Vec::new(),
        updated_at: None,
        disabled_reason: Some("Remote provider is not configured".to_owned()),
    }
}

fn provider_configured(config: &StoredRemoteProviderConfig) -> bool {
    !config.model_id.is_empty() && !config.key_reference.is_empty()
}

fn disabled_reason(config: &StoredRemoteProviderConfig) -> Option<String> {
    if !provider_configured(config) {
        Some("Remote provider is not configured".to_owned())
    } else if !config.provider_verified {
        Some("Remote provider has not been verified".to_owned())
    } else if !config.remote_provider_enabled {
        Some("Remote provider is disabled".to_owned())
    } else if config.feature_scope.is_empty() {
        Some("Remote provider feature scope is empty".to_owned())
    } else {
        None
    }
}

pub(super) fn deserialize_stored_config(
    serialized: &str,
) -> CoreResult<StoredRemoteProviderConfig> {
    serde_json::from_str(serialized)
        .map_err(|_| CoreError::config("remote provider metadata is invalid"))
}
