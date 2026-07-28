//! Fail-closed validation for structured observability input.

use crate::{CoreError, CoreResult};

use super::{
    catalog::{ensure_catalog, validate_action_id, validate_component_id},
    validation_text::{attribute_privacy_floor, is_credential_key, looks_like_locator},
    CoreObservabilityAttribute, CoreObservabilityEvent, CoreObservabilityResourceRef,
    CoreTraceContext, ObservabilityBuildContext, ObservabilityConfig, ObservabilityPrivacy,
};

const MIN_QUEUE_CAPACITY: u64 = 64;
const MAX_QUEUE_CAPACITY: u64 = 65_536;
const MAX_ID_LENGTH: usize = 128;
pub(super) const MAX_VALUE_LENGTH: usize = 4_096;
const MAX_STRUCTURED_PAYLOAD_BYTES: usize = 65_536;
const MAX_ATTRIBUTES: usize = 64;
const MAX_RESOURCES: usize = 64;
const MAX_EXTENSION_LENGTH: usize = 32;
const RESOURCE_ALIAS_HEX_LENGTH: usize = 24;
const RESOURCE_SIZE_BUCKETS: [&str; 5] =
    ["lt_1mb", "1mb_10mb", "10mb_100mb", "100mb_1gb", "gte_1gb"];
const RESOURCE_STORAGE_MODES: [&str; 3] = ["copied", "moved", "indexed"];

pub(crate) fn validate_config(config: &ObservabilityConfig) -> CoreResult<()> {
    ensure_catalog()?;
    uuid::Uuid::parse_str(&config.session_id)
        .map_err(|_| CoreError::config("observability session id must be a UUID"))?;
    if !(MIN_QUEUE_CAPACITY..=MAX_QUEUE_CAPACITY).contains(&config.queue_capacity) {
        return Err(CoreError::config(
            "observability queue capacity must be between 64 and 65536",
        ));
    }
    Ok(())
}

pub(crate) fn validate_trace_context(context: &CoreTraceContext) -> CoreResult<()> {
    validate_uuid("session id", &context.session_id)?;
    validate_uuid("trace id", &context.trace_id)?;
    validate_optional_uuid("parent span id", context.parent_span_id.as_deref())?;
    validate_optional_uuid("incident id", context.incident_id.as_deref())?;
    validate_optional_uuid("operation id", context.operation_id.as_deref())?;
    validate_optional_uuid(
        "retry operation id",
        context.retry_of_operation_id.as_deref(),
    )?;
    validate_retry_relation(
        context.operation_id.as_deref(),
        context.retry_of_operation_id.as_deref(),
    )?;
    validate_catalog_id("action id", &context.action_id)?;
    validate_catalog_id("component id", &context.component_id)?;
    validate_context_payload(context)?;
    validate_action_id(&context.action_id)?;
    validate_component_id(&context.component_id)?;
    Ok(())
}

pub(super) fn validate_event(event: &CoreObservabilityEvent) -> CoreResult<()> {
    if event.schema_version != 2 {
        return Err(CoreError::validation(
            "observability event schema version is unsupported",
        ));
    }
    validate_uuid("event id", &event.event_id)?;
    validate_uuid("session id", &event.session_id)?;
    validate_uuid("trace id", &event.trace_id)?;
    validate_uuid("span id", &event.span_id)?;
    validate_optional_uuid("parent span id", event.parent_span_id.as_deref())?;
    validate_optional_uuid("incident id", event.incident_id.as_deref())?;
    validate_optional_uuid("operation id", event.operation_id.as_deref())?;
    validate_optional_uuid("retry operation id", event.retry_of_operation_id.as_deref())?;
    validate_retry_relation(
        event.operation_id.as_deref(),
        event.retry_of_operation_id.as_deref(),
    )?;
    validate_catalog_id("action id", &event.action_id)?;
    validate_catalog_id("component id", &event.component_id)?;
    validate_catalog_id("phase", &event.phase)?;
    validate_build_context(&event.build_context)?;
    validate_field_counts(event.attributes.len(), event.resource_refs.len())?;
    validate_event_payload_size(event)?;
    validate_action_id(&event.action_id)?;
    validate_component_id(&event.component_id)
}

fn validate_build_context(context: &ObservabilityBuildContext) -> CoreResult<()> {
    if context != &ObservabilityBuildContext::core() {
        return Err(CoreError::validation(
            "observability build context does not match the current core binary",
        ));
    }
    Ok(())
}

pub(super) fn validate_attribute(attribute: &CoreObservabilityAttribute) -> CoreResult<()> {
    validate_catalog_id("attribute key", &attribute.key)?;
    if is_credential_key(&attribute.key) {
        return Err(CoreError::validation(
            "credential-like observability attribute keys are prohibited",
        ));
    }
    if attribute.value.len() > MAX_VALUE_LENGTH {
        return Err(CoreError::validation(
            "observability attribute value must not exceed 4096 bytes",
        ));
    }
    let privacy_floor = attribute_privacy_floor(&attribute.key);
    if attribute.privacy.rank() < privacy_floor.rank() {
        return Err(CoreError::validation(
            "observability attribute privacy is below its key floor",
        ));
    }
    reject_prohibited_text(&attribute.value)?;
    reject_misclassified_locator(&attribute.value, attribute.privacy)?;
    if attribute.privacy == ObservabilityPrivacy::Prohibited {
        return Err(CoreError::validation(
            "prohibited observability data was rejected",
        ));
    }
    Ok(())
}

pub(super) fn validate_resource(resource: &CoreObservabilityResourceRef) -> CoreResult<()> {
    validate_uuid("resource id", &resource.resource_id)?;
    validate_resource_alias(&resource.alias)?;
    validate_optional_allowlist(
        "resource storage mode",
        resource.storage_mode.as_deref(),
        &RESOURCE_STORAGE_MODES,
    )?;
    validate_optional_allowlist(
        "resource size bucket",
        resource.size_bucket.as_deref(),
        &RESOURCE_SIZE_BUCKETS,
    )?;
    if let Some(extension) = &resource.extension {
        let mut extension = extension.clone();
        normalize_extension(&mut extension)?;
    }
    Ok(())
}

pub(super) fn validate_catalog_id(label: &str, value: &str) -> CoreResult<()> {
    if value.is_empty()
        || value.len() > MAX_ID_LENGTH
        || !value.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-')
        })
    {
        return Err(CoreError::validation(format!(
            "observability {label} is invalid"
        )));
    }
    Ok(())
}

pub(super) fn reject_prohibited_text(value: &str) -> CoreResult<()> {
    let normalized = normalize_security_text(value);
    let markers = [
        "authorization:",
        "authorization=",
        "bearer ",
        "api_key",
        "api-key",
        "apikey",
        "access_token",
        "access-token",
        "accesstoken",
        "refresh_token",
        "refresh-token",
        "refreshtoken",
        "client_secret",
        "client-secret",
        "clientsecret",
        "password=",
        "password:",
        "passwd=",
        "token=",
        "token:",
        "secret=",
        "secret:",
        "private_key",
        "private-key",
        "privatekey",
        "-----begin private key",
        "-----begin rsa private key",
        "-----begin ec private key",
        "-----begin openssh private key",
    ];
    if markers.iter().any(|marker| normalized.contains(marker)) {
        return Err(CoreError::validation(
            "prohibited observability text was rejected",
        ));
    }
    Ok(())
}

fn normalize_security_text(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            let scalar = character as u32;
            if (0xFF01..=0xFF5E).contains(&scalar) {
                char::from_u32(scalar - 0xFEE0).unwrap_or(character)
            } else {
                character
            }
        })
        .collect::<String>()
        .to_lowercase()
}

pub(super) fn reject_misclassified_locator(
    value: &str,
    privacy: ObservabilityPrivacy,
) -> CoreResult<()> {
    if matches!(
        privacy,
        ObservabilityPrivacy::Sensitive | ObservabilityPrivacy::Prohibited
    ) || !looks_like_locator(value)
    {
        return Ok(());
    }
    Err(CoreError::validation(
        "path, URL, or filename observability text must be classified as sensitive",
    ))
}

pub(super) fn normalize_extension(extension: &mut str) -> CoreResult<()> {
    extension.make_ascii_lowercase();
    if extension.is_empty()
        || extension.len() > MAX_EXTENSION_LENGTH
        || !extension
            .chars()
            .all(|character| character.is_ascii_alphanumeric())
    {
        return Err(CoreError::validation(
            "observability resource extension is invalid",
        ));
    }
    Ok(())
}

fn validate_context_payload(context: &CoreTraceContext) -> CoreResult<()> {
    validate_field_counts(context.attributes.len(), context.resource_refs.len())?;
    for attribute in &context.attributes {
        validate_attribute(attribute)?;
    }
    for resource in &context.resource_refs {
        validate_resource(resource)?;
    }
    let identity = [
        Some(context.session_id.as_str()),
        Some(context.trace_id.as_str()),
        context.parent_span_id.as_deref(),
        context.incident_id.as_deref(),
        context.operation_id.as_deref(),
        context.retry_of_operation_id.as_deref(),
        Some(context.action_id.as_str()),
        Some(context.component_id.as_str()),
    ];
    validate_payload_size(
        &context.attributes,
        &context.resource_refs,
        identity.into_iter().flatten(),
    )
}

fn validate_field_counts(attribute_count: usize, resource_count: usize) -> CoreResult<()> {
    if attribute_count > MAX_ATTRIBUTES || resource_count > MAX_RESOURCES {
        return Err(CoreError::validation(
            "observability event exceeds field count limits",
        ));
    }
    Ok(())
}

fn validate_resource_alias(alias: &str) -> CoreResult<()> {
    let valid = alias.strip_prefix("file.").is_some_and(|digest| {
        digest.len() == RESOURCE_ALIAS_HEX_LENGTH
            && digest
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    });
    if !valid {
        return Err(CoreError::validation(
            "observability resource alias must match file.<24 lowercase hex characters>",
        ));
    }
    Ok(())
}

fn validate_optional_allowlist(
    label: &str,
    value: Option<&str>,
    allowed: &[&str],
) -> CoreResult<()> {
    let Some(value) = value else { return Ok(()) };
    if !allowed.contains(&value) {
        return Err(CoreError::validation(format!(
            "observability {label} is invalid"
        )));
    }
    Ok(())
}

fn validate_retry_relation(operation_id: Option<&str>, retry_id: Option<&str>) -> CoreResult<()> {
    let Some(retry_id) = retry_id else {
        return Ok(());
    };
    let Some(operation_id) = operation_id else {
        return Err(CoreError::validation(
            "observability retry requires a new operation id",
        ));
    };
    if retry_id == operation_id {
        return Err(CoreError::validation(
            "observability retry must reference a different operation",
        ));
    }
    Ok(())
}

fn validate_optional_uuid(label: &str, value: Option<&str>) -> CoreResult<()> {
    value.map_or(Ok(()), |value| validate_uuid(label, value))
}

fn validate_uuid(label: &str, value: &str) -> CoreResult<()> {
    uuid::Uuid::parse_str(value)
        .map(|_| ())
        .map_err(|_| CoreError::validation(format!("observability {label} must be a UUID")))
}

fn validate_event_payload_size(event: &CoreObservabilityEvent) -> CoreResult<()> {
    let extra = [
        Some(event.event_id.as_str()),
        Some(event.session_id.as_str()),
        event.incident_id.as_deref(),
        Some(event.trace_id.as_str()),
        Some(event.span_id.as_str()),
        event.parent_span_id.as_deref(),
        event.operation_id.as_deref(),
        event.retry_of_operation_id.as_deref(),
        Some(event.action_id.as_str()),
        Some(event.component_id.as_str()),
        Some(event.phase.as_str()),
        event.message.as_deref(),
        event.target.as_deref(),
        event.thread_name.as_deref(),
        event.error.as_ref().map(|error| error.code.as_str()),
        event.error.as_ref().and_then(|error| error.kind.as_deref()),
        event
            .error
            .as_ref()
            .and_then(|error| error.technical_details.as_deref()),
        Some(event.build_context.producer.as_str()),
        Some(event.build_context.version.as_str()),
        event.build_context.build.as_deref(),
        Some(event.build_context.configuration.as_str()),
        Some(event.build_context.platform.as_str()),
        Some(event.build_context.architecture.as_str()),
    ];
    validate_payload_size(
        &event.attributes,
        &event.resource_refs,
        extra.into_iter().flatten(),
    )
}

fn validate_payload_size<'a>(
    attributes: &[CoreObservabilityAttribute],
    resources: &[CoreObservabilityResourceRef],
    extra: impl IntoIterator<Item = &'a str>,
) -> CoreResult<()> {
    let mut total = 0_usize;
    for attribute in attributes {
        add_payload_bytes(&mut total, &attribute.key)?;
        add_payload_bytes(&mut total, &attribute.value)?;
    }
    for resource in resources {
        add_payload_bytes(&mut total, &resource.resource_id)?;
        add_payload_bytes(&mut total, &resource.alias)?;
        for value in [
            resource.extension.as_deref(),
            resource.size_bucket.as_deref(),
            resource.storage_mode.as_deref(),
        ]
        .into_iter()
        .flatten()
        {
            add_payload_bytes(&mut total, value)?;
        }
    }
    for value in extra {
        add_payload_bytes(&mut total, value)?;
    }
    Ok(())
}

fn add_payload_bytes(total: &mut usize, value: &str) -> CoreResult<()> {
    *total = total
        .checked_add(value.len())
        .filter(|total| *total <= MAX_STRUCTURED_PAYLOAD_BYTES)
        .ok_or_else(|| {
            CoreError::validation("observability structured payload must not exceed 65536 bytes")
        })?;
    Ok(())
}
