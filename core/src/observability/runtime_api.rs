//! Process-wide facade for the bounded observability runtime.

use std::{
    sync::{Arc, Mutex, OnceLock},
    thread,
    time::{Duration, Instant},
};

use uuid::Uuid;

use crate::{CoreError, CoreResult};

use super::{
    runtime::ObservabilityRuntime, validation::validate_config, CoreObservabilityEvent,
    CoreObservabilitySink, ObservabilityConfig, ObservabilityHealth, ObservabilityMode,
    ObservabilitySeverity,
};

static RUNTIME: OnceLock<Arc<ObservabilityRuntime>> = OnceLock::new();
static SUBSCRIBER_RESULT: OnceLock<Result<(), String>> = OnceLock::new();
static INITIALIZATION_LOCK: Mutex<()> = Mutex::new(());

pub(crate) fn initialize(
    config: ObservabilityConfig,
    sink: Arc<dyn CoreObservabilitySink>,
) -> CoreResult<ObservabilityHealth> {
    validate_config(&config)?;
    let subscriber_result = SUBSCRIBER_RESULT.get_or_init(super::layer::install_global_subscriber);
    if let Err(reason) = subscriber_result {
        return Err(CoreError::internal(format!(
            "observability subscriber installation failed: {reason}"
        )));
    }
    let _initialization = INITIALIZATION_LOCK
        .lock()
        .map_err(|_| CoreError::internal("observability initialization lock is unavailable"))?;
    if let Some(runtime) = RUNTIME.get() {
        runtime.update(config, Some(sink))?;
        return Ok(runtime.health(true));
    }
    let runtime = ObservabilityRuntime::new(config, sink)?;
    RUNTIME
        .set(Arc::clone(&runtime))
        .map_err(|_| CoreError::internal("observability runtime publication failed"))?;
    Ok(runtime.health(true))
}

pub(crate) fn update_config(config: ObservabilityConfig) -> CoreResult<ObservabilityHealth> {
    let runtime = initialized_runtime()?;
    runtime.update(config, None)?;
    Ok(runtime.health(subscriber_is_installed()))
}

pub(crate) fn legacy_configuration(
    minimum_severity: ObservabilitySeverity,
) -> CoreResult<ObservabilityConfig> {
    RUNTIME.get().map_or_else(
        || {
            Ok(ObservabilityConfig {
                session_id: Uuid::new_v4().to_string(),
                mode: ObservabilityMode::Developer,
                minimum_severity,
                queue_capacity: 1_024,
                include_sensitive: false,
            })
        },
        |runtime| runtime.legacy_configuration(minimum_severity),
    )
}

pub(crate) fn health() -> ObservabilityHealth {
    RUNTIME.get().map_or_else(uninitialized_health, |runtime| {
        runtime.health(subscriber_is_installed())
    })
}

pub(crate) fn flush(deadline_ms: u64) -> CoreResult<ObservabilityHealth> {
    if !(1..=5_000).contains(&deadline_ms) {
        return Err(CoreError::validation(
            "observability flush deadline must be between 1 and 5000 milliseconds",
        ));
    }
    let runtime = initialized_runtime()?;
    runtime.try_enqueue_drop_summary_from_state();
    let deadline = Instant::now() + Duration::from_millis(deadline_ms);
    while runtime.has_outstanding_delivery() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(1));
    }
    if runtime.has_outstanding_delivery() {
        runtime.mark_degraded("flush-deadline-exceeded");
    }
    Ok(runtime.health(subscriber_is_installed()))
}

pub(crate) fn submit(event: CoreObservabilityEvent) {
    if let Some(runtime) = RUNTIME.get() {
        runtime.submit(event);
    }
}

pub(crate) fn validate_context_session(session_id: &str) -> CoreResult<()> {
    RUNTIME.get().map_or(Ok(()), |runtime| {
        runtime.validate_context_session(session_id)
    })
}

fn initialized_runtime() -> CoreResult<&'static Arc<ObservabilityRuntime>> {
    RUNTIME
        .get()
        .ok_or_else(|| CoreError::config("observability is not initialized"))
}

fn subscriber_is_installed() -> bool {
    SUBSCRIBER_RESULT.get().is_some_and(Result::is_ok)
}

fn uninitialized_health() -> ObservabilityHealth {
    ObservabilityHealth {
        initialized: false,
        mode: ObservabilityMode::Disabled,
        queue_depth: 0,
        queue_capacity: 0,
        dropped_trace: 0,
        dropped_debug: 0,
        dropped_info: 0,
        dropped_warn: 0,
        dropped_error: 0,
        redaction_rejected: 0,
        callback_connected: false,
        degraded: false,
        degraded_reason: None,
    }
}
