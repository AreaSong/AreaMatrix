use serde::{Deserialize, Serialize};

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
