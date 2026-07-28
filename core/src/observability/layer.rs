//! Tracing layer that converts registered Core events to owned DTOs.

use std::{
    collections::BTreeMap,
    thread,
    time::{Instant, SystemTime},
};

use tracing::{
    field::Visit,
    span::{Attributes, Record},
    Event, Id, Level, Metadata, Subscriber,
};
use tracing_subscriber::{
    layer::Context,
    prelude::*,
    registry::{LookupSpan, SpanRef},
    Layer,
};
use uuid::Uuid;

use super::{
    runtime_api, CoreObservabilityAttribute, CoreObservabilityEvent, ObservabilityBuildContext,
    ObservabilityLayer, ObservabilityOutcome, ObservabilityPrivacy, ObservabilitySeverity,
};

pub(crate) struct CoreObservabilityLayer;

impl<S> Layer<S> for CoreObservabilityLayer
where
    S: Subscriber + for<'lookup> LookupSpan<'lookup>,
{
    fn on_new_span(&self, attributes: &Attributes<'_>, id: &Id, context: Context<'_, S>) {
        let mut visitor = SafeFieldVisitor::default();
        attributes.record(&mut visitor);
        let Some(span) = context.span(id) else { return };
        let parent = span.parent().and_then(span_state);
        let state = SpanState::new(&mut visitor, parent.as_ref(), span.metadata());
        let started_event = state.event("started", ObservabilityOutcome::Started, None);
        span.extensions_mut().insert(state);
        runtime_api::submit(started_event);
    }

    fn on_record(&self, id: &Id, values: &Record<'_>, context: Context<'_, S>) {
        let mut visitor = SafeFieldVisitor::default();
        values.record(&mut visitor);
        let Some(span) = context.span(id) else { return };
        let mut extensions = span.extensions_mut();
        if let Some(state) = extensions.get_mut::<SpanState>() {
            state.record(&mut visitor);
        }
    }

    fn on_event(&self, event: &Event<'_>, context: Context<'_, S>) {
        let mut visitor = SafeFieldVisitor::default();
        event.record(&mut visitor);
        let current = context.event_span(event).and_then(span_state);
        runtime_api::submit(tracing_event(visitor, current.as_ref(), event.metadata()));
    }

    fn on_close(&self, id: Id, context: Context<'_, S>) {
        let Some(span) = context.span(&id) else {
            return;
        };
        let Some(state) = span_state(span) else {
            return;
        };
        runtime_api::submit(state.event(
            "completed",
            state.close_outcome,
            Some(state.started.elapsed().as_millis().min(u64::MAX as u128) as u64),
        ));
    }
}

pub(crate) fn install_global_subscriber() -> Result<(), String> {
    let subscriber = tracing_subscriber::registry().with(CoreObservabilityLayer);
    tracing::subscriber::set_global_default(subscriber).map_err(|error| error.to_string())
}

struct TracingEventIdentity {
    incident_id: Option<String>,
    trace_id: String,
    span_id: String,
    parent_span_id: Option<String>,
    operation_id: Option<String>,
    retry_of_operation_id: Option<String>,
}

impl TracingEventIdentity {
    fn take(visitor: &mut SafeFieldVisitor, current: Option<&SpanState>) -> Self {
        Self {
            incident_id: inherited_optional(
                visitor,
                "incident_id",
                current.and_then(|state| state.incident_id.as_deref()),
            ),
            trace_id: inherited(
                visitor,
                "trace_id",
                current.map(|state| state.trace_id.as_str()),
            ),
            span_id: inherited(
                visitor,
                "span_id",
                current.map(|state| state.span_id.as_str()),
            ),
            parent_span_id: inherited_optional(
                visitor,
                "parent_span_id",
                current.and_then(|state| state.parent_span_id.as_deref()),
            ),
            operation_id: inherited_optional(
                visitor,
                "operation_id",
                current.and_then(|state| state.operation_id.as_deref()),
            ),
            retry_of_operation_id: inherited_optional(
                visitor,
                "retry_of_operation_id",
                current.and_then(|state| state.retry_of_operation_id.as_deref()),
            ),
        }
    }
}

fn tracing_event(
    mut visitor: SafeFieldVisitor,
    current: Option<&SpanState>,
    metadata: &Metadata<'_>,
) -> CoreObservabilityEvent {
    let identity = TracingEventIdentity::take(&mut visitor, current);
    let action_id = visitor
        .take("action_id")
        .or_else(|| current.map(|state| state.action_id.clone()))
        .unwrap_or_else(|| "core.tracing.event".to_owned());
    let component_id = visitor
        .take("component_id")
        .or_else(|| current.map(|state| state.component_id.clone()))
        .unwrap_or_else(|| "core.observability.runtime".to_owned());
    let phase = visitor.take("phase").unwrap_or_else(|| "event".to_owned());
    let outcome = parse_outcome(visitor.take("outcome").as_deref());
    let duration_ms = visitor
        .take("duration_ms")
        .and_then(|value| value.parse().ok());
    CoreObservabilityEvent {
        schema_version: 2,
        event_id: Uuid::new_v4().to_string(),
        wall_timestamp_ms: wall_timestamp_ms(),
        monotonic_timestamp_ns: 0,
        sequence_number: 0,
        session_id: Uuid::nil().to_string(),
        incident_id: identity.incident_id,
        trace_id: identity.trace_id,
        span_id: identity.span_id,
        parent_span_id: identity.parent_span_id,
        operation_id: identity.operation_id,
        retry_of_operation_id: identity.retry_of_operation_id,
        action_id,
        component_id,
        layer: ObservabilityLayer::Core,
        phase,
        severity: severity(metadata.level()),
        outcome,
        duration_ms,
        resource_refs: Vec::new(),
        error: None,
        attributes: visitor.public_attributes(),
        privacy_level: ObservabilityPrivacy::Public,
        message: None,
        target: Some(metadata.target().to_owned()),
        thread_name: thread::current().name().map(str::to_owned),
        build_context: ObservabilityBuildContext::core(),
    }
}

#[derive(Clone)]
struct SpanState {
    trace_id: String,
    span_id: String,
    parent_span_id: Option<String>,
    incident_id: Option<String>,
    operation_id: Option<String>,
    retry_of_operation_id: Option<String>,
    action_id: String,
    component_id: String,
    attributes: Vec<CoreObservabilityAttribute>,
    severity: ObservabilitySeverity,
    close_outcome: ObservabilityOutcome,
    target: String,
    started: Instant,
}

impl SpanState {
    fn new(visitor: &mut SafeFieldVisitor, parent: Option<&Self>, metadata: &Metadata<'_>) -> Self {
        let outcome = parse_outcome(visitor.take("outcome").as_deref());
        Self {
            trace_id: inherited(
                visitor,
                "trace_id",
                parent.map(|state| state.trace_id.as_str()),
            ),
            span_id: inherited(visitor, "span_id", None),
            parent_span_id: inherited_optional(
                visitor,
                "parent_span_id",
                parent.map(|state| state.span_id.as_str()),
            ),
            incident_id: inherited_optional(
                visitor,
                "incident_id",
                parent.and_then(|state| state.incident_id.as_deref()),
            ),
            operation_id: inherited_optional(
                visitor,
                "operation_id",
                parent.and_then(|state| state.operation_id.as_deref()),
            ),
            retry_of_operation_id: inherited_optional(
                visitor,
                "retry_of_operation_id",
                parent.and_then(|state| state.retry_of_operation_id.as_deref()),
            ),
            action_id: visitor
                .take("action_id")
                .unwrap_or_else(|| "core.tracing.span".to_owned()),
            component_id: visitor
                .take("component_id")
                .unwrap_or_else(|| "core.observability.runtime".to_owned()),
            attributes: std::mem::take(visitor).public_attributes(),
            severity: severity(metadata.level()),
            close_outcome: terminal_span_outcome(outcome),
            target: metadata.target().to_owned(),
            started: Instant::now(),
        }
    }

    fn record(&mut self, visitor: &mut SafeFieldVisitor) {
        if let Some(outcome) = visitor.take("outcome") {
            self.close_outcome = terminal_span_outcome(parse_outcome(Some(&outcome)));
        }
        for attribute in std::mem::take(visitor).public_attributes() {
            if let Some(existing) = self
                .attributes
                .iter_mut()
                .find(|existing| existing.key == attribute.key)
            {
                *existing = attribute;
            } else {
                self.attributes.push(attribute);
            }
        }
    }

    fn event(
        &self,
        phase: &str,
        outcome: ObservabilityOutcome,
        duration_ms: Option<u64>,
    ) -> CoreObservabilityEvent {
        CoreObservabilityEvent {
            schema_version: 2,
            event_id: Uuid::new_v4().to_string(),
            wall_timestamp_ms: wall_timestamp_ms(),
            monotonic_timestamp_ns: 0,
            sequence_number: 0,
            session_id: Uuid::nil().to_string(),
            incident_id: self.incident_id.clone(),
            trace_id: self.trace_id.clone(),
            span_id: self.span_id.clone(),
            parent_span_id: self.parent_span_id.clone(),
            operation_id: self.operation_id.clone(),
            retry_of_operation_id: self.retry_of_operation_id.clone(),
            action_id: self.action_id.clone(),
            component_id: self.component_id.clone(),
            layer: ObservabilityLayer::Core,
            phase: phase.to_owned(),
            severity: span_severity(self.severity, outcome),
            outcome,
            duration_ms,
            resource_refs: Vec::new(),
            error: None,
            attributes: self.attributes.clone(),
            privacy_level: ObservabilityPrivacy::Public,
            message: None,
            target: Some(self.target.clone()),
            thread_name: thread::current().name().map(str::to_owned),
            build_context: ObservabilityBuildContext::core(),
        }
    }
}

fn span_state<S>(span: SpanRef<'_, S>) -> Option<SpanState>
where
    S: Subscriber + for<'lookup> LookupSpan<'lookup>,
{
    span.extensions().get::<SpanState>().cloned()
}

fn inherited(visitor: &mut SafeFieldVisitor, key: &str, inherited: Option<&str>) -> String {
    visitor
        .take(key)
        .or_else(|| inherited.map(str::to_owned))
        .unwrap_or_else(|| Uuid::new_v4().to_string())
}

fn inherited_optional(
    visitor: &mut SafeFieldVisitor,
    key: &str,
    inherited: Option<&str>,
) -> Option<String> {
    visitor.take(key).or_else(|| inherited.map(str::to_owned))
}

fn terminal_span_outcome(outcome: ObservabilityOutcome) -> ObservabilityOutcome {
    match outcome {
        ObservabilityOutcome::None | ObservabilityOutcome::Started => {
            ObservabilityOutcome::Succeeded
        }
        terminal => terminal,
    }
}

fn span_severity(
    declared: ObservabilitySeverity,
    outcome: ObservabilityOutcome,
) -> ObservabilitySeverity {
    match outcome {
        ObservabilityOutcome::Failed => ObservabilitySeverity::Error,
        ObservabilityOutcome::Degraded => ObservabilitySeverity::Warn,
        _ => declared,
    }
}

#[derive(Default)]
struct SafeFieldVisitor {
    fields: BTreeMap<String, String>,
}

impl SafeFieldVisitor {
    fn take(&mut self, key: &str) -> Option<String> {
        self.fields.remove(key)
    }

    fn public_attributes(self) -> Vec<CoreObservabilityAttribute> {
        self.fields
            .into_iter()
            .filter(|(key, _)| key.starts_with("obs_"))
            .map(|(key, value)| {
                let (key, privacy) = classified_attribute(key);
                CoreObservabilityAttribute {
                    key,
                    value,
                    privacy,
                }
            })
            .collect()
    }

    fn record(&mut self, field: &tracing::field::Field, value: String) {
        let key = field.name();
        if is_allowed_field(key) {
            self.fields.insert(key.to_owned(), value);
        }
    }
}

fn classified_attribute(key: String) -> (String, ObservabilityPrivacy) {
    for (prefix, privacy) in [
        ("obs_public_", ObservabilityPrivacy::Public),
        ("obs_pseudonymous_", ObservabilityPrivacy::Pseudonymous),
        ("obs_sensitive_", ObservabilityPrivacy::Sensitive),
        ("obs_prohibited_", ObservabilityPrivacy::Prohibited),
    ] {
        if let Some(key) = key.strip_prefix(prefix) {
            return (key.to_owned(), privacy);
        }
    }
    (key, ObservabilityPrivacy::Prohibited)
}

impl Visit for SafeFieldVisitor {
    fn record_i64(&mut self, field: &tracing::field::Field, value: i64) {
        self.record(field, value.to_string());
    }

    fn record_u64(&mut self, field: &tracing::field::Field, value: u64) {
        self.record(field, value.to_string());
    }

    fn record_bool(&mut self, field: &tracing::field::Field, value: bool) {
        self.record(field, value.to_string());
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        self.record(field, value.to_owned());
    }

    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        self.record(field, format!("{value:?}"));
    }
}

fn is_allowed_field(key: &str) -> bool {
    matches!(
        key,
        "session_id"
            | "trace_id"
            | "span_id"
            | "parent_span_id"
            | "incident_id"
            | "operation_id"
            | "retry_of_operation_id"
            | "action_id"
            | "component_id"
            | "phase"
            | "outcome"
            | "duration_ms"
    ) || key.starts_with("obs_")
}

fn severity(level: &Level) -> ObservabilitySeverity {
    match *level {
        Level::TRACE => ObservabilitySeverity::Trace,
        Level::DEBUG => ObservabilitySeverity::Debug,
        Level::INFO => ObservabilitySeverity::Info,
        Level::WARN => ObservabilitySeverity::Warn,
        Level::ERROR => ObservabilitySeverity::Error,
    }
}

fn parse_outcome(value: Option<&str>) -> ObservabilityOutcome {
    match value {
        Some("started") => ObservabilityOutcome::Started,
        Some("succeeded") => ObservabilityOutcome::Succeeded,
        Some("failed") => ObservabilityOutcome::Failed,
        Some("cancelled") => ObservabilityOutcome::Cancelled,
        Some("skipped") => ObservabilityOutcome::Skipped,
        Some("degraded") => ObservabilityOutcome::Degraded,
        _ => ObservabilityOutcome::None,
    }
}

fn wall_timestamp_ms() -> i64 {
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
}

#[cfg(test)]
#[path = "layer_tests.rs"]
mod tests;
