use super::*;
use crate::{
    CoreError, CoreObservabilityAttribute, CoreObservabilityError, CoreObservabilityResourceRef,
    CoreTraceContext, ObservabilityBuildContext, ObservabilityLayer, ObservabilityMode,
    ObservabilityOutcome,
};

#[test]
fn sensitive_values_are_redacted_before_delivery() {
    let mut event = event();
    event.attributes.push(CoreObservabilityAttribute {
        key: "source.name".to_owned(),
        value: "private.txt".to_owned(),
        privacy: ObservabilityPrivacy::Sensitive,
    });

    let sanitized = sanitize_event(event, &config(false)).unwrap();

    assert_eq!(sanitized.attributes[0].value, "[REDACTED]");
    assert_eq!(sanitized.privacy_level, ObservabilityPrivacy::Sensitive);
}

#[test]
fn prohibited_event_is_rejected_even_without_payload_fields() {
    let mut event = event();
    event.privacy_level = ObservabilityPrivacy::Prohibited;

    assert!(sanitize_event(event, &config(true)).is_err());
}

#[test]
fn core_only_accepts_current_schema_and_its_own_build_identity() {
    let mut legacy = event();
    legacy.schema_version = 1;
    assert!(sanitize_event(legacy, &config(false)).is_err());

    let mut foreign = event();
    foreign.build_context.producer = "areamatrix_macos".to_owned();
    assert!(sanitize_event(foreign, &config(false)).is_err());

    let current = sanitize_event(event(), &config(false)).unwrap();
    assert_eq!(current.schema_version, 2);
    assert_eq!(current.build_context.producer, "area_matrix_core");
    assert_eq!(current.build_context.version, env!("CARGO_PKG_VERSION"));
    assert!(matches!(
        current.build_context.configuration.as_str(),
        "debug" | "release"
    ));
    assert!(!current.build_context.platform.is_empty());
    assert!(!current.build_context.architecture.is_empty());
}

#[test]
fn core_build_context_must_match_the_current_binary_exactly() {
    let mut candidates = Vec::new();
    for replacement in ["0.0.0", "999.0.0"] {
        let mut candidate = event();
        candidate.build_context.version = replacement.to_owned();
        candidates.push(candidate);
    }
    let mut build = event();
    build.build_context.build = Some("forged-build".to_owned());
    candidates.push(build);
    let mut configuration = event();
    configuration.build_context.configuration = "release".to_owned();
    if configuration.build_context == ObservabilityBuildContext::core() {
        configuration.build_context.configuration = "debug".to_owned();
    }
    candidates.push(configuration);
    let mut platform = event();
    platform.build_context.platform = "linux".to_owned();
    candidates.push(platform);
    let mut architecture = event();
    architecture.build_context.architecture = "arm64".to_owned();
    candidates.push(architecture);

    for candidate in candidates {
        assert!(sanitize_event(candidate, &config(false)).is_err());
    }
}

#[test]
fn resource_extensions_are_normalized() {
    let mut event = event();
    event.resource_refs.push(CoreObservabilityResourceRef {
        resource_id: uuid::Uuid::new_v4().to_string(),
        alias: "file.0123456789abcdef01234567".to_owned(),
        extension: Some("PDF".to_owned()),
        size_bucket: Some("lt_1mb".to_owned()),
        storage_mode: Some("copied".to_owned()),
    });

    let sanitized = sanitize_event(event, &config(false)).unwrap();

    assert_eq!(sanitized.resource_refs[0].extension.as_deref(), Some("pdf"));
    assert_eq!(sanitized.privacy_level, ObservabilityPrivacy::Pseudonymous);
}

#[test]
fn resource_alias_and_metadata_follow_the_platform_wire_contract() {
    for alias in [
        "private-client.pdf",
        "file.0123456789abcdef0123456",
        "file.0123456789abcdef012345678",
        "file.0123456789ABCDEF01234567",
        "file.0123456789abcdef0123456g",
    ] {
        let mut event = event();
        event.resource_refs.push(resource(alias));
        assert!(sanitize_event(event, &config(false)).is_err(), "{alias}");
    }

    for (size_bucket, storage_mode) in [
        (Some("tiny"), Some("copied")),
        (Some("lt_1mb"), Some("external")),
    ] {
        let mut reference = resource("file.0123456789abcdef01234567");
        reference.size_bucket = size_bucket.map(str::to_owned);
        reference.storage_mode = storage_mode.map(str::to_owned);
        let mut event = event();
        event.resource_refs.push(reference);
        assert!(sanitize_event(event, &config(false)).is_err());
    }
}

#[test]
fn attribute_value_limit_is_measured_in_utf8_bytes() {
    let mut accepted = trace_context();
    accepted.attributes.push(CoreObservabilityAttribute {
        key: "diagnostic.value".to_owned(),
        value: "é".repeat(MAX_VALUE_LENGTH / 2),
        privacy: ObservabilityPrivacy::Public,
    });
    assert!(validate_trace_context(&accepted).is_ok());

    let mut rejected = trace_context();
    rejected.attributes.push(CoreObservabilityAttribute {
        key: "diagnostic.value".to_owned(),
        value: "é".repeat(MAX_VALUE_LENGTH / 2 + 1),
        privacy: ObservabilityPrivacy::Public,
    });
    assert!(validate_trace_context(&rejected).is_err());
}

#[test]
fn structured_context_has_an_aggregate_byte_limit() {
    let mut context = trace_context();
    context.attributes = (0..17)
        .map(|index| CoreObservabilityAttribute {
            key: format!("diagnostic.value.{index}"),
            value: "x".repeat(MAX_VALUE_LENGTH),
            privacy: ObservabilityPrivacy::Public,
        })
        .collect();

    assert!(validate_trace_context(&context).is_err());
}

#[test]
fn locator_keys_cannot_downgrade_their_sensitive_privacy_floor() {
    for key in [
        "source.name",
        "source_path",
        "source-name",
        "sourceName",
        "repository.url",
        "repositoryURL",
        "file.locator",
    ] {
        let mut context = trace_context();
        context.attributes.push(CoreObservabilityAttribute {
            key: key.to_owned(),
            value: "private-client.pdf".to_owned(),
            privacy: ObservabilityPrivacy::Public,
        });
        assert!(validate_trace_context(&context).is_err(), "{key}");
    }
}

#[test]
fn public_embedded_paths_are_rejected() {
    for value in [
        "source is /Users/person/private.txt",
        "source is /用户/机密.txt",
        "来源：/用户/机密.txt",
        "source\u{00a0}/Users/person/private.txt",
        "来源/用户/机密.txt",
        "source=/.ssh/id_ed25519",
        "source=\"/tmp/private.txt\"",
        "source is C:\\Users\\person\\private.txt",
        "source is file:///Users/person/private.txt",
        "path:/Users/person/private.txt",
        "source=\\\\server\\share\\private.txt",
    ] {
        let mut event = event();
        event.attributes.push(CoreObservabilityAttribute {
            key: "diagnostic.value".to_owned(),
            value: value.to_owned(),
            privacy: ObservabilityPrivacy::Public,
        });
        assert!(sanitize_event(event, &config(true)).is_err(), "{value}");
    }
}

#[test]
fn public_filename_tokens_are_rejected_under_generic_fields() {
    for value in [
        "private-client.pdf",
        "source is private-client.pdf",
        "来源：机密.txt",
        "source\u{00a0}private-client.pdf",
        "config .env",
        "report。pdf",
    ] {
        let mut event = event();
        event.attributes.push(CoreObservabilityAttribute {
            key: "diagnostic.value".to_owned(),
            value: value.to_owned(),
            privacy: ObservabilityPrivacy::Public,
        });
        assert!(sanitize_event(event, &config(true)).is_err(), "{value}");
    }

    for value in ["completed", "version 1.2.3", "42", "no-file-value"] {
        let mut event = event();
        event.attributes.push(CoreObservabilityAttribute {
            key: "diagnostic.value".to_owned(),
            value: value.to_owned(),
            privacy: ObservabilityPrivacy::Public,
        });
        assert!(sanitize_event(event, &config(true)).is_ok(), "{value}");
    }
}

#[test]
fn credential_like_attribute_keys_are_rejected_without_secret_markers_in_the_value() {
    for key in [
        "api_key",
        "accessToken",
        "client-secret",
        "authorization",
        "accessＴoken",
    ] {
        let mut event = event();
        event.attributes.push(CoreObservabilityAttribute {
            key: key.to_owned(),
            value: "opaque-value".to_owned(),
            privacy: ObservabilityPrivacy::Public,
        });
        assert!(sanitize_event(event, &config(true)).is_err(), "{key}");
    }
}

#[test]
fn compact_and_compatibility_credential_text_is_rejected() {
    for value in [
        "apiKey: opaque",
        "accessToken opaque",
        "refreshToken=opaque",
        "clientSecret: opaque",
        "privateKey=opaque",
        "accessＴoken＝opaque",
    ] {
        let mut candidate = event();
        candidate.message = Some(value.to_owned());
        assert!(sanitize_event(candidate, &config(true)).is_err(), "{value}");
    }
}

#[test]
fn build_platform_and_architecture_require_controlled_lowercase_identifiers() {
    for value in ["MacOS", "ARM64", "mac.os", "架构"] {
        let mut candidate = event();
        candidate.build_context.platform = value.to_owned();
        assert!(
            sanitize_event(candidate, &config(false)).is_err(),
            "{value}"
        );
    }
}

#[test]
fn invalid_config_session_id_uses_the_config_error_contract() {
    let mut candidate = config(false);
    candidate.session_id = "not-a-uuid".to_owned();

    assert!(matches!(
        validate_config(&candidate),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn retry_context_requires_a_distinct_current_operation() {
    let operation_id = uuid::Uuid::new_v4().to_string();
    let mut context = trace_context();
    context.operation_id = None;
    context.retry_of_operation_id = Some(uuid::Uuid::new_v4().to_string());
    assert!(validate_trace_context(&context).is_err());

    context.operation_id = Some(operation_id.clone());
    context.retry_of_operation_id = Some(operation_id);
    assert!(validate_trace_context(&context).is_err());

    context.operation_id = Some(uuid::Uuid::new_v4().to_string());
    context.retry_of_operation_id = Some(uuid::Uuid::new_v4().to_string());
    assert!(validate_trace_context(&context).is_ok());
}

#[test]
fn prohibited_secret_markers_are_rejected_before_value_truncation() {
    let mut event = event();
    event.message = Some(format!(
        "{}Authorization: Bearer should-never-leave-core",
        "x".repeat(MAX_VALUE_LENGTH + 1)
    ));

    assert!(sanitize_event(event, &config(true)).is_err());
}

#[test]
fn public_paths_are_rejected_but_sensitive_paths_follow_explicit_config() {
    let mut public_event = event();
    public_event.attributes.push(CoreObservabilityAttribute {
        key: "source.path".to_owned(),
        value: "/Users/person/private.txt".to_owned(),
        privacy: ObservabilityPrivacy::Public,
    });
    assert!(sanitize_event(public_event, &config(true)).is_err());

    let mut sensitive_event = event();
    sensitive_event.attributes.push(CoreObservabilityAttribute {
        key: "source.path".to_owned(),
        value: "/Users/person/private.txt".to_owned(),
        privacy: ObservabilityPrivacy::Sensitive,
    });
    let redacted = sanitize_event(sensitive_event.clone(), &config(false)).unwrap();
    assert_eq!(redacted.attributes[0].value, "[REDACTED]");
    let included = sanitize_event(sensitive_event, &config(true)).unwrap();
    assert_eq!(included.attributes[0].value, "/Users/person/private.txt");
}

#[test]
fn technical_error_detail_is_always_classified_sensitive() {
    let mut event = event();
    event.error = Some(CoreObservabilityError {
        code: "io.failure".to_owned(),
        kind: Some("io".to_owned()),
        technical_details: Some("private implementation detail".to_owned()),
    });

    let redacted = sanitize_event(event.clone(), &config(false)).unwrap();
    assert_eq!(
        redacted.error.and_then(|error| error.technical_details),
        Some("[REDACTED]".to_owned())
    );
    assert_eq!(redacted.privacy_level, ObservabilityPrivacy::Sensitive);

    let included = sanitize_event(event, &config(true)).unwrap();
    assert_eq!(included.privacy_level, ObservabilityPrivacy::Sensitive);
}

#[test]
fn untrusted_thread_metadata_is_removed() {
    let mut event = event();
    event.thread_name = Some("/Users/person/private.txt".to_owned());

    let sanitized = sanitize_event(event, &config(false)).unwrap();

    assert_eq!(sanitized.thread_name, None);
}

#[test]
fn credential_like_optional_metadata_is_removed() {
    let mut candidate = event();
    candidate.target = Some("accessToken".to_owned());
    candidate.thread_name = Some("clientSecret".to_owned());

    let sanitized = sanitize_event(candidate, &config(false)).unwrap();

    assert_eq!(sanitized.target, None);
    assert_eq!(sanitized.thread_name, None);
}

fn config(include_sensitive: bool) -> ObservabilityConfig {
    ObservabilityConfig {
        session_id: uuid::Uuid::new_v4().to_string(),
        mode: ObservabilityMode::Developer,
        minimum_severity: ObservabilitySeverity::Trace,
        queue_capacity: 64,
        include_sensitive,
    }
}

fn event() -> CoreObservabilityEvent {
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
        action_id: "repository.import.confirmed".to_owned(),
        component_id: "core.storage.import".to_owned(),
        layer: ObservabilityLayer::Core,
        phase: "test".to_owned(),
        severity: ObservabilitySeverity::Info,
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

fn trace_context() -> CoreTraceContext {
    CoreTraceContext {
        session_id: uuid::Uuid::new_v4().to_string(),
        trace_id: uuid::Uuid::new_v4().to_string(),
        parent_span_id: None,
        incident_id: None,
        operation_id: Some(uuid::Uuid::new_v4().to_string()),
        retry_of_operation_id: None,
        action_id: "repository.import.confirmed".to_owned(),
        component_id: "core.storage.import".to_owned(),
        resource_refs: Vec::new(),
        attributes: Vec::new(),
    }
}

fn resource(alias: &str) -> CoreObservabilityResourceRef {
    CoreObservabilityResourceRef {
        resource_id: uuid::Uuid::new_v4().to_string(),
        alias: alias.to_owned(),
        extension: Some("pdf".to_owned()),
        size_bucket: Some("lt_1mb".to_owned()),
        storage_mode: Some("copied".to_owned()),
    }
}
