use area_matrix_core::{
    flush_observability, get_observability_build_context, get_observability_health, init_logging,
    initialize_observability, update_observability_config, CoreError, CoreLogCallback,
    CoreLogRecord, CoreObservabilityEvent, CoreObservabilitySink, ObservabilityConfig,
    ObservabilityMode, ObservabilitySeverity,
};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

struct NoopLogCallback;

impl CoreLogCallback for NoopLogCallback {
    fn on_log(&self, _record: CoreLogRecord) {}
}

struct DropTrackedSink(Arc<AtomicBool>);

impl CoreObservabilitySink for DropTrackedSink {
    fn on_event(&self, _event: CoreObservabilityEvent) {}
}

impl Drop for DropTrackedSink {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Release);
    }
}

#[test]
fn observability_build_context_comes_from_the_loaded_core_binary() {
    let context = get_observability_build_context();

    assert_eq!(context.producer, "area_matrix_core");
    assert_eq!(context.version, env!("CARGO_PKG_VERSION"));
    assert_eq!(
        context.build.as_deref(),
        option_env!("AREAMATRIX_CORE_BUILD_ID").filter(|value| !value.is_empty())
    );
    assert_eq!(context.platform, std::env::consts::OS);
    assert_eq!(context.architecture, std::env::consts::ARCH);
    assert_eq!(
        context.configuration,
        if cfg!(debug_assertions) {
            "debug"
        } else {
            "release"
        }
    );
}

#[test]
fn observability_public_contract_validates_without_initializing_on_error() {
    let health = get_observability_health();
    assert!(!health.initialized);
    assert_eq!(health.queue_depth, 0);

    assert!(init_logging("verbose".to_owned(), Box::new(NoopLogCallback)).is_err());
    assert!(!get_observability_health().initialized);
    assert!(matches!(
        flush_observability(0),
        Err(CoreError::Validation { .. })
    ));
    assert!(matches!(
        flush_observability(1),
        Err(CoreError::Config { .. })
    ));

    tracing::subscriber::set_global_default(tracing_subscriber::registry())
        .expect("the contract test owns the process subscriber");
    let dropped = Arc::new(AtomicBool::new(false));
    let config = ObservabilityConfig {
        session_id: uuid::Uuid::new_v4().to_string(),
        mode: ObservabilityMode::Developer,
        minimum_severity: ObservabilitySeverity::Trace,
        queue_capacity: 64,
        include_sensitive: false,
    };
    let error = initialize_observability(
        config.clone(),
        Box::new(DropTrackedSink(Arc::clone(&dropped))),
    )
    .expect_err("a preinstalled subscriber must reject initialization atomically");

    assert!(matches!(error, CoreError::Internal { .. }));
    assert!(dropped.load(Ordering::Acquire));
    let health = get_observability_health();
    assert!(!health.initialized);
    assert!(!health.callback_connected);
    assert_eq!(health.queue_capacity, 0);
    assert!(matches!(
        update_observability_config(config),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        flush_observability(1),
        Err(CoreError::Config { .. })
    ));
}
