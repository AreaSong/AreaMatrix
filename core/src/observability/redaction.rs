//! Source-side validation and redaction for Core observability events.

use crate::{CoreError, CoreResult};

use super::validation::{
    normalize_extension, reject_misclassified_locator, reject_prohibited_text, validate_attribute,
    validate_catalog_id, validate_event, validate_resource, MAX_VALUE_LENGTH,
};
#[cfg(test)]
use super::validation::{validate_config, validate_trace_context};
use super::validation_text::{is_credential_key, looks_like_locator};
use super::{
    CoreObservabilityAttribute, CoreObservabilityError, CoreObservabilityEvent,
    CoreObservabilityResourceRef, ObservabilityConfig, ObservabilityPrivacy, ObservabilitySeverity,
};

pub(crate) fn sanitize_event(
    mut event: CoreObservabilityEvent,
    config: &ObservabilityConfig,
) -> CoreResult<CoreObservabilityEvent> {
    if event.privacy_level == ObservabilityPrivacy::Prohibited {
        return Err(CoreError::validation(
            "prohibited observability data was rejected",
        ));
    }
    validate_event(&event)?;
    let mut highest_privacy =
        sanitize_attributes(&mut event.attributes, config, event.privacy_level)?;
    highest_privacy = sanitize_resources(&mut event.resource_refs, highest_privacy)?;
    highest_privacy = sanitize_error(&mut event.error, config, highest_privacy)?;
    if let Some(message) = &mut event.message {
        reject_prohibited_text(message)?;
        reject_misclassified_locator(message, event.privacy_level)?;
        bound_value(message);
        apply_privacy(message, event.privacy_level, config)?;
    }
    sanitize_optional_catalog_metadata(&mut event.target);
    sanitize_optional_catalog_metadata(&mut event.thread_name);
    event.privacy_level = highest_privacy;
    Ok(event)
}

fn sanitize_attributes(
    attributes: &mut [CoreObservabilityAttribute],
    config: &ObservabilityConfig,
    mut highest: ObservabilityPrivacy,
) -> CoreResult<ObservabilityPrivacy> {
    for attribute in attributes {
        validate_attribute(attribute)?;
        bound_value(&mut attribute.value);
        apply_privacy(&mut attribute.value, attribute.privacy, config)?;
        highest = highest.max(attribute.privacy);
    }
    Ok(highest)
}

fn sanitize_resources(
    resources: &mut [CoreObservabilityResourceRef],
    mut highest: ObservabilityPrivacy,
) -> CoreResult<ObservabilityPrivacy> {
    for resource in resources {
        validate_resource(resource)?;
        if let Some(extension) = &mut resource.extension {
            normalize_extension(extension)?;
        }
        highest = highest.max(ObservabilityPrivacy::Pseudonymous);
    }
    Ok(highest)
}

fn sanitize_error(
    error: &mut Option<CoreObservabilityError>,
    config: &ObservabilityConfig,
    mut highest: ObservabilityPrivacy,
) -> CoreResult<ObservabilityPrivacy> {
    let Some(error) = error else {
        return Ok(highest);
    };
    validate_catalog_id("error code", &error.code)?;
    if let Some(kind) = error.kind.as_deref() {
        validate_catalog_id("error kind", kind)?;
    }
    if let Some(detail) = &mut error.technical_details {
        reject_prohibited_text(detail)?;
        bound_value(detail);
        apply_privacy(detail, ObservabilityPrivacy::Sensitive, config)?;
        highest = highest.max(ObservabilityPrivacy::Sensitive);
    }
    Ok(highest)
}

pub(crate) fn severity_is_enabled(
    severity: ObservabilitySeverity,
    config: &ObservabilityConfig,
) -> bool {
    let mode_floor = match config.mode {
        super::ObservabilityMode::Disabled => ObservabilitySeverity::Error,
        super::ObservabilityMode::Standard => ObservabilitySeverity::Info,
        super::ObservabilityMode::Diagnostic => ObservabilitySeverity::Debug,
        super::ObservabilityMode::Developer => ObservabilitySeverity::Trace,
    };
    severity.rank() >= mode_floor.rank().max(config.minimum_severity.rank())
}

pub(crate) fn estimated_event_bytes(event: &CoreObservabilityEvent) -> usize {
    let required = estimated_strings([
        event.event_id.as_str(),
        event.session_id.as_str(),
        event.trace_id.as_str(),
        event.span_id.as_str(),
        event.action_id.as_str(),
        event.component_id.as_str(),
        event.phase.as_str(),
        event.build_context.producer.as_str(),
        event.build_context.version.as_str(),
        event.build_context.configuration.as_str(),
        event.build_context.platform.as_str(),
        event.build_context.architecture.as_str(),
    ]);
    let optional = estimated_strings(
        [
            event.incident_id.as_deref(),
            event.parent_span_id.as_deref(),
            event.operation_id.as_deref(),
            event.retry_of_operation_id.as_deref(),
            event.message.as_deref(),
            event.target.as_deref(),
            event.thread_name.as_deref(),
            event.build_context.build.as_deref(),
        ]
        .into_iter()
        .flatten(),
    );
    let attributes = event.attributes.iter().fold(0_usize, |total, attribute| {
        total
            .saturating_add(attribute.key.len())
            .saturating_add(attribute.value.len())
    });
    let resources = event
        .resource_refs
        .iter()
        .map(estimated_resource_bytes)
        .fold(0_usize, usize::saturating_add);
    512_usize
        .saturating_add(required)
        .saturating_add(optional)
        .saturating_add(attributes)
        .saturating_add(resources)
        .saturating_add(event.error.as_ref().map_or(0, estimated_error_bytes))
}

fn estimated_strings<'a>(values: impl IntoIterator<Item = &'a str>) -> usize {
    values
        .into_iter()
        .map(str::len)
        .fold(0_usize, usize::saturating_add)
}

fn estimated_resource_bytes(resource: &CoreObservabilityResourceRef) -> usize {
    estimated_strings([resource.resource_id.as_str(), resource.alias.as_str()]).saturating_add(
        estimated_strings(
            [
                resource.extension.as_deref(),
                resource.size_bucket.as_deref(),
                resource.storage_mode.as_deref(),
            ]
            .into_iter()
            .flatten(),
        ),
    )
}

fn estimated_error_bytes(error: &CoreObservabilityError) -> usize {
    estimated_strings(
        [
            Some(error.code.as_str()),
            error.kind.as_deref(),
            error.technical_details.as_deref(),
        ]
        .into_iter()
        .flatten(),
    )
}

fn apply_privacy(
    value: &mut String,
    privacy: ObservabilityPrivacy,
    config: &ObservabilityConfig,
) -> CoreResult<()> {
    match privacy {
        ObservabilityPrivacy::Prohibited => Err(CoreError::validation(
            "prohibited observability data was rejected",
        )),
        ObservabilityPrivacy::Sensitive if !config.include_sensitive => {
            *value = "[REDACTED]".to_owned();
            Ok(())
        }
        _ => Ok(()),
    }
}

fn bound_value(value: &mut String) {
    if value.len() <= MAX_VALUE_LENGTH {
        return;
    }
    let mut boundary = MAX_VALUE_LENGTH;
    while !value.is_char_boundary(boundary) {
        boundary -= 1;
    }
    value.truncate(boundary);
}

fn sanitize_optional_catalog_metadata(value: &mut Option<String>) {
    let keep = value.as_deref().is_some_and(|value| {
        validate_catalog_id("metadata", value).is_ok()
            && !is_credential_key(value)
            && !looks_like_locator(value)
            && reject_prohibited_text(value).is_ok()
    });
    if !keep {
        *value = None;
    }
}

#[cfg(test)]
#[path = "redaction_tests.rs"]
mod tests;
