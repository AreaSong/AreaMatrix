use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Condvar, Mutex,
    },
    time::Duration,
};

use area_matrix_core::{
    CoreLogCallback, CoreLogRecord, CoreObservabilityEvent, CoreObservabilitySink,
    ObservabilityPrivacy,
};

#[derive(Default)]
pub(crate) struct SinkState {
    pub(crate) events: Mutex<Vec<CoreObservabilityEvent>>,
    pub(crate) completed: (Mutex<u64>, Condvar),
    pub(crate) first_started: (Mutex<bool>, Condvar),
    pub(crate) release_first: (Mutex<bool>, Condvar),
    pub(crate) block_first: AtomicBool,
}

pub(crate) struct RecordingSink(pub(crate) Arc<SinkState>);

impl CoreObservabilitySink for RecordingSink {
    fn on_event(&self, event: CoreObservabilityEvent) {
        record_event(&self.0, event);
    }
}

pub(crate) struct DropTrackingSink {
    state: Arc<SinkState>,
    dropped: Arc<SinkDropSignal>,
}

impl DropTrackingSink {
    pub(crate) fn new(state: Arc<SinkState>) -> (Self, Arc<SinkDropSignal>) {
        let dropped = Arc::new(SinkDropSignal::default());
        (
            Self {
                state,
                dropped: Arc::clone(&dropped),
            },
            dropped,
        )
    }
}

impl CoreObservabilitySink for DropTrackingSink {
    fn on_event(&self, event: CoreObservabilityEvent) {
        record_event(&self.state, event);
    }
}

impl Drop for DropTrackingSink {
    fn drop(&mut self) {
        *self.dropped.dropped.lock().unwrap() = true;
        self.dropped.signal.notify_all();
    }
}

#[derive(Default)]
pub(crate) struct SinkDropSignal {
    dropped: Mutex<bool>,
    signal: Condvar,
}

pub(crate) struct PanicSink;

impl CoreObservabilitySink for PanicSink {
    fn on_event(&self, _event: CoreObservabilityEvent) {
        panic!("intentional callback failure");
    }
}

pub(crate) struct CountingLegacySink(pub(crate) Arc<AtomicBool>);

impl CoreLogCallback for CountingLegacySink {
    fn on_log(&self, _record: CoreLogRecord) {
        self.0.store(true, Ordering::Release);
    }
}

pub(crate) fn wait_for_first_callback(state: &SinkState) {
    let (started, signal) = &state.first_started;
    let started = started.lock().unwrap();
    let (started, _) = signal
        .wait_timeout_while(started, Duration::from_secs(10), |started| !*started)
        .unwrap();
    assert!(*started, "callback did not start within the test deadline");
}

pub(crate) fn release_first_callback(state: &SinkState) {
    let (released, signal) = &state.release_first;
    *released.lock().unwrap() = true;
    signal.notify_one();
}

pub(crate) fn wait_for_completed_callbacks(state: &SinkState, expected: u64) {
    let (completed, signal) = &state.completed;
    let completed = completed.lock().unwrap();
    let (completed, _) = signal
        .wait_timeout_while(completed, Duration::from_secs(10), |completed| {
            *completed < expected
        })
        .unwrap();
    assert!(
        *completed >= expected,
        "callback did not complete within the test deadline"
    );
}

pub(crate) fn wait_for_sink_drop(dropped: &SinkDropSignal) {
    let state = dropped.dropped.lock().unwrap();
    let (state, _) = dropped
        .signal
        .wait_timeout_while(state, Duration::from_secs(10), |dropped| !*dropped)
        .unwrap();
    assert!(
        *state,
        "callback sink was not released within the test deadline"
    );
}

fn record_event(state: &SinkState, event: CoreObservabilityEvent) {
    if state.block_first.swap(false, Ordering::AcqRel) {
        let (started, signal) = &state.first_started;
        *started.lock().unwrap() = true;
        signal.notify_one();
        let (released, signal) = &state.release_first;
        let released = released.lock().unwrap();
        let _released = signal.wait_while(released, |released| !*released).unwrap();
    }
    state.events.lock().unwrap().push(event);
    let (completed, signal) = &state.completed;
    *completed.lock().unwrap() += 1;
    signal.notify_all();
}

pub(crate) fn assert_span_tree(state: &SinkState, trace_id: &str, operation_id: &str) {
    let events = state.events.lock().unwrap();
    let root: Vec<_> = events
        .iter()
        .filter(|event| event.action_id == "repository.import.validation")
        .collect();
    let child: Vec<_> = events
        .iter()
        .filter(|event| event.action_id == "repository.import.staging")
        .collect();
    let event = events
        .iter()
        .find(|event| event.action_id == "repository.import.destination")
        .expect("event inside child span is delivered");
    assert_eq!(root.len(), 2);
    assert_eq!(child.len(), 2);
    assert_eq!(root[0].phase, "started");
    assert_eq!(root[1].phase, "completed");
    assert_eq!(root[0].span_id, root[1].span_id);
    assert_eq!(
        child[0].parent_span_id.as_deref(),
        Some(root[0].span_id.as_str())
    );
    assert_eq!(event.span_id, child[0].span_id);
    assert_eq!(event.parent_span_id, child[0].parent_span_id);
    assert!(root
        .iter()
        .chain(child.iter())
        .copied()
        .chain(std::iter::once(event))
        .all(|event| {
            event.trace_id == trace_id && event.operation_id.as_deref() == Some(operation_id)
        }));
    assert!(root.iter().all(|event| {
        event.privacy_level == ObservabilityPrivacy::Sensitive
            && event.attributes[0].value == "[REDACTED]"
    }));
}
