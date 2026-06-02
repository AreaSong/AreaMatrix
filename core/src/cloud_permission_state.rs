//! C4-08 cloud storage permission and placeholder state contract.

use std::{fs, io, path::Path};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

/// Cloud storage provider inferred from an authorized repository path.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CloudStorageProviderKind {
    /// No known cloud provider marker was detected in the repository path.
    Local,
    /// iCloud Drive or CloudDocs-managed path.
    ICloudDrive,
    /// OneDrive-managed path.
    OneDrive,
    /// The provider cannot be identified from Core-visible path metadata.
    Unknown,
}

/// Coarse cloud-storage risk level consumed by recovery and notice pages.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CloudStorageRiskLevel {
    /// No cloud-specific risk is detected.
    NoRisk,
    /// A mild path or provider caveat exists.
    Low,
    /// Cloud sync timing, placeholder, or permission caveats may affect access.
    Medium,
    /// The current state should block writes until the platform layer recovers access.
    High,
    /// Core cannot determine the risk from platform-neutral metadata.
    Unknown,
}

/// Placeholder availability state for cloud-backed paths.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CloudPlaceholderState {
    /// No placeholder marker is visible to Core.
    NotPlaceholder,
    /// The path or required metadata appears to be a cloud placeholder.
    Placeholder,
    /// Placeholder state needs platform-specific inspection.
    Unknown,
}

/// Permission state for the repository path.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CloudPermissionState {
    /// Core can inspect the repository path.
    Accessible,
    /// Core-visible filesystem permission is denied.
    PermissionDenied,
    /// Platform-owned access, such as a security-scoped bookmark, has expired.
    AccessExpired,
    /// Permission state needs platform-specific inspection.
    Unknown,
}

/// Structured C4-08 cloud state returned to iOS and Windows recovery surfaces.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CloudStorageState {
    /// Repository path that was inspected by Core.
    pub repo_path: String,
    /// Cloud provider inferred from the path.
    pub provider_kind: CloudStorageProviderKind,
    /// Coarse risk level for cloud permission, placeholder, or sync-timing caveats.
    pub risk: CloudStorageRiskLevel,
    /// Placeholder state visible to Core.
    pub placeholder_state: CloudPlaceholderState,
    /// Permission state visible to Core.
    pub permission_state: CloudPermissionState,
    /// Display-safe summary for logs or platform notice copy.
    pub status_summary: String,
    /// Structured risk reasons. UI may render these without parsing `status_summary`.
    pub risk_reasons: Vec<String>,
    /// Whether retrying the same read-only check may recover the state.
    pub can_retry: bool,
    /// Whether the platform shell should request folder access again.
    pub requires_reconnect: bool,
}

/// Detects C4-08 cloud provider, risk, placeholder, and permission state.
///
/// The check is platform-neutral and read-only. It inspects only the supplied
/// path shape and basic filesystem metadata. iCloud, OneDrive, document
/// picker, SDK, settings, and security-scoped bookmark recovery stay in the
/// platform layer.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the input is empty or points
/// inside AreaMatrix metadata, `CoreError::ICloudPlaceholder { path }` when the
/// repository path itself is a visible placeholder,
/// `CoreError::PermissionDenied { path }` when metadata or directory listing is
/// blocked, and `CoreError::Io { message }` for other filesystem inspection
/// failures.
pub(crate) fn detect_cloud_storage_state(repo_path: String) -> CoreResult<CloudStorageState> {
    let path = Path::new(&repo_path);
    validate_path(path, &repo_path)?;
    reject_placeholder_path(path, &repo_path)?;
    ensure_inspectable_directory(path)?;

    let provider_kind = provider_kind(path);
    Ok(state_for_provider(repo_path, provider_kind))
}

fn validate_path(path: &Path, repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("repository path is required"));
    }
    if path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .eq_ignore_ascii_case(".areamatrix")
    }) {
        return Err(CoreError::invalid_path(
            "cloud state detection requires a repository root, not .areamatrix metadata",
        ));
    }
    Ok(())
}

fn reject_placeholder_path(path: &Path, repo_path: &str) -> CoreResult<()> {
    if path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .to_ascii_lowercase()
            .ends_with(".icloud")
    }) {
        return Err(CoreError::icloud_placeholder(repo_path));
    }
    Ok(())
}

fn ensure_inspectable_directory(path: &Path) -> CoreResult<()> {
    let metadata = fs::metadata(path).map_err(|error| map_fs_error(path, error))?;
    if !metadata.is_dir() {
        return Err(CoreError::io("cloud state path is not a directory"));
    }
    fs::read_dir(path).map_err(|error| map_fs_error(path, error))?;
    Ok(())
}

fn provider_kind(path: &Path) -> CloudStorageProviderKind {
    let components = path
        .components()
        .map(|component| component.as_os_str().to_string_lossy().to_ascii_lowercase())
        .collect::<Vec<_>>();

    if components.iter().any(|component| {
        component == "icloud drive"
            || component == "mobile documents"
            || component.contains("com~apple~clouddocs")
            || component.contains("icloud")
    }) {
        return CloudStorageProviderKind::ICloudDrive;
    }

    if components
        .iter()
        .any(|component| component.contains("onedrive") || component.contains("one drive"))
    {
        return CloudStorageProviderKind::OneDrive;
    }

    CloudStorageProviderKind::Local
}

fn state_for_provider(
    repo_path: String,
    provider_kind: CloudStorageProviderKind,
) -> CloudStorageState {
    let (risk, status_summary, risk_reasons) = match provider_kind {
        CloudStorageProviderKind::Local => (
            CloudStorageRiskLevel::NoRisk,
            "No cloud storage provider was detected from the repository path.",
            Vec::new(),
        ),
        CloudStorageProviderKind::ICloudDrive => (
            CloudStorageRiskLevel::Medium,
            "iCloud Drive path detected; platform layer owns iCloud availability and downloads.",
            vec![
                "iCloud may expose placeholder files before they are downloaded.".to_owned(),
                "Core does not enable iCloud Drive or trigger downloads.".to_owned(),
            ],
        ),
        CloudStorageProviderKind::OneDrive => (
            CloudStorageRiskLevel::Medium,
            "OneDrive path detected; OneDrive controls sync timing and conflict copies.",
            vec![
                "Files may appear before cloud sync has completed.".to_owned(),
                "Core does not use the OneDrive SDK or change OneDrive settings.".to_owned(),
            ],
        ),
        CloudStorageProviderKind::Unknown => (
            CloudStorageRiskLevel::Unknown,
            "Cloud provider state cannot be determined from Core-visible metadata.",
            vec!["Platform-specific inspection is required.".to_owned()],
        ),
    };

    CloudStorageState {
        repo_path,
        provider_kind,
        risk,
        placeholder_state: CloudPlaceholderState::NotPlaceholder,
        permission_state: CloudPermissionState::Accessible,
        status_summary: status_summary.to_owned(),
        risk_reasons,
        can_retry: false,
        requires_reconnect: false,
    }
}

fn map_fs_error(path: &Path, error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => {
            CoreError::permission_denied(path.to_string_lossy().into_owned())
        }
        _ => CoreError::io(error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_kind_detects_icloud_and_onedrive_path_markers() {
        assert_eq!(
            provider_kind(Path::new(
                "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Repo"
            )),
            CloudStorageProviderKind::ICloudDrive
        );
        assert_eq!(
            provider_kind(Path::new("C:/Users/me/OneDrive/AreaMatrix")),
            CloudStorageProviderKind::OneDrive
        );
        assert_eq!(
            provider_kind(Path::new("/Users/me/Documents/AreaMatrix")),
            CloudStorageProviderKind::Local
        );
    }
}
