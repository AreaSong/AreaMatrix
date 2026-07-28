//! Bounded process-wide Core observability runtime.

use std::{
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, RwLock,
    },
    thread,
    time::{Instant, SystemTime},
};

use crate::{CoreError, CoreResult};

use super::{
    callback::{CallbackDeliveryError, CallbackDispatcher},
    queue::{PriorityEventQueue, QueuePushResult, QueuedObservabilityEvent},
    redaction::{estimated_event_bytes, sanitize_event, severity_is_enabled},
    validation::validate_config,
    CoreObservabilityAttribute, CoreObservabilityEvent, CoreObservabilitySink,
    ObservabilityBuildContext, ObservabilityConfig, ObservabilityHealth, ObservabilityLayer,
    ObservabilityMode, ObservabilityOutcome, ObservabilityPrivacy, ObservabilitySeverity,
};
use uuid::Uuid;

pub(crate) struct ObservabilityRuntime {
    state: RwLock<RuntimeState>,
    queue: PriorityEventQueue,
    queue_capacity: u64,
    queue_depth: AtomicU64,
    delivery_in_flight: AtomicU64,
    dropped: DropCounters,
    redaction_rejected: AtomicU64,
    drop_report_pending: AtomicBool,
    degraded: AtomicBool,
    degraded_reason: RwLock<Option<String>>,
    timed_out_callbacks: Mutex<Vec<CallbackDispatcher>>,
    started: Instant,
}

struct RuntimeState {
    config: ObservabilityConfig,
    sink: Option<CallbackDispatcher>,
    authorization_generation: u64,
}

struct DropCounters {
    trace: AtomicU64,
    debug: AtomicU64,
    info: AtomicU64,
    warn: AtomicU64,
    error: AtomicU64,
}

impl DropCounters {
    fn new() -> Self {
        Self {
            trace: AtomicU64::new(0),
            debug: AtomicU64::new(0),
            info: AtomicU64::new(0),
            warn: AtomicU64::new(0),
            error: AtomicU64::new(0),
        }
    }

    fn increment(&self, severity: ObservabilitySeverity) {
        let counter = match severity {
            ObservabilitySeverity::Trace => &self.trace,
            ObservabilitySeverity::Debug => &self.debug,
            ObservabilitySeverity::Info => &self.info,
            ObservabilitySeverity::Warn => &self.warn,
            ObservabilitySeverity::Error => &self.error,
        };
        counter.fetch_add(1, Ordering::Relaxed);
    }
}

impl ObservabilityRuntime {
    pub(super) fn new(
        config: ObservabilityConfig,
        sink: Arc<dyn CoreObservabilitySink>,
    ) -> CoreResult<Arc<Self>> {
        let sink = CallbackDispatcher::new(sink)?;
        let queue_capacity = config.queue_capacity;
        let runtime = Arc::new(Self {
            queue_capacity,
            state: RwLock::new(RuntimeState {
                config,
                sink: Some(sink),
                authorization_generation: next_generation(0),
            }),
            queue: PriorityEventQueue::new(
                queue_capacity as usize,
                queue_byte_capacity(queue_capacity),
            ),
            queue_depth: AtomicU64::new(0),
            delivery_in_flight: AtomicU64::new(0),
            dropped: DropCounters::new(),
            redaction_rejected: AtomicU64::new(0),
            drop_report_pending: AtomicBool::new(false),
            degraded: AtomicBool::new(false),
            degraded_reason: RwLock::new(None),
            timed_out_callbacks: Mutex::new(Vec::new()),
            started: Instant::now(),
        });
        let worker_runtime = Arc::clone(&runtime);
        thread::Builder::new()
            .name("areamatrix-observability".to_owned())
            .spawn(move || {
                while let Some(event) = worker_runtime.queue.take() {
                    worker_runtime
                        .delivery_in_flight
                        .fetch_add(1, Ordering::AcqRel);
                    worker_runtime.queue_depth.fetch_sub(1, Ordering::Release);
                    if worker_runtime.deliver(event) {
                        worker_runtime.try_enqueue_drop_summary_from_state();
                    }
                }
            })
            .map_err(|_| CoreError::internal("observability delivery worker could not start"))?;
        Ok(runtime)
    }

    fn deliver(&self, event: QueuedObservabilityEvent) -> bool {
        let delivered = self.deliver_inner(event);
        self.delivery_in_flight.fetch_sub(1, Ordering::Release);
        delivered
    }

    fn deliver_inner(&self, queued: QueuedObservabilityEvent) -> bool {
        let severity = queued.event.severity;
        let (mut config, sink, generation) = match self.state.read() {
            Ok(state) => (
                state.config.clone(),
                state.sink.clone(),
                state.authorization_generation,
            ),
            Err(_) => {
                self.mark_degraded("runtime-state-lock-poisoned");
                self.note_drop(severity);
                return false;
            }
        };
        if queued.authorization_generation != generation {
            config.include_sensitive = false;
        }
        let event = match sanitize_event(queued.event, &config) {
            Ok(event) => event,
            Err(_) => {
                self.redaction_rejected.fetch_add(1, Ordering::Relaxed);
                self.mark_degraded("delivery-redaction-rejected-event");
                self.note_drop(severity);
                return sink.is_some();
            }
        };
        let Some(sink) = sink else {
            self.note_drop(severity);
            return false;
        };
        match sink.deliver(event) {
            Ok(()) => true,
            Err(error) => self.handle_callback_error(error, sink, generation, severity),
        }
    }

    fn handle_callback_error(
        &self,
        error: CallbackDeliveryError,
        sink: CallbackDispatcher,
        generation: u64,
        severity: ObservabilitySeverity,
    ) -> bool {
        self.disconnect_failed_sink(generation);
        match error {
            CallbackDeliveryError::Disconnected => {
                self.note_drop(severity);
                self.mark_degraded("callback-disconnected");
            }
            CallbackDeliveryError::Panicked => {
                self.note_drop(severity);
                self.mark_degraded("callback-panicked");
            }
            CallbackDeliveryError::TimedOut => {
                self.track_timed_out_callback(sink);
                self.mark_degraded("callback-deadline-exceeded");
            }
        }
        false
    }

    pub(super) fn submit(&self, mut event: CoreObservabilityEvent) {
        let (config, authorization_generation) = match self.state.read() {
            Ok(state) => (state.config.clone(), state.authorization_generation),
            Err(_) => {
                self.mark_degraded("runtime-state-lock-poisoned");
                self.note_drop(event.severity);
                return;
            }
        };
        if !severity_is_enabled(event.severity, &config) {
            return;
        }
        self.try_enqueue_drop_summary(&config, authorization_generation);
        event.session_id.clone_from(&config.session_id);
        event.monotonic_timestamp_ns =
            self.started.elapsed().as_nanos().min(u64::MAX as u128) as u64;
        let event = match sanitize_event(event, &config) {
            Ok(event) => event,
            Err(_) => {
                self.redaction_rejected.fetch_add(1, Ordering::Relaxed);
                self.mark_degraded("source-redaction-rejected-event");
                return;
            }
        };
        let byte_size = estimated_event_bytes(&event);
        self.enqueue(QueuedObservabilityEvent::new(
            event,
            authorization_generation,
            byte_size,
        ));
    }

    fn enqueue(&self, event: QueuedObservabilityEvent) {
        let severity = event.event.severity;
        self.queue_depth.fetch_add(1, Ordering::AcqRel);
        match self.queue.push(event) {
            QueuePushResult::Accepted => {}
            QueuePushResult::Replaced(evicted_severities) => {
                self.queue_depth
                    .fetch_sub(evicted_severities.len() as u64, Ordering::Release);
                for evicted_severity in evicted_severities {
                    self.note_drop(evicted_severity);
                }
                self.mark_degraded("queue-saturated");
            }
            QueuePushResult::Rejected => {
                self.queue_depth.fetch_sub(1, Ordering::Release);
                self.note_drop(severity);
                self.mark_degraded("queue-saturated");
            }
        }
    }

    pub(super) fn update(
        &self,
        config: ObservabilityConfig,
        sink: Option<Arc<dyn CoreObservabilitySink>>,
    ) -> CoreResult<()> {
        validate_config(&config)?;
        if sink.is_some() {
            self.ensure_callback_replacement_available()?;
        }
        let replacement = sink.map(CallbackDispatcher::new).transpose()?;
        let mut state = self
            .state
            .write()
            .map_err(|_| CoreError::internal("observability runtime state is unavailable"))?;
        if config.session_id != state.config.session_id {
            return Err(CoreError::config(
                "observability session changes require an app restart",
            ));
        }
        if config.queue_capacity != self.queue_capacity {
            return Err(CoreError::config(
                "observability queue capacity changes require an app restart",
            ));
        }
        let authorization_changed =
            replacement.is_some() || config.include_sensitive != state.config.include_sensitive;
        state.config = config;
        if let Some(sink) = replacement {
            state.sink = Some(sink);
        }
        if authorization_changed {
            state.authorization_generation = next_generation(state.authorization_generation);
        }
        drop(state);
        self.try_enqueue_drop_summary_from_state();
        Ok(())
    }

    fn ensure_callback_replacement_available(&self) -> CoreResult<()> {
        const MAX_TIMED_OUT_CALLBACKS: usize = 4;
        let mut callbacks = self
            .timed_out_callbacks
            .lock()
            .map_err(|_| CoreError::internal("observability callback registry is unavailable"))?;
        callbacks.retain(CallbackDispatcher::is_busy);
        if callbacks.len() >= MAX_TIMED_OUT_CALLBACKS {
            return Err(CoreError::config(
                "observability callback replacement limit reached; restart the app",
            ));
        }
        Ok(())
    }

    fn track_timed_out_callback(&self, sink: CallbackDispatcher) {
        if !sink.is_busy() {
            return;
        }
        if let Ok(mut callbacks) = self.timed_out_callbacks.lock() {
            callbacks.retain(CallbackDispatcher::is_busy);
            callbacks.push(sink);
        } else {
            self.mark_degraded("callback-registry-lock-poisoned");
        }
    }

    pub(super) fn mark_degraded(&self, reason: &str) {
        self.degraded.store(true, Ordering::Release);
        if let Ok(mut current) = self.degraded_reason.write() {
            *current = Some(reason.to_owned());
        }
    }

    fn note_drop(&self, severity: ObservabilitySeverity) {
        self.dropped.increment(severity);
        self.drop_report_pending.store(true, Ordering::Release);
    }

    fn try_enqueue_drop_summary(
        &self,
        config: &ObservabilityConfig,
        authorization_generation: u64,
    ) {
        if self.queue_depth.load(Ordering::Acquire) >= self.queue_capacity
            || self
                .drop_report_pending
                .compare_exchange(true, false, Ordering::AcqRel, Ordering::Acquire)
                .is_err()
        {
            return;
        }

        let event = self.drop_summary_event(config);
        let byte_size = estimated_event_bytes(&event);
        self.enqueue(QueuedObservabilityEvent::new(
            event,
            authorization_generation,
            byte_size,
        ));
    }

    pub(super) fn try_enqueue_drop_summary_from_state(&self) {
        let Ok(state) = self.state.read() else {
            self.mark_degraded("runtime-state-lock-poisoned");
            return;
        };
        let config = state.config.clone();
        let generation = state.authorization_generation;
        drop(state);
        self.try_enqueue_drop_summary(&config, generation);
    }

    fn drop_summary_event(&self, config: &ObservabilityConfig) -> CoreObservabilityEvent {
        CoreObservabilityEvent {
            schema_version: 2,
            event_id: Uuid::new_v4().to_string(),
            wall_timestamp_ms: wall_timestamp_ms(),
            monotonic_timestamp_ns: self.started.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            sequence_number: 0,
            session_id: config.session_id.clone(),
            incident_id: None,
            trace_id: Uuid::new_v4().to_string(),
            span_id: Uuid::new_v4().to_string(),
            parent_span_id: None,
            operation_id: None,
            retry_of_operation_id: None,
            action_id: "observability.events_dropped".to_owned(),
            component_id: "core.observability.runtime".to_owned(),
            layer: ObservabilityLayer::Core,
            phase: "capacity_recovered".to_owned(),
            severity: ObservabilitySeverity::Warn,
            outcome: ObservabilityOutcome::Degraded,
            duration_ms: None,
            resource_refs: Vec::new(),
            error: None,
            attributes: self.drop_summary_attributes(),
            privacy_level: ObservabilityPrivacy::Public,
            message: None,
            target: Some("area_matrix_core.observability".to_owned()),
            thread_name: thread::current().name().map(str::to_owned),
            build_context: ObservabilityBuildContext::core(),
        }
    }

    fn drop_summary_attributes(&self) -> Vec<CoreObservabilityAttribute> {
        [
            ("dropped.trace", self.dropped.trace.load(Ordering::Relaxed)),
            ("dropped.debug", self.dropped.debug.load(Ordering::Relaxed)),
            ("dropped.info", self.dropped.info.load(Ordering::Relaxed)),
            ("dropped.warn", self.dropped.warn.load(Ordering::Relaxed)),
            ("dropped.error", self.dropped.error.load(Ordering::Relaxed)),
        ]
        .into_iter()
        .map(|(key, value)| CoreObservabilityAttribute {
            key: key.to_owned(),
            value: value.to_string(),
            privacy: ObservabilityPrivacy::Public,
        })
        .collect()
    }

    pub(super) fn health(&self, initialized: bool) -> ObservabilityHealth {
        let (mode, callback_connected) = self
            .state
            .read()
            .map(|state| (state.config.mode, state.sink.is_some()))
            .unwrap_or((ObservabilityMode::Disabled, false));
        ObservabilityHealth {
            initialized,
            mode,
            queue_depth: self.queue_depth.load(Ordering::Acquire),
            queue_capacity: self.queue_capacity,
            dropped_trace: self.dropped.trace.load(Ordering::Relaxed),
            dropped_debug: self.dropped.debug.load(Ordering::Relaxed),
            dropped_info: self.dropped.info.load(Ordering::Relaxed),
            dropped_warn: self.dropped.warn.load(Ordering::Relaxed),
            dropped_error: self.dropped.error.load(Ordering::Relaxed),
            redaction_rejected: self.redaction_rejected.load(Ordering::Relaxed),
            callback_connected,
            degraded: self.degraded.load(Ordering::Acquire),
            degraded_reason: self
                .degraded_reason
                .read()
                .ok()
                .and_then(|reason| reason.clone()),
        }
    }

    fn disconnect_failed_sink(&self, failed_generation: u64) {
        let Ok(mut state) = self.state.write() else {
            self.mark_degraded("runtime-state-lock-poisoned");
            return;
        };
        if state.authorization_generation == failed_generation {
            state.sink = None;
            state.authorization_generation = next_generation(state.authorization_generation);
        }
    }

    pub(super) fn has_outstanding_delivery(&self) -> bool {
        self.queue_depth.load(Ordering::Acquire) > 0
            || self.delivery_in_flight.load(Ordering::Acquire) > 0
    }

    pub(super) fn legacy_configuration(
        &self,
        minimum_severity: ObservabilitySeverity,
    ) -> CoreResult<ObservabilityConfig> {
        let current = self
            .state
            .read()
            .map_err(|_| CoreError::internal("observability runtime state is unavailable"))?;
        Ok(ObservabilityConfig {
            session_id: current.config.session_id.clone(),
            mode: ObservabilityMode::Developer,
            minimum_severity,
            queue_capacity: self.queue_capacity,
            include_sensitive: false,
        })
    }

    pub(super) fn validate_context_session(&self, session_id: &str) -> CoreResult<()> {
        let current = self
            .state
            .read()
            .map_err(|_| CoreError::internal("observability runtime state is unavailable"))?;
        if current.config.session_id != session_id {
            return Err(CoreError::validation(
                "observability trace session does not match the runtime session",
            ));
        }
        Ok(())
    }
}

fn queue_byte_capacity(queue_capacity: u64) -> usize {
    const BYTES_PER_SLOT: usize = 8 * 1024;
    const MAX_BYTES: usize = 64 * 1024 * 1024;
    usize::try_from(queue_capacity)
        .unwrap_or(usize::MAX)
        .saturating_mul(BYTES_PER_SLOT)
        .min(MAX_BYTES)
}

fn next_generation(current: u64) -> u64 {
    match current.wrapping_add(1) {
        0 => 1,
        next => next,
    }
}

fn wall_timestamp_ms() -> i64 {
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
}
