//! Public structured observability entry points.

use std::sync::Arc;

use crate::{
    observability, CoreObservabilitySink, CoreResult, ObservabilityBuildContext,
    ObservabilityConfig, ObservabilityHealth,
};

/// Returns the authoritative build identity for the loaded Core binary.
///
/// The platform shell uses this side-effect-free value to pin the only build context accepted from
/// the live Core sink. Historical diagnostic events retain their original build identity.
pub fn get_observability_build_context() -> ObservabilityBuildContext {
    ObservabilityBuildContext::core()
}

/// Initializes or reconnects the process-wide Core observability runtime.
///
/// The runtime installs one tracing subscriber and retains the supplied sink. Event delivery is
/// bounded and occurs on a dedicated worker so sink latency cannot block user-file operations.
///
/// # Errors
///
/// Returns CoreError::Config for an invalid session or queue configuration and
/// CoreError::Internal when the global subscriber cannot be installed.
pub fn initialize_observability(
    config: ObservabilityConfig,
    sink: Box<dyn CoreObservabilitySink>,
) -> CoreResult<ObservabilityHealth> {
    observability::initialize(config, Arc::from(sink))
}

/// Updates the current Core observability mode and privacy configuration.
///
/// # Errors
///
/// Returns CoreError::Config when observability is not initialized, inputs are invalid, or the
/// caller attempts to resize the fixed process queue without restarting the app.
pub fn update_observability_config(config: ObservabilityConfig) -> CoreResult<ObservabilityHealth> {
    observability::update_config(config)
}

/// Returns read-only Core observability health without producing another event.
pub fn get_observability_health() -> ObservabilityHealth {
    observability::health()
}

/// Waits up to the bounded deadline for accepted Core events to reach the platform sink.
///
/// # Errors
///
/// Returns CoreError::Validation for a deadline outside 1–5,000 milliseconds and
/// CoreError::Config when observability is not initialized.
pub fn flush_observability(deadline_ms: u64) -> CoreResult<ObservabilityHealth> {
    observability::flush(deadline_ms)
}
