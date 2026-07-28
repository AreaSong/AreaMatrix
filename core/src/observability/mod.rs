//! Platform-neutral structured observability runtime.

mod callback;
mod catalog;
mod layer;
mod operation;
mod queue;
mod redaction;
mod runtime;
mod runtime_api;
mod types;
mod validation;
mod validation_text;

pub use types::{
    CoreObservabilityAttribute, CoreObservabilityError, CoreObservabilityEvent,
    CoreObservabilityResourceRef, CoreObservabilitySink, CoreTraceContext,
    ObservabilityBuildContext, ObservabilityConfig, ObservabilityHealth, ObservabilityLayer,
    ObservabilityMode, ObservabilityOutcome, ObservabilityPrivacy, ObservabilitySeverity,
};

pub(crate) use operation::CoreOperationTrace;
pub(crate) use runtime_api::{flush, health, initialize, legacy_configuration, update_config};
