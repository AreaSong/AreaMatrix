use serde::{Deserialize, Serialize};

use super::repository::ContentLocale;

/// Filesystem event kind sent from the platform layer.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ExternalEventKind {
    /// A path was created.
    Created,
    /// A path was externally removed and should be reflected as a soft delete in metadata.
    Removed,
    /// A path was modified.
    Modified,
    /// A path was renamed.
    Renamed,
}

/// External filesystem event from the platform layer.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ExternalEvent {
    /// Repository-relative or absolute path supplied by the platform layer.
    pub path: String,
    /// Event kind.
    pub kind: ExternalEventKind,
    /// Platform filesystem event identifier.
    pub fs_event_id: i64,
}

/// One legacy external-sync receipt whose content locale must be recovered.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExternalSyncLocaleRecoveryReceipt {
    /// Filesystem event identifier captured by the original sync window.
    pub event_id: i64,
    /// Original event kind.
    pub kind: ExternalEventKind,
    /// Repository-relative event path, preserved verbatim.
    pub path: String,
}

/// Read-only plan binding recovery to one repository cursor and exact receipt set.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExternalSyncLocaleRecoveryPlan {
    /// Opaque token required by the mutation call.
    pub recovery_token: String,
    /// Cursor observed while the plan was created.
    pub cursor: Option<i64>,
    /// Stable, sorted legacy receipt set covered by the token.
    pub receipts: Vec<ExternalSyncLocaleRecoveryReceipt>,
}

/// Result of explicitly assigning a concrete locale to legacy receipts.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExternalSyncLocaleRecoveryReport {
    /// Number of receipts updated atomically.
    pub recovered_receipts: i64,
    /// Concrete locale selected by the user.
    pub content_locale: ContentLocale,
}

/// Summary of external-change synchronization.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncResult {
    /// Number of created paths detected.
    pub detected_creates: i64,
    /// Number of renames detected.
    pub detected_renames: i64,
    /// Number of removed paths reflected as deleted metadata rows.
    pub detected_deletes: i64,
    /// Number of modifications detected.
    pub detected_modifies: i64,
    /// Human-readable errors.
    pub errors: Vec<String>,
}
