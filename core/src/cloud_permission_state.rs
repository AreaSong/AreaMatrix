//! C4-08 cloud storage permission and placeholder state contract.

use std::{
    fs, io,
    path::{Path, PathBuf},
};

use rusqlite::{Connection, ErrorCode, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";
const ONEDRIVE_NOTICE_ACK_KEY: &str = "onedrive_risk_notice_acknowledged";

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

/// Primary cloud-storage action recommended to the platform shell.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CloudStorageRecommendedAction {
    /// No provider-specific action is recommended.
    None,
    /// Show and persist the provider risk acknowledgement before continuing.
    AcknowledgeNotice,
    /// Retry the same read-only provider status check.
    RetryStatusCheck,
    /// Ask the platform shell to reacquire folder access.
    ReconnectFolder,
    /// Offer a local-folder picker branch.
    ChooseLocalFolder,
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
    /// Primary action for cloud permission or OneDrive risk notice UI.
    pub recommended_action: CloudStorageRecommendedAction,
    /// Whether the OneDrive notice must be acknowledged before continuing.
    pub requires_notice_acknowledgement: bool,
    /// Whether Core-visible metadata already records the OneDrive notice acknowledgement.
    pub notice_acknowledged: bool,
    /// Whether retrying the same read-only check may recover the state.
    pub can_retry: bool,
    /// Whether the platform shell should request folder access again.
    pub requires_reconnect: bool,
}

/// Detects C4-08 cloud provider state and C4-14 OneDrive risk state.
///
/// The check is platform-neutral and read-only. It inspects only the supplied
/// path shape and basic filesystem metadata. iCloud, OneDrive, document
/// picker, SDK, settings, acknowledgement UI, and security-scoped bookmark
/// recovery stay in the platform layer.
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
    let notice_acknowledged = notice_acknowledged(path, &provider_kind)?;
    Ok(state_for_provider(
        repo_path,
        provider_kind,
        notice_acknowledged,
    ))
}

/// Persists the C4-14 OneDrive notice acknowledgement and returns refreshed state.
///
/// The acknowledgement is stored only in initialized repository metadata. This
/// keeps the notice flow from implicitly creating `.areamatrix/` during
/// choose-repo or adopt preflight screens.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the input is empty or points
/// inside AreaMatrix metadata, `CoreError::ICloudPlaceholder { path }` when the
/// repository path itself is a visible placeholder,
/// `CoreError::PermissionDenied { path }` when metadata, directory listing, or
/// DB writing is blocked, and `CoreError::Io { message }` for missing
/// initialized metadata or other acknowledgement persistence failures.
pub(crate) fn acknowledge_onedrive_risk_notice(repo_path: String) -> CoreResult<CloudStorageState> {
    let path = Path::new(&repo_path);
    validate_path(path, &repo_path)?;
    reject_placeholder_path(path, &repo_path)?;
    ensure_inspectable_directory(path)?;

    let provider_kind = provider_kind(path);
    if provider_kind == CloudStorageProviderKind::OneDrive {
        persist_onedrive_notice_acknowledgement(path)?;
    }

    let notice_acknowledged = notice_acknowledged(path, &provider_kind)?;
    Ok(state_for_provider(
        repo_path,
        provider_kind,
        notice_acknowledged,
    ))
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
    let normalized_path = path.to_string_lossy().to_ascii_lowercase();

    if components.iter().any(|component| {
        component == "icloud drive"
            || component == "mobile documents"
            || component.contains("com~apple~clouddocs")
            || component.contains("icloud")
    }) || normalized_path.contains("icloud drive")
        || normalized_path.contains("mobile documents")
        || normalized_path.contains("com~apple~clouddocs")
    {
        return CloudStorageProviderKind::ICloudDrive;
    }

    if components
        .iter()
        .any(|component| component.contains("onedrive") || component.contains("one drive"))
        || normalized_path.contains("onedrive")
        || normalized_path.contains("one drive")
    {
        return CloudStorageProviderKind::OneDrive;
    }

    CloudStorageProviderKind::Local
}

fn state_for_provider(
    repo_path: String,
    provider_kind: CloudStorageProviderKind,
    notice_acknowledged: bool,
) -> CloudStorageState {
    let (risk, status_summary, risk_reasons) = match &provider_kind {
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
                "Conflict copies may be created when multiple devices edit the same file."
                    .to_owned(),
                "Core does not use the OneDrive SDK or change OneDrive settings.".to_owned(),
            ],
        ),
        CloudStorageProviderKind::Unknown => (
            CloudStorageRiskLevel::Unknown,
            "Cloud provider state cannot be determined from Core-visible metadata.",
            vec!["Platform-specific inspection is required.".to_owned()],
        ),
    };

    let recommended_action = recommended_action(&provider_kind, notice_acknowledged);
    let requires_notice_acknowledgement =
        provider_kind == CloudStorageProviderKind::OneDrive && !notice_acknowledged;

    CloudStorageState {
        repo_path,
        provider_kind,
        risk,
        placeholder_state: CloudPlaceholderState::NotPlaceholder,
        permission_state: CloudPermissionState::Accessible,
        status_summary: status_summary.to_owned(),
        risk_reasons,
        recommended_action,
        requires_notice_acknowledgement,
        notice_acknowledged,
        can_retry: false,
        requires_reconnect: false,
    }
}

fn recommended_action(
    provider_kind: &CloudStorageProviderKind,
    notice_acknowledged: bool,
) -> CloudStorageRecommendedAction {
    match (provider_kind, notice_acknowledged) {
        (CloudStorageProviderKind::OneDrive, false) => {
            CloudStorageRecommendedAction::AcknowledgeNotice
        }
        _ => CloudStorageRecommendedAction::None,
    }
}

fn notice_acknowledged(path: &Path, provider_kind: &CloudStorageProviderKind) -> CoreResult<bool> {
    if provider_kind != &CloudStorageProviderKind::OneDrive {
        return Ok(false);
    }
    load_onedrive_notice_acknowledgement(path)
}

fn load_onedrive_notice_acknowledgement(repo_path: &Path) -> CoreResult<bool> {
    let Some(db_path) = existing_notice_db_path(repo_path)? else {
        return Ok(false);
    };

    let connection = Connection::open(&db_path).map_err(map_notice_metadata_db_error)?;
    let value = connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [ONEDRIVE_NOTICE_ACK_KEY],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(map_notice_metadata_db_error)?;
    value
        .as_deref()
        .map(parse_notice_acknowledgement)
        .unwrap_or(Ok(false))
}

fn persist_onedrive_notice_acknowledgement(repo_path: &Path) -> CoreResult<()> {
    let Some(db_path) = existing_notice_db_path(repo_path)? else {
        return Err(CoreError::io(
            "OneDrive notice acknowledgement requires initialized repository metadata",
        ));
    };

    let connection = Connection::open(&db_path).map_err(map_notice_metadata_db_error)?;
    connection
        .execute(
            "INSERT INTO repo_config (key, value, updated_at) \
             VALUES (?1, 'true', strftime('%s', 'now')) \
             ON CONFLICT(key) DO UPDATE SET \
             value = excluded.value, updated_at = excluded.updated_at",
            [ONEDRIVE_NOTICE_ACK_KEY],
        )
        .map_err(map_notice_metadata_db_error)?;
    Ok(())
}

fn existing_notice_db_path(repo_path: &Path) -> CoreResult<Option<PathBuf>> {
    let db_path = repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    match fs::metadata(&db_path) {
        Ok(metadata) if metadata.is_file() => Ok(Some(db_path)),
        Ok(_) => Err(CoreError::io(
            "OneDrive notice acknowledgement metadata is not a database file",
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(map_notice_metadata_io_error(&db_path, error)),
    }
}

fn map_notice_metadata_io_error(path: &Path, error: io::Error) -> CoreError {
    if error.kind() == io::ErrorKind::PermissionDenied {
        return CoreError::permission_denied(path.to_string_lossy().into_owned());
    }
    CoreError::io(format!(
        "OneDrive notice acknowledgement metadata is unavailable: {error}"
    ))
}

fn map_notice_metadata_db_error(error: rusqlite::Error) -> CoreError {
    if matches!(
        error,
        rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error {
                code: ErrorCode::PermissionDenied | ErrorCode::ReadOnly,
                ..
            },
            _
        )
    ) {
        return CoreError::permission_denied("OneDrive notice acknowledgement metadata");
    }

    CoreError::io(format!(
        "OneDrive notice acknowledgement metadata is unavailable: {error}"
    ))
}

fn parse_notice_acknowledgement(value: &str) -> CoreResult<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "acknowledged" => Ok(true),
        "0" | "false" | "" => Ok(false),
        _ => Err(CoreError::io(
            "OneDrive notice acknowledgement metadata is invalid",
        )),
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
            provider_kind(Path::new(
                "/tmp/C:\\Users\\me\\OneDrive - Example Org\\AreaMatrix"
            )),
            CloudStorageProviderKind::OneDrive
        );
        assert_eq!(
            provider_kind(Path::new("/Users/me/Documents/AreaMatrix")),
            CloudStorageProviderKind::Local
        );
    }
}
