use serde::{Deserialize, Serialize};

/// Filter used when listing files.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FileFilter {
    /// Optional category slug.
    pub category: Option<String>,
    /// Whether deleted entries should be included.
    pub include_deleted: Option<bool>,
    /// Lower import timestamp bound.
    pub imported_after: Option<i64>,
    /// Upper import timestamp bound.
    pub imported_before: Option<i64>,
    /// Maximum number of rows to return.
    pub limit: i64,
    /// Offset for paginated reads.
    pub offset: i64,
}

/// Filter used when listing change-log entries.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ChangeFilter {
    /// Optional file identifier.
    pub file_id: Option<i64>,
    /// Optional category slug.
    pub category: Option<String>,
    /// Optional exact action string such as `imported`, `renamed`, or `external_modified`.
    pub action: Option<String>,
    /// Lower `occurred_at` timestamp bound, inclusive.
    pub since: Option<i64>,
    /// Upper `occurred_at` timestamp bound, exclusive.
    pub until: Option<i64>,
    /// Maximum number of rows to return.
    pub limit: i64,
    /// Offset for paginated reads.
    pub offset: i64,
}

/// A user-visible change-log entry.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ChangeLogEntry {
    /// Stable database identifier.
    pub id: i64,
    /// Optional related file identifier.
    pub file_id: Option<i64>,
    /// Filename snapshot for display.
    pub filename: String,
    /// Category snapshot for display.
    pub category: String,
    /// Action string.
    pub action: String,
    /// JSON detail payload that callers may parse for action-specific metadata.
    pub detail_json: String,
    /// Unix timestamp for the event.
    pub occurred_at: i64,
}
