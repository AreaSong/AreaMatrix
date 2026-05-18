use std::path::{Path, PathBuf};

use crate::{
    CoreError, CoreResult, ICloudConflictPreviewReport, ICloudConflictPreviewStatus,
    ICloudConflictResolution, ICloudConflictResolutionOption, ICloudConflictVersionMetadata,
    ICloudConflictVersionRole,
};

use super::{paths::map_io_error, types::VersionState};

pub(super) fn preview_report(
    conflict_id: String,
    versions: Vec<VersionState>,
    trash_available: bool,
) -> ICloudConflictPreviewReport {
    let metadata_complete = has_complete_pair(&versions);
    let can_resolve_destructive = metadata_complete && trash_available;
    ICloudConflictPreviewReport {
        conflict_id,
        versions: versions.into_iter().map(version_metadata).collect(),
        default_resolution: ICloudConflictResolution::KeepBoth,
        resolution_options: resolution_options(metadata_complete, trash_available),
        metadata_complete,
        trash_available,
        can_keep_both: true,
        can_resolve_destructive,
        blocked_reason: blocked_reason(metadata_complete, trash_available),
    }
}

pub(super) fn ensure_resolution_enabled(
    preview: &ICloudConflictPreviewReport,
    resolution: &ICloudConflictResolution,
) -> CoreResult<()> {
    let Some(option) = preview
        .resolution_options
        .iter()
        .find(|option| &option.resolution == resolution)
    else {
        return Err(CoreError::conflict("unsupported resolution"));
    };
    if option.enabled {
        Ok(())
    } else {
        Err(CoreError::conflict(
            option
                .disabled_reason
                .clone()
                .unwrap_or_else(|| "resolution disabled".to_owned()),
        ))
    }
}

pub(super) fn trash_available() -> CoreResult<bool> {
    let Some(home) = std::env::var_os("HOME") else {
        return Ok(false);
    };
    let trash_dir = PathBuf::from(home).join(".Trash");
    if trash_dir.try_exists().map_err(map_io_error)? {
        return writable_dir(&trash_dir);
    }
    match trash_dir.parent() {
        Some(parent) => writable_dir(parent),
        None => Ok(false),
    }
}

fn version_metadata(version: VersionState) -> ICloudConflictVersionMetadata {
    ICloudConflictVersionMetadata {
        version_id: version_id(&version.role),
        role: version.role,
        path: version.relative_path,
        modified_at: Some(version.modified_at),
        size_bytes: Some(version.size_bytes),
        hash_sha256: Some(version.hash_sha256),
        preview_summary: Some(preview_summary(&version.absolute_path, version.size_bytes)),
        preview_status: ICloudConflictPreviewStatus::MetadataOnly,
    }
}

fn version_id(role: &ICloudConflictVersionRole) -> String {
    match role {
        ICloudConflictVersionRole::Original => "original".to_owned(),
        ICloudConflictVersionRole::ConflictedCopy => "conflicted-copy".to_owned(),
    }
}

fn preview_summary(path: &Path, size_bytes: i64) -> String {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("version");
    format!("{name} · {size_bytes} bytes")
}

fn has_complete_pair(versions: &[VersionState]) -> bool {
    let has_original = versions
        .iter()
        .any(|version| version.role == ICloudConflictVersionRole::Original);
    let has_conflicted = versions
        .iter()
        .any(|version| version.role == ICloudConflictVersionRole::ConflictedCopy);
    has_original && has_conflicted
}

fn resolution_options(
    metadata_complete: bool,
    trash_available: bool,
) -> Vec<ICloudConflictResolutionOption> {
    vec![
        ICloudConflictResolutionOption {
            resolution: ICloudConflictResolution::KeepBoth,
            destructive: false,
            requires_trash: false,
            enabled: true,
            disabled_reason: None,
        },
        destructive_option(
            ICloudConflictResolution::KeepOriginal,
            metadata_complete,
            trash_available,
        ),
        destructive_option(
            ICloudConflictResolution::KeepConflictedCopy,
            metadata_complete,
            trash_available,
        ),
    ]
}

fn destructive_option(
    resolution: ICloudConflictResolution,
    metadata_complete: bool,
    trash_available: bool,
) -> ICloudConflictResolutionOption {
    let disabled_reason = destructive_disabled_reason(metadata_complete, trash_available);
    ICloudConflictResolutionOption {
        resolution,
        destructive: true,
        requires_trash: true,
        enabled: disabled_reason.is_none(),
        disabled_reason,
    }
}

fn destructive_disabled_reason(metadata_complete: bool, trash_available: bool) -> Option<String> {
    if !metadata_complete {
        Some("Metadata incomplete".to_owned())
    } else if !trash_available {
        Some("Trash unavailable".to_owned())
    } else {
        None
    }
}

fn blocked_reason(metadata_complete: bool, trash_available: bool) -> Option<String> {
    destructive_disabled_reason(metadata_complete, trash_available)
}

fn writable_dir(path: &Path) -> CoreResult<bool> {
    let metadata = path.metadata().map_err(map_io_error)?;
    Ok(metadata.is_dir() && !metadata.permissions().readonly())
}
