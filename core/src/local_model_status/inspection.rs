//! Read-only local model manifest, folder, and runtime inspection for C3-02.

use std::path::Path;

use serde::Deserialize;

use crate::{
    CoreError, CoreResult, LocalModelAvailability, LocalModelFeatureStatus,
    LocalModelFolderLocation, LocalModelStatusRequest, LocalModelStatusSnapshot,
};

use super::{
    diagnostics::{diagnostics, sanitize_optional_str},
    filesystem::{directory_size, inspect_folder, read_text_if_exists},
    snapshot::{
        default_feature_statuses, feature_kind, snapshot, unavailable_reason, SnapshotDraft,
    },
};

const MANIFEST_FILE: &str = "manifest.json";
const RUNTIME_HEALTH_FILE: &str = "runtime-health.json";

#[derive(Debug, Deserialize)]
struct ModelManifest {
    model_id: Option<String>,
    version: Option<String>,
    compatible: Option<bool>,
    min_core_version: Option<String>,
    min_area_matrix_version: Option<String>,
    availability: Option<String>,
    last_error: Option<String>,
    diagnostics_summary: Option<String>,
    features: Option<Vec<ModelManifestFeature>>,
}

#[derive(Debug, Deserialize)]
struct ModelManifestFeature {
    feature: String,
    available: Option<bool>,
    unavailable_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RuntimeHealth {
    status: Option<String>,
    last_error: Option<String>,
    diagnostics_summary: Option<String>,
}

enum ManifestRead {
    Missing,
    Invalid(String),
    Present(ModelManifest),
}

enum RuntimeRead {
    Missing,
    Invalid(String),
    Present(RuntimeHealth),
}

pub(super) fn inspect_local_model(
    request: &LocalModelStatusRequest,
    model_path: &Path,
    checked_at: i64,
) -> CoreResult<LocalModelStatusSnapshot> {
    let folder = inspect_folder(model_path)?;
    if !folder.exists {
        return Ok(snapshot(SnapshotDraft {
            request,
            availability: LocalModelAvailability::NotInstalled,
            version: None,
            size_bytes: None,
            last_error: Some("Model is not installed".to_owned()),
            checked_at,
            diagnostics_summary: diagnostics("missing", "not checked", "missing", None, None),
            feature_statuses: None,
        }));
    }
    if !folder.openable {
        return Ok(snapshot(SnapshotDraft {
            request,
            availability: LocalModelAvailability::PathUnreadable,
            version: None,
            size_bytes: None,
            last_error: folder.unavailable_reason,
            checked_at,
            diagnostics_summary: diagnostics("unknown", "not checked", "unreadable", None, None),
            feature_statuses: None,
        }));
    }

    let size_bytes = Some(directory_size(model_path)?);
    let runtime = read_runtime_health(model_path)?;
    match read_manifest(model_path)? {
        ManifestRead::Missing => Ok(snapshot(SnapshotDraft {
            request,
            availability: LocalModelAvailability::NotInstalled,
            version: None,
            size_bytes,
            last_error: Some("Model manifest is missing".to_owned()),
            checked_at,
            diagnostics_summary: diagnostics(
                "missing",
                runtime_label(&runtime),
                "readable",
                size_bytes,
                None,
            ),
            feature_statuses: None,
        })),
        ManifestRead::Invalid(reason) => Ok(snapshot(SnapshotDraft {
            request,
            availability: LocalModelAvailability::Corrupted,
            version: None,
            size_bytes,
            last_error: Some(reason.clone()),
            checked_at,
            diagnostics_summary: diagnostics(
                "invalid",
                runtime_label(&runtime),
                "readable",
                size_bytes,
                Some(&reason),
            ),
            feature_statuses: None,
        })),
        ManifestRead::Present(manifest) => {
            manifest_snapshot(request, manifest, runtime, size_bytes, checked_at)
        }
    }
}

pub(super) fn locate_model_folder(
    model_id: &str,
    folder_path: &Path,
) -> CoreResult<LocalModelFolderLocation> {
    let inspection = inspect_folder(folder_path)?;
    Ok(LocalModelFolderLocation {
        model_id: model_id.to_owned(),
        folder_path: folder_path.to_string_lossy().into_owned(),
        exists: inspection.exists,
        readable: inspection.readable,
        openable: inspection.openable,
        unavailable_reason: inspection.unavailable_reason,
    })
}

fn manifest_snapshot(
    request: &LocalModelStatusRequest,
    manifest: ModelManifest,
    runtime: RuntimeRead,
    size_bytes: Option<i64>,
    checked_at: i64,
) -> CoreResult<LocalModelStatusSnapshot> {
    if manifest
        .model_id
        .as_deref()
        .is_some_and(|id| id != request.model_id)
    {
        return Ok(corrupted_snapshot(
            request,
            size_bytes,
            checked_at,
            "Model manifest id does not match request",
            &runtime,
        ));
    }
    if version_incompatible(&manifest) {
        return snapshot_from_manifest(
            request,
            &manifest,
            LocalModelAvailability::VersionIncompatible,
            size_bytes,
            checked_at,
            &runtime,
        );
    }
    let availability = match manifest_availability(&manifest, &runtime) {
        Ok(availability) => availability,
        Err(reason) => {
            return Ok(invalid_status_snapshot(
                request, &manifest, size_bytes, checked_at, &reason, &runtime,
            ));
        }
    };
    snapshot_from_manifest(
        request,
        &manifest,
        availability,
        size_bytes,
        checked_at,
        &runtime,
    )
}

fn snapshot_from_manifest(
    request: &LocalModelStatusRequest,
    manifest: &ModelManifest,
    availability: LocalModelAvailability,
    size_bytes: Option<i64>,
    checked_at: i64,
    runtime: &RuntimeRead,
) -> CoreResult<LocalModelStatusSnapshot> {
    let runtime_error = runtime_last_error(runtime);
    let last_error =
        sanitize_optional_str(manifest.last_error.as_deref().or(runtime_error.as_deref()));
    let summary = diagnostics(
        "ok",
        runtime_label(runtime),
        "readable",
        size_bytes,
        last_error
            .as_deref()
            .or(manifest.diagnostics_summary.as_deref()),
    );
    let features = manifest_features(manifest, &availability)?;
    Ok(snapshot(SnapshotDraft {
        request,
        availability,
        version: manifest.version.clone(),
        size_bytes,
        last_error,
        checked_at,
        diagnostics_summary: summary,
        feature_statuses: Some(features),
    }))
}

fn invalid_status_snapshot(
    request: &LocalModelStatusRequest,
    manifest: &ModelManifest,
    size_bytes: Option<i64>,
    checked_at: i64,
    reason: &str,
    runtime: &RuntimeRead,
) -> LocalModelStatusSnapshot {
    let availability = if reason.contains("manifest") {
        LocalModelAvailability::Corrupted
    } else {
        LocalModelAvailability::RuntimeFailed
    };
    snapshot(SnapshotDraft {
        request,
        availability,
        version: manifest.version.clone(),
        size_bytes,
        last_error: sanitize_optional_str(Some(reason)),
        checked_at,
        diagnostics_summary: diagnostics(
            manifest_status_for_invalid(reason),
            runtime_label(runtime),
            "readable",
            size_bytes,
            Some(reason),
        ),
        feature_statuses: None,
    })
}

fn manifest_status_for_invalid(reason: &str) -> &'static str {
    if reason.contains("manifest") {
        "invalid"
    } else {
        "ok"
    }
}

fn read_manifest(model_path: &Path) -> CoreResult<ManifestRead> {
    let manifest_path = model_path.join(MANIFEST_FILE);
    match read_text_if_exists(&manifest_path)? {
        Some(content) => match serde_json::from_str::<ModelManifest>(&content) {
            Ok(manifest) => Ok(ManifestRead::Present(manifest)),
            Err(_) => Ok(ManifestRead::Invalid(
                "Model manifest cannot be parsed".to_owned(),
            )),
        },
        None => Ok(ManifestRead::Missing),
    }
}

fn read_runtime_health(model_path: &Path) -> CoreResult<RuntimeRead> {
    let health_path = model_path.join(RUNTIME_HEALTH_FILE);
    match read_text_if_exists(&health_path)? {
        Some(content) => match serde_json::from_str::<RuntimeHealth>(&content) {
            Ok(health) => Ok(RuntimeRead::Present(health)),
            Err(_) => Ok(RuntimeRead::Invalid(
                "Runtime health metadata cannot be parsed".to_owned(),
            )),
        },
        None => Ok(RuntimeRead::Missing),
    }
}

fn manifest_features(
    manifest: &ModelManifest,
    availability: &LocalModelAvailability,
) -> CoreResult<Vec<LocalModelFeatureStatus>> {
    let ready = matches!(availability, LocalModelAvailability::Ready);
    let mut statuses = default_feature_statuses(availability);
    for feature in manifest.features.as_deref().unwrap_or_default() {
        let Some(kind) = feature_kind(&feature.feature) else {
            return Err(CoreError::config(
                "local model manifest contains unknown feature",
            ));
        };
        let available = ready && feature.available.unwrap_or(false);
        let unavailable_reason = if available {
            None
        } else {
            sanitize_optional_str(feature.unavailable_reason.as_deref())
                .or_else(|| Some(unavailable_reason(availability)))
        };
        replace_feature_status(
            &mut statuses,
            LocalModelFeatureStatus {
                feature: kind,
                available,
                unavailable_reason,
            },
        );
    }
    Ok(statuses)
}

fn replace_feature_status(
    statuses: &mut [LocalModelFeatureStatus],
    replacement: LocalModelFeatureStatus,
) {
    if let Some(status) = statuses
        .iter_mut()
        .find(|status| status.feature == replacement.feature)
    {
        *status = replacement;
    }
}

fn manifest_availability(
    manifest: &ModelManifest,
    runtime: &RuntimeRead,
) -> Result<LocalModelAvailability, String> {
    if let Some(value) = manifest.availability.as_deref() {
        return availability_from_str(value)
            .ok_or_else(|| "manifest availability is invalid".to_owned());
    }
    match runtime {
        RuntimeRead::Present(health) => runtime_availability(health),
        RuntimeRead::Invalid(_) => Err("runtime health metadata is invalid".to_owned()),
        RuntimeRead::Missing => Ok(LocalModelAvailability::Ready),
    }
}

fn runtime_availability(health: &RuntimeHealth) -> Result<LocalModelAvailability, String> {
    match health.status.as_deref().unwrap_or("ready") {
        "ready" | "Ready" => Ok(LocalModelAvailability::Ready),
        "checking" | "Checking" => Ok(LocalModelAvailability::Checking),
        "verifying" | "Verifying" => Ok(LocalModelAvailability::Verifying),
        "loading" | "Loading" => Ok(LocalModelAvailability::Loading),
        "failed" | "runtime_failed" | "RuntimeFailed" => Ok(LocalModelAvailability::RuntimeFailed),
        "error" | "Error" => Ok(LocalModelAvailability::Error),
        _ => Err("runtime health status is invalid".to_owned()),
    }
}

fn availability_from_str(value: &str) -> Option<LocalModelAvailability> {
    match value {
        "Unknown" | "unknown" => Some(LocalModelAvailability::Unknown),
        "Ready" | "ready" => Some(LocalModelAvailability::Ready),
        "NotInstalled" | "not_installed" => Some(LocalModelAvailability::NotInstalled),
        "PathUnreadable" | "path_unreadable" => Some(LocalModelAvailability::PathUnreadable),
        "VersionIncompatible" | "version_incompatible" => {
            Some(LocalModelAvailability::VersionIncompatible)
        }
        "Checking" | "checking" => Some(LocalModelAvailability::Checking),
        "Verifying" | "verifying" => Some(LocalModelAvailability::Verifying),
        "Loading" | "loading" => Some(LocalModelAvailability::Loading),
        "Corrupted" | "corrupted" => Some(LocalModelAvailability::Corrupted),
        "RuntimeFailed" | "runtime_failed" => Some(LocalModelAvailability::RuntimeFailed),
        "Error" | "error" => Some(LocalModelAvailability::Error),
        _ => None,
    }
}

fn version_incompatible(manifest: &ModelManifest) -> bool {
    manifest.compatible == Some(false)
        || manifest.min_core_version.is_some()
        || manifest.min_area_matrix_version.is_some()
}

fn corrupted_snapshot(
    request: &LocalModelStatusRequest,
    size_bytes: Option<i64>,
    checked_at: i64,
    reason: &str,
    runtime: &RuntimeRead,
) -> LocalModelStatusSnapshot {
    snapshot(SnapshotDraft {
        request,
        availability: LocalModelAvailability::Corrupted,
        version: None,
        size_bytes,
        last_error: Some(reason.to_owned()),
        checked_at,
        diagnostics_summary: diagnostics(
            "invalid",
            runtime_label(runtime),
            "readable",
            size_bytes,
            Some(reason),
        ),
        feature_statuses: None,
    })
}

fn runtime_label(runtime: &RuntimeRead) -> &str {
    match runtime {
        RuntimeRead::Missing => "missing",
        RuntimeRead::Invalid(reason) => {
            let _ = reason;
            "invalid"
        }
        RuntimeRead::Present(health) => health.status.as_deref().unwrap_or("ready"),
    }
}

fn runtime_last_error(runtime: &RuntimeRead) -> Option<String> {
    match runtime {
        RuntimeRead::Invalid(reason) => Some(reason.clone()),
        RuntimeRead::Present(health) => health
            .last_error
            .as_deref()
            .or(health.diagnostics_summary.as_deref())
            .and_then(|value| sanitize_optional_str(Some(value))),
        RuntimeRead::Missing => None,
    }
}
