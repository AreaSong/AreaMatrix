//! C4-12 platform watcher status contract types and entry point.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult, ExternalEventKind};

const MAX_STATUS_TEXT_LEN: usize = 512;
const MAX_RECENT_EVENTS: usize = 5;

/// Platform watcher backend that produced a health signal.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PlatformWatcherBackend {
    /// Windows ReadDirectoryChangesW watcher.
    ReadDirectoryChangesW,
    /// Linux inotify watcher.
    Inotify,
    /// Platform backend is not known to Core.
    Unknown,
}

/// Current lifecycle state for a platform watcher.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PlatformWatcherStatus {
    /// Watcher startup is in progress.
    Starting,
    /// Watcher is running and reporting events.
    Running,
    /// Watcher is intentionally paused or waiting for restart.
    Paused,
    /// Watcher reported a recoverable or blocking error.
    Error,
    /// Watcher backend is unavailable for the current repository.
    Unavailable,
}

/// Structured reason that explains watcher degradation without parsing text.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PlatformWatcherHealthReason {
    /// Repository path or watched subtree cannot be inspected.
    PermissionDenied,
    /// Watched path is missing or disconnected.
    PathMissing,
    /// Platform watcher backend is unavailable.
    BackendUnavailable,
    /// Repository metadata is locked or unavailable.
    DatabaseLocked,
    /// Linux inotify watch limit was exceeded.
    LimitExceeded,
    /// Network mount may not deliver reliable watcher events.
    NetworkMount,
    /// Cloud sync provider may emit event bursts or delayed changes.
    CloudSyncNoise,
    /// Platform supplied a reason Core cannot classify.
    Unknown,
}

/// Recent watcher event sample for diagnostic previews.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PlatformWatcherEventSample {
    /// Repository-relative or display-safe path for the event sample.
    pub path: String,
    /// Event kind as already normalized by the platform layer.
    pub kind: ExternalEventKind,
    /// Platform filesystem event identifier.
    pub fs_event_id: i64,
    /// Unix timestamp when the event was observed, when known.
    pub occurred_at: Option<i64>,
}

/// Platform-provided watcher health signal accepted by Core.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PlatformWatcherHealthSignal {
    /// Platform backend that produced this signal.
    pub backend: PlatformWatcherBackend,
    /// Current watcher lifecycle state.
    pub status: PlatformWatcherStatus,
    /// Path currently watched by the platform service.
    pub watched_path: String,
    /// Highest platform event id observed by the watcher, when known.
    pub last_event_id: Option<i64>,
    /// Unix timestamp for the latest observed watcher event, when known.
    pub last_event_at: Option<i64>,
    /// Highest event id successfully synchronized into Core metadata, when known.
    pub last_sync_event_id: Option<i64>,
    /// Unix timestamp for the latest successful Core sync, when known.
    pub last_sync_at: Option<i64>,
    /// Unix timestamp for the latest manual rescan, when known.
    pub last_rescan_at: Option<i64>,
    /// Number of platform events waiting for Core sync.
    pub pending_event_count: i64,
    /// Number of active platform watches, when the backend exposes it.
    pub watch_count: Option<i64>,
    /// Display-safe error summary supplied by the platform layer.
    pub error_summary: Option<String>,
    /// Structured health reasons for UI badges and disabled states.
    pub health_reasons: Vec<PlatformWatcherHealthReason>,
    /// Recent event samples for diagnostics. Core accepts at most five.
    pub recent_events: Vec<PlatformWatcherEventSample>,
    /// Unix timestamp when the platform captured this signal.
    pub reported_at: i64,
}

/// Normalized watcher snapshot returned to Windows and Linux watcher pages.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PlatformWatcherSnapshot {
    /// Repository path this watcher state belongs to.
    pub repo_path: String,
    /// Platform backend that produced this snapshot.
    pub backend: PlatformWatcherBackend,
    /// Current watcher lifecycle state.
    pub status: PlatformWatcherStatus,
    /// Path currently watched by the platform service.
    pub watched_path: String,
    /// Highest platform event id observed by the watcher, when known.
    pub last_event_id: Option<i64>,
    /// Unix timestamp for the latest observed watcher event, when known.
    pub last_event_at: Option<i64>,
    /// Highest event id successfully synchronized into Core metadata, when known.
    pub last_sync_event_id: Option<i64>,
    /// Unix timestamp for the latest successful Core sync, when known.
    pub last_sync_at: Option<i64>,
    /// Unix timestamp for the latest manual rescan, when known.
    pub last_rescan_at: Option<i64>,
    /// Number of platform events waiting for Core sync.
    pub pending_event_count: i64,
    /// Number of active platform watches, when the backend exposes it.
    pub watch_count: Option<i64>,
    /// Display-safe error summary for status pages and diagnostics.
    pub error_summary: Option<String>,
    /// Structured health reasons for UI badges and disabled states.
    pub health_reasons: Vec<PlatformWatcherHealthReason>,
    /// Recent event samples for diagnostics.
    pub recent_events: Vec<PlatformWatcherEventSample>,
    /// Unix timestamp when the platform captured this snapshot.
    pub reported_at: i64,
}

/// Records a platform watcher health signal and returns the normalized snapshot.
///
/// This C4-12 contract is platform neutral. The platform layer owns
/// ReadDirectoryChangesW/inotify startup, restart, debounce, and event capture.
/// Core accepts only a sanitized health signal and must not start watchers,
/// trigger manual rescan, inspect user file contents, or mutate user files.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when the signal is invalid or watcher
/// health metadata is unavailable. Returns `CoreError::Io { message }` for
/// AreaMatrix-owned metadata I/O failures.
pub(crate) fn record_watcher_health(
    repo_path: String,
    signal: PlatformWatcherHealthSignal,
) -> CoreResult<PlatformWatcherSnapshot> {
    validate_signal(&repo_path, &signal)?;
    let snapshot = snapshot_from_signal(repo_path, signal);
    let serialized = serde_json::to_string(&snapshot)
        .map_err(|_| CoreError::db("watcher health metadata is invalid"))?;
    db::upsert_platform_watcher_health(&PathBuf::from(&snapshot.repo_path), &serialized)
        .map_err(normalize_metadata_error)?;
    Ok(snapshot)
}

fn snapshot_from_signal(
    repo_path: String,
    signal: PlatformWatcherHealthSignal,
) -> PlatformWatcherSnapshot {
    let PlatformWatcherHealthSignal {
        backend,
        status,
        watched_path,
        last_event_id,
        last_event_at,
        last_sync_event_id,
        last_sync_at,
        last_rescan_at,
        pending_event_count,
        watch_count,
        error_summary,
        health_reasons,
        recent_events,
        reported_at,
    } = signal;

    PlatformWatcherSnapshot {
        repo_path,
        backend,
        status,
        watched_path,
        last_event_id,
        last_event_at,
        last_sync_event_id,
        last_sync_at,
        last_rescan_at,
        pending_event_count,
        watch_count,
        error_summary,
        health_reasons,
        recent_events,
        reported_at,
    }
}

fn validate_signal(repo_path: &str, signal: &PlatformWatcherHealthSignal) -> CoreResult<()> {
    validate_text("repo_path", repo_path)?;
    validate_text("watched_path", &signal.watched_path)?;
    validate_non_negative("pending_event_count", signal.pending_event_count)?;
    validate_non_negative("reported_at", signal.reported_at)?;
    validate_optional_non_negative("last_event_id", signal.last_event_id)?;
    validate_optional_non_negative("last_event_at", signal.last_event_at)?;
    validate_optional_non_negative("last_sync_event_id", signal.last_sync_event_id)?;
    validate_optional_non_negative("last_sync_at", signal.last_sync_at)?;
    validate_optional_non_negative("last_rescan_at", signal.last_rescan_at)?;
    validate_optional_non_negative("watch_count", signal.watch_count)?;
    if let Some(summary) = signal.error_summary.as_deref() {
        validate_text("error_summary", summary)?;
    }
    if signal.recent_events.len() > MAX_RECENT_EVENTS {
        return Err(invalid_signal("recent_events"));
    }
    for event in &signal.recent_events {
        validate_event_sample(event)?;
    }
    Ok(())
}

fn validate_event_sample(event: &PlatformWatcherEventSample) -> CoreResult<()> {
    validate_text("recent_events.path", &event.path)?;
    validate_non_negative("recent_events.fs_event_id", event.fs_event_id)?;
    validate_optional_non_negative("recent_events.occurred_at", event.occurred_at)
}

fn validate_text(field: &str, value: &str) -> CoreResult<()> {
    if value.trim().is_empty() || value.contains('\0') || value.len() > MAX_STATUS_TEXT_LEN {
        return Err(invalid_signal(field));
    }
    Ok(())
}

fn validate_non_negative(field: &str, value: i64) -> CoreResult<()> {
    if value < 0 {
        return Err(invalid_signal(field));
    }
    Ok(())
}

fn validate_optional_non_negative(field: &str, value: Option<i64>) -> CoreResult<()> {
    if let Some(value) = value {
        validate_non_negative(field, value)?;
    }
    Ok(())
}

fn invalid_signal(field: &str) -> CoreError {
    CoreError::db(format!("watcher health signal is invalid: {field}"))
}

fn normalize_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Io { .. } => CoreError::io("watcher health metadata io unavailable"),
        CoreError::PermissionDenied { .. } => {
            CoreError::io("watcher health metadata io unavailable: permission denied")
        }
        CoreError::Db { message } => CoreError::Db { message },
        _ => CoreError::db("watcher health metadata is unavailable"),
    }
}
