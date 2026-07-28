//! Fixed-capacity FIFO delivery queue with severity-aware admission.

use std::{
    collections::VecDeque,
    sync::{Condvar, Mutex},
};

use super::{CoreObservabilityEvent, ObservabilitySeverity};

pub(super) enum QueuePushResult {
    Accepted,
    Replaced(Vec<ObservabilitySeverity>),
    Rejected,
}

pub(super) struct QueuedObservabilityEvent {
    pub(super) event: CoreObservabilityEvent,
    pub(super) authorization_generation: u64,
    byte_size: usize,
}

impl QueuedObservabilityEvent {
    pub(super) fn new(
        event: CoreObservabilityEvent,
        authorization_generation: u64,
        byte_size: usize,
    ) -> Self {
        Self {
            event,
            authorization_generation,
            byte_size,
        }
    }
}

pub(super) struct PriorityEventQueue {
    capacity: usize,
    byte_capacity: usize,
    state: Mutex<QueueState>,
    available: Condvar,
}

struct QueueState {
    queue: VecDeque<QueuedObservabilityEvent>,
    bytes: usize,
    next_sequence: u64,
}

impl PriorityEventQueue {
    pub(super) fn new(capacity: usize, byte_capacity: usize) -> Self {
        Self {
            capacity,
            byte_capacity,
            state: Mutex::new(QueueState {
                queue: VecDeque::new(),
                bytes: 0,
                next_sequence: 0,
            }),
            available: Condvar::new(),
        }
    }

    pub(super) fn push(&self, mut incoming: QueuedObservabilityEvent) -> QueuePushResult {
        let Ok(mut state) = self.state.lock() else {
            return QueuePushResult::Rejected;
        };
        if incoming.byte_size > self.byte_capacity {
            return QueuePushResult::Rejected;
        }
        let evicted = if fits(&state, &incoming, self.capacity, self.byte_capacity) {
            Vec::new()
        } else {
            let incoming_rank = incoming.event.severity.rank();
            if !eligible_events_can_make_room(
                &state,
                &incoming,
                incoming_rank,
                self.capacity,
                self.byte_capacity,
            ) {
                return QueuePushResult::Rejected;
            }
            evict_until_fits(
                &mut state,
                &incoming,
                incoming_rank,
                self.capacity,
                self.byte_capacity,
            )
        };
        state.next_sequence = state.next_sequence.saturating_add(1);
        incoming.event.sequence_number = state.next_sequence;
        state.bytes += incoming.byte_size;
        state.queue.push_back(incoming);
        self.available.notify_one();
        if evicted.is_empty() {
            QueuePushResult::Accepted
        } else {
            QueuePushResult::Replaced(evicted)
        }
    }

    pub(super) fn take(&self) -> Option<QueuedObservabilityEvent> {
        let mut state = self.state.lock().ok()?;
        loop {
            if let Some(event) = state.queue.pop_front() {
                state.bytes = state.bytes.saturating_sub(event.byte_size);
                return Some(event);
            }
            state = self.available.wait(state).ok()?;
        }
    }
}

fn fits(
    state: &QueueState,
    incoming: &QueuedObservabilityEvent,
    capacity: usize,
    byte_capacity: usize,
) -> bool {
    state.queue.len() < capacity
        && state
            .bytes
            .checked_add(incoming.byte_size)
            .is_some_and(|bytes| bytes <= byte_capacity)
}

fn eligible_events_can_make_room(
    state: &QueueState,
    incoming: &QueuedObservabilityEvent,
    incoming_rank: u8,
    capacity: usize,
    byte_capacity: usize,
) -> bool {
    let eligible = state
        .queue
        .iter()
        .filter(|event| event.event.severity.rank() < incoming_rank);
    let (count, bytes) = eligible.fold((0_usize, 0_usize), |(count, bytes), event| {
        (count + 1, bytes.saturating_add(event.byte_size))
    });
    state.queue.len().saturating_sub(count) < capacity
        && state
            .bytes
            .saturating_sub(bytes)
            .checked_add(incoming.byte_size)
            .is_some_and(|bytes| bytes <= byte_capacity)
}

fn evict_until_fits(
    state: &mut QueueState,
    incoming: &QueuedObservabilityEvent,
    incoming_rank: u8,
    capacity: usize,
    byte_capacity: usize,
) -> Vec<ObservabilitySeverity> {
    let mut evicted = Vec::new();
    for rank in 0..incoming_rank {
        while !fits(state, incoming, capacity, byte_capacity) {
            let Some(index) = state
                .queue
                .iter()
                .position(|event| event.event.severity.rank() == rank)
            else {
                break;
            };
            let event = state
                .queue
                .remove(index)
                .expect("queue index came from position");
            state.bytes = state.bytes.saturating_sub(event.byte_size);
            evicted.push(event.event.severity);
        }
    }
    evicted
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ObservabilityBuildContext, ObservabilityLayer, ObservabilityOutcome, ObservabilityPrivacy,
    };

    #[test]
    fn higher_severity_replaces_lower_severity_without_reordering_survivors() {
        let queue = PriorityEventQueue::new(2, 1_024);
        assert!(matches!(
            queue.push(queued(
                ObservabilitySeverity::Trace,
                "core.tracing.event",
                64
            )),
            QueuePushResult::Accepted
        ));
        assert!(matches!(
            queue.push(queued(
                ObservabilitySeverity::Debug,
                "core.tracing.span",
                64
            )),
            QueuePushResult::Accepted
        ));
        assert!(matches!(
            queue.push(queued(
                ObservabilitySeverity::Error,
                "observability.runtime.initialization",
                64
            )),
            QueuePushResult::Replaced(ref severities)
                if severities == &[ObservabilitySeverity::Trace]
        ));

        assert_eq!(queue.take().unwrap().event.action_id, "core.tracing.span");
        assert_eq!(
            queue.take().unwrap().event.action_id,
            "observability.runtime.initialization"
        );
    }

    #[test]
    fn mixed_severity_delivery_is_fifo_when_not_congested() {
        let queue = PriorityEventQueue::new(3, 1_024);
        queue.push(queued(
            ObservabilitySeverity::Info,
            "repository.import.validation",
            64,
        ));
        queue.push(queued(
            ObservabilitySeverity::Error,
            "observability.runtime.initialization",
            64,
        ));
        queue.push(queued(
            ObservabilitySeverity::Debug,
            "core.tracing.span",
            64,
        ));

        let delivered = (0..3)
            .map(|_| queue.take().unwrap().event.action_id)
            .collect::<Vec<_>>();
        assert_eq!(
            delivered,
            [
                "repository.import.validation",
                "observability.runtime.initialization",
                "core.tracing.span"
            ]
        );
    }

    #[test]
    fn byte_budget_can_evict_multiple_lower_severity_events() {
        let queue = PriorityEventQueue::new(4, 180);
        queue.push(queued(
            ObservabilitySeverity::Trace,
            "core.tracing.event",
            60,
        ));
        queue.push(queued(
            ObservabilitySeverity::Trace,
            "core.tracing.span",
            60,
        ));
        queue.push(queued(
            ObservabilitySeverity::Info,
            "repository.import.validation",
            60,
        ));

        assert!(matches!(
            queue.push(queued(
                ObservabilitySeverity::Error,
                "observability.runtime.initialization",
                120
            )),
            QueuePushResult::Replaced(ref severities)
                if severities == &[
                    ObservabilitySeverity::Trace,
                    ObservabilitySeverity::Trace,
                ]
        ));
        assert_eq!(
            queue.take().unwrap().event.action_id,
            "repository.import.validation"
        );
        assert_eq!(
            queue.take().unwrap().event.action_id,
            "observability.runtime.initialization"
        );
    }

    #[test]
    fn full_queue_rejects_event_without_lower_priority_candidate() {
        let queue = PriorityEventQueue::new(1, 1_024);
        queue.push(queued(
            ObservabilitySeverity::Error,
            "observability.runtime.initialization",
            64,
        ));

        assert!(matches!(
            queue.push(queued(
                ObservabilitySeverity::Error,
                "repository.import.confirmed",
                64
            )),
            QueuePushResult::Rejected
        ));
    }

    fn queued(
        severity: ObservabilitySeverity,
        action_id: &str,
        byte_size: usize,
    ) -> QueuedObservabilityEvent {
        QueuedObservabilityEvent::new(event(severity, action_id), 1, byte_size)
    }

    fn event(severity: ObservabilitySeverity, action_id: &str) -> CoreObservabilityEvent {
        CoreObservabilityEvent {
            schema_version: 2,
            event_id: uuid::Uuid::new_v4().to_string(),
            wall_timestamp_ms: 0,
            monotonic_timestamp_ns: 0,
            sequence_number: 0,
            session_id: uuid::Uuid::new_v4().to_string(),
            incident_id: None,
            trace_id: uuid::Uuid::new_v4().to_string(),
            span_id: uuid::Uuid::new_v4().to_string(),
            parent_span_id: None,
            operation_id: None,
            retry_of_operation_id: None,
            action_id: action_id.to_owned(),
            component_id: "core.observability.runtime".to_owned(),
            layer: ObservabilityLayer::Core,
            phase: "test".to_owned(),
            severity,
            outcome: ObservabilityOutcome::None,
            duration_ms: None,
            resource_refs: Vec::new(),
            error: None,
            attributes: Vec::new(),
            privacy_level: ObservabilityPrivacy::Public,
            message: None,
            target: None,
            thread_name: None,
            build_context: ObservabilityBuildContext::core(),
        }
    }
}
