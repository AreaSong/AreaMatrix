//! Explicit operation traces propagated across the FFI boundary.

use std::time::{Instant, SystemTime};

use uuid::Uuid;

use crate::{CoreError, CoreResult};

use super::{
    runtime_api, validation::validate_trace_context, CoreObservabilityError,
    CoreObservabilityEvent, CoreTraceContext, ObservabilityBuildContext, ObservabilityLayer,
    ObservabilityOutcome, ObservabilityPrivacy, ObservabilitySeverity,
};

pub(crate) struct CoreOperationTrace {
    context: CoreTraceContext,
    span_id: String,
    started: Instant,
}

impl CoreOperationTrace {
    pub(crate) fn start(context: CoreTraceContext) -> CoreResult<Self> {
        validate_trace_context(&context)?;
        runtime_api::validate_context_session(&context.session_id)?;
        let trace = Self {
            context,
            span_id: Uuid::new_v4().to_string(),
            started: Instant::now(),
        };
        trace.emit(
            "started",
            ObservabilitySeverity::Info,
            ObservabilityOutcome::Started,
            None,
        );
        Ok(trace)
    }

    pub(crate) fn finish<T>(&self, result: &CoreResult<T>) {
        match result {
            Ok(_) => self.finish_with_outcome(ObservabilityOutcome::Succeeded, None),
            Err(error) => self.finish_with_outcome(ObservabilityOutcome::Failed, Some(error)),
        }
    }

    pub(crate) fn finish_with_outcome(
        &self,
        outcome: ObservabilityOutcome,
        error: Option<&CoreError>,
    ) {
        self.emit("completed", severity_for_outcome(outcome), outcome, error);
    }

    pub(crate) fn stage<T>(
        &self,
        action_id: &str,
        component_id: &str,
        operation: impl FnOnce() -> CoreResult<T>,
    ) -> CoreResult<T> {
        let span_id = Uuid::new_v4().to_string();
        let started = Instant::now();
        self.emit_stage(
            action_id,
            component_id,
            &span_id,
            "started",
            ObservabilityOutcome::Started,
            None,
            None,
        );
        let result = operation();
        let (outcome, error) = match &result {
            Ok(_) => (ObservabilityOutcome::Succeeded, None),
            Err(error) => (ObservabilityOutcome::Failed, Some(error)),
        };
        self.emit_stage(
            action_id,
            component_id,
            &span_id,
            "completed",
            outcome,
            Some(elapsed_ms(started)),
            error,
        );
        result
    }

    pub(crate) fn stage_with_outcome<T>(
        &self,
        action_id: &str,
        component_id: &str,
        operation: impl FnOnce() -> T,
        classify: impl FnOnce(&T) -> ObservabilityOutcome,
    ) -> T {
        let span_id = Uuid::new_v4().to_string();
        let started = Instant::now();
        self.emit_stage(
            action_id,
            component_id,
            &span_id,
            "started",
            ObservabilityOutcome::Started,
            None,
            None,
        );
        let result = operation();
        let outcome = classify(&result);
        self.emit_stage(
            action_id,
            component_id,
            &span_id,
            "completed",
            outcome,
            Some(elapsed_ms(started)),
            None,
        );
        result
    }

    pub(crate) fn skip_stage(&self, action_id: &str, component_id: &str) {
        self.emit_stage(
            action_id,
            component_id,
            &Uuid::new_v4().to_string(),
            "skipped",
            ObservabilityOutcome::Skipped,
            None,
            None,
        );
    }

    pub(crate) fn event(
        &self,
        action_id: &str,
        component_id: &str,
        phase: &str,
        outcome: ObservabilityOutcome,
        attributes: Vec<super::CoreObservabilityAttribute>,
    ) {
        let span_id = Uuid::new_v4().to_string();
        let mut event = self.stage_event(
            action_id,
            component_id,
            &span_id,
            phase,
            outcome,
            None,
            None,
        );
        event.attributes = attributes;
        runtime_api::submit(event);
    }

    fn emit(
        &self,
        phase: &str,
        severity: ObservabilitySeverity,
        outcome: ObservabilityOutcome,
        error: Option<&CoreError>,
    ) {
        runtime_api::submit(CoreObservabilityEvent {
            schema_version: 2,
            event_id: Uuid::new_v4().to_string(),
            wall_timestamp_ms: wall_timestamp_ms(),
            monotonic_timestamp_ns: 0,
            sequence_number: 0,
            session_id: self.context.session_id.clone(),
            incident_id: self.context.incident_id.clone(),
            trace_id: self.context.trace_id.clone(),
            span_id: self.span_id.clone(),
            parent_span_id: self.context.parent_span_id.clone(),
            operation_id: self.context.operation_id.clone(),
            retry_of_operation_id: self.context.retry_of_operation_id.clone(),
            action_id: self.context.action_id.clone(),
            component_id: self.context.component_id.clone(),
            layer: ObservabilityLayer::Core,
            phase: phase.to_owned(),
            severity,
            outcome,
            duration_ms: (phase == "completed")
                .then(|| self.started.elapsed().as_millis().min(u64::MAX as u128) as u64),
            resource_refs: self.context.resource_refs.clone(),
            error: error.map(structured_error),
            attributes: self.context.attributes.clone(),
            privacy_level: ObservabilityPrivacy::Public,
            message: None,
            target: Some("area_matrix_core.operation".to_owned()),
            thread_name: std::thread::current().name().map(str::to_owned),
            build_context: ObservabilityBuildContext::core(),
        });
    }

    #[allow(clippy::too_many_arguments)]
    fn emit_stage(
        &self,
        action_id: &str,
        component_id: &str,
        span_id: &str,
        phase: &str,
        outcome: ObservabilityOutcome,
        duration_ms: Option<u64>,
        error: Option<&CoreError>,
    ) {
        runtime_api::submit(self.stage_event(
            action_id,
            component_id,
            span_id,
            phase,
            outcome,
            duration_ms,
            error,
        ));
    }

    #[allow(clippy::too_many_arguments)]
    fn stage_event(
        &self,
        action_id: &str,
        component_id: &str,
        span_id: &str,
        phase: &str,
        outcome: ObservabilityOutcome,
        duration_ms: Option<u64>,
        error: Option<&CoreError>,
    ) -> CoreObservabilityEvent {
        CoreObservabilityEvent {
            schema_version: 2,
            event_id: Uuid::new_v4().to_string(),
            wall_timestamp_ms: wall_timestamp_ms(),
            monotonic_timestamp_ns: 0,
            sequence_number: 0,
            session_id: self.context.session_id.clone(),
            incident_id: self.context.incident_id.clone(),
            trace_id: self.context.trace_id.clone(),
            span_id: span_id.to_owned(),
            parent_span_id: Some(self.span_id.clone()),
            operation_id: self.context.operation_id.clone(),
            retry_of_operation_id: self.context.retry_of_operation_id.clone(),
            action_id: action_id.to_owned(),
            component_id: component_id.to_owned(),
            layer: ObservabilityLayer::Core,
            phase: phase.to_owned(),
            severity: severity_for_outcome(outcome),
            outcome,
            duration_ms,
            resource_refs: self.context.resource_refs.clone(),
            error: error.map(structured_error),
            attributes: self.context.attributes.clone(),
            privacy_level: ObservabilityPrivacy::Public,
            message: None,
            target: Some("area_matrix_core.operation".to_owned()),
            thread_name: std::thread::current().name().map(str::to_owned),
            build_context: ObservabilityBuildContext::core(),
        }
    }
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis().min(u64::MAX as u128) as u64
}

fn severity_for_outcome(outcome: ObservabilityOutcome) -> ObservabilitySeverity {
    match outcome {
        ObservabilityOutcome::Failed => ObservabilitySeverity::Error,
        ObservabilityOutcome::Degraded => ObservabilitySeverity::Warn,
        ObservabilityOutcome::None
        | ObservabilityOutcome::Started
        | ObservabilityOutcome::Succeeded
        | ObservabilityOutcome::Cancelled
        | ObservabilityOutcome::Skipped => ObservabilitySeverity::Info,
    }
}

fn structured_error(error: &CoreError) -> CoreObservabilityError {
    let mapping = error.to_error_mapping();
    CoreObservabilityError {
        code: mapping.code,
        kind: None,
        technical_details: None,
    }
}

fn wall_timestamp_ms() -> i64 {
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
}
