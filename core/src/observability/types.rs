//! Public observability contract types shared with platform shells.

use serde::{Deserialize, Serialize};

/// Runtime detail and persistence intent selected by the platform shell.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ObservabilityMode {
    /// Only critical in-process evidence is delivered.
    Disabled,
    /// Key actions, outcomes, errors, and duration summaries.
    Standard,
    /// Detailed branches, component calls, and state changes.
    Diagnostic,
    /// All registered technical events allowed by the privacy contract.
    Developer,
}

/// Event severity ordered from most verbose to most urgent.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ObservabilitySeverity {
    /// Fine-grained execution trace.
    Trace,
    /// Developer diagnostic detail.
    Debug,
    /// Normal semantic operation information.
    Info,
    /// Recoverable or degraded behavior.
    Warn,
    /// Failed operation or invariant.
    Error,
}

impl ObservabilitySeverity {
    pub(crate) const fn rank(self) -> u8 {
        match self {
            Self::Trace => 0,
            Self::Debug => 1,
            Self::Info => 2,
            Self::Warn => 3,
            Self::Error => 4,
        }
    }
}

/// Architectural layer that emitted an event.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ObservabilityLayer {
    /// SwiftUI presentation and semantic actions.
    SwiftUi,
    /// macOS platform service.
    Platform,
    /// Hand-written Swift/Core bridge.
    Bridge,
    /// Platform-neutral Rust domain logic.
    Core,
    /// SQLite read or transaction boundary.
    Database,
    /// Filesystem observation or mutation boundary.
    Filesystem,
    /// Explicit network boundary owned by a platform shell.
    Network,
}

/// Stable outcome associated with an event.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ObservabilityOutcome {
    /// Event is informational and has no lifecycle outcome.
    None,
    /// Operation or span started.
    Started,
    /// Operation or span succeeded.
    Succeeded,
    /// Operation or span failed.
    Failed,
    /// Operation was explicitly cancelled.
    Cancelled,
    /// Operation was intentionally skipped.
    Skipped,
    /// Operation completed with degraded behavior.
    Degraded,
}

/// Privacy classification applied before an event reaches a sink.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ObservabilityPrivacy {
    /// Stable non-user data safe for enabled sinks.
    Public,
    /// A keyed or otherwise non-reversible resource reference.
    Pseudonymous,
    /// User-identifying metadata requiring explicit local authorization.
    Sensitive,
    /// Data that must never enter observability.
    Prohibited,
}

impl ObservabilityPrivacy {
    pub(crate) const fn rank(self) -> u8 {
        match self {
            Self::Public => 0,
            Self::Pseudonymous => 1,
            Self::Sensitive => 2,
            Self::Prohibited => 3,
        }
    }

    pub(crate) const fn max(self, other: Self) -> Self {
        if self.rank() >= other.rank() {
            self
        } else {
            other
        }
    }
}

/// Core observability runtime configuration.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObservabilityConfig {
    /// UUID identifying the current application process session.
    pub session_id: String,
    /// Selected runtime detail mode.
    pub mode: ObservabilityMode,
    /// Minimum accepted severity within the mode ceiling.
    pub minimum_severity: ObservabilitySeverity,
    /// Fixed bounded Core delivery queue capacity.
    pub queue_capacity: u64,
    /// Whether explicitly classified sensitive values may be delivered locally.
    pub include_sensitive: bool,
}

/// Explicit context propagated across a Swift/Core request boundary.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CoreTraceContext {
    /// Application process session UUID.
    pub session_id: String,
    /// Root causal trace UUID.
    pub trace_id: String,
    /// Parent span UUID when this is not a root request.
    pub parent_span_id: Option<String>,
    /// User-marked incident UUID when capture is active.
    pub incident_id: Option<String>,
    /// Durable business operation UUID when one exists.
    pub operation_id: Option<String>,
    /// Prior terminal operation UUID when this operation is a retry.
    pub retry_of_operation_id: Option<String>,
    /// Registered semantic action identifier.
    pub action_id: String,
    /// Registered component identifier.
    pub component_id: String,
    /// Platform-created privacy-safe resource identities propagated to every Core span.
    pub resource_refs: Vec<CoreObservabilityResourceRef>,
    /// Bounded typed context attributes subject to Core source redaction.
    pub attributes: Vec<CoreObservabilityAttribute>,
}

/// One structured event attribute.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CoreObservabilityAttribute {
    /// Stable field name.
    pub key: String,
    /// Bounded field value.
    pub value: String,
    /// Field privacy classification.
    pub privacy: ObservabilityPrivacy,
}

/// Privacy-safe reference to a user-controlled resource.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CoreObservabilityResourceRef {
    /// Stable opaque identity for correlation.
    pub resource_id: String,
    /// Keyed pseudonymous display alias.
    pub alias: String,
    /// Optional lowercase extension without a leading dot.
    pub extension: Option<String>,
    /// Optional coarse size bucket.
    pub size_bucket: Option<String>,
    /// Optional stable storage mode identifier.
    pub storage_mode: Option<String>,
}

/// Structured error attached to an observability event.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CoreObservabilityError {
    /// Stable error code used for grouping and presentation.
    pub code: String,
    /// Optional stable error kind.
    pub kind: Option<String>,
    /// Optional bounded technical detail after source redaction.
    pub technical_details: Option<String>,
}

/// Public build identity for the binary that produced an event.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObservabilityBuildContext {
    /// Stable producer identifier such as `area_matrix_core`.
    pub producer: String,
    /// Producer version from its authoritative build metadata.
    pub version: String,
    /// Optional CI or bundle build identifier.
    pub build: Option<String>,
    /// Stable `debug` or `release` configuration.
    pub configuration: String,
    /// Target operating-system identifier.
    pub platform: String,
    /// Target architecture identifier.
    pub architecture: String,
}

impl ObservabilityBuildContext {
    pub(crate) fn core() -> Self {
        Self {
            producer: "area_matrix_core".to_owned(),
            version: env!("CARGO_PKG_VERSION").to_owned(),
            build: option_env!("AREAMATRIX_CORE_BUILD_ID")
                .filter(|value| !value.is_empty())
                .map(str::to_owned),
            configuration: if cfg!(debug_assertions) {
                "debug".to_owned()
            } else {
                "release".to_owned()
            },
            platform: std::env::consts::OS.to_owned(),
            architecture: std::env::consts::ARCH.to_owned(),
        }
    }
}

/// Structured event delivered from Core to the platform shell.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CoreObservabilityEvent {
    /// Event schema version.
    pub schema_version: u64,
    /// Unique event UUID.
    pub event_id: String,
    /// Unix epoch timestamp in milliseconds.
    pub wall_timestamp_ms: i64,
    /// Nanoseconds since Core observability runtime initialization.
    pub monotonic_timestamp_ns: u64,
    /// Process-local monotonically increasing event sequence.
    pub sequence_number: u64,
    /// Application process session UUID.
    pub session_id: String,
    /// User-marked incident UUID.
    pub incident_id: Option<String>,
    /// Root causal trace UUID.
    pub trace_id: String,
    /// Current span UUID.
    pub span_id: String,
    /// Parent span UUID.
    pub parent_span_id: Option<String>,
    /// Durable business operation UUID.
    pub operation_id: Option<String>,
    /// Prior operation UUID for a terminal retry.
    pub retry_of_operation_id: Option<String>,
    /// Registered semantic action identifier.
    pub action_id: String,
    /// Registered component identifier.
    pub component_id: String,
    /// Architectural source layer.
    pub layer: ObservabilityLayer,
    /// Stable lifecycle phase identifier.
    pub phase: String,
    /// Event severity.
    pub severity: ObservabilitySeverity,
    /// Stable event outcome.
    pub outcome: ObservabilityOutcome,
    /// Optional completed duration.
    pub duration_ms: Option<u64>,
    /// Privacy-safe resource references.
    pub resource_refs: Vec<CoreObservabilityResourceRef>,
    /// Optional structured error.
    pub error: Option<CoreObservabilityError>,
    /// Typed bounded attributes.
    pub attributes: Vec<CoreObservabilityAttribute>,
    /// Highest privacy classification present after redaction.
    pub privacy_level: ObservabilityPrivacy,
    /// Optional bounded non-localized technical message.
    pub message: Option<String>,
    /// Optional Rust tracing target.
    pub target: Option<String>,
    /// Optional source thread name.
    pub thread_name: Option<String>,
    /// Build identity of the binary that produced this event.
    pub build_context: ObservabilityBuildContext,
}

/// Read-only Core observability runtime health.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObservabilityHealth {
    /// Whether a runtime and subscriber are installed.
    pub initialized: bool,
    /// Current runtime mode.
    pub mode: ObservabilityMode,
    /// Events accepted but not yet delivered.
    pub queue_depth: u64,
    /// Fixed queue capacity.
    pub queue_capacity: u64,
    /// Dropped trace event count.
    pub dropped_trace: u64,
    /// Dropped debug event count.
    pub dropped_debug: u64,
    /// Dropped info event count.
    pub dropped_info: u64,
    /// Dropped warning event count.
    pub dropped_warn: u64,
    /// Dropped error event count.
    pub dropped_error: u64,
    /// Events rejected by fail-closed source redaction.
    pub redaction_rejected: u64,
    /// Whether a platform callback is currently retained.
    pub callback_connected: bool,
    /// Whether delivery has encountered a bounded failure.
    pub degraded: bool,
    /// Stable bounded reason for degraded state.
    pub degraded_reason: Option<String>,
}

/// Platform callback that receives sanitized structured Core events.
pub trait CoreObservabilitySink: Send + Sync {
    /// Receives one event on the Core delivery worker thread.
    fn on_event(&self, event: CoreObservabilityEvent);
}
