use super::*;

#[test]
fn unknown_observability_attribute_prefix_is_classified_prohibited() {
    let (key, privacy) = classified_attribute("obs_unclassified_name".to_owned());

    assert_eq!(key, "obs_unclassified_name");
    assert_eq!(privacy, ObservabilityPrivacy::Prohibited);
}

#[test]
fn explicit_observability_attribute_prefixes_preserve_their_privacy() {
    for (raw, expected_key, expected_privacy) in [
        ("obs_public_reason", "reason", ObservabilityPrivacy::Public),
        (
            "obs_pseudonymous_alias",
            "alias",
            ObservabilityPrivacy::Pseudonymous,
        ),
        (
            "obs_sensitive_source_name",
            "source_name",
            ObservabilityPrivacy::Sensitive,
        ),
        (
            "obs_prohibited_payload",
            "payload",
            ObservabilityPrivacy::Prohibited,
        ),
    ] {
        let (key, privacy) = classified_attribute(raw.to_owned());
        assert_eq!(key, expected_key);
        assert_eq!(privacy, expected_privacy);
    }
}

#[test]
fn repeated_span_attribute_records_replace_by_key() {
    let mut state = SpanState {
        trace_id: uuid::Uuid::new_v4().to_string(),
        span_id: uuid::Uuid::new_v4().to_string(),
        parent_span_id: None,
        incident_id: None,
        operation_id: None,
        retry_of_operation_id: None,
        action_id: "core.tracing.span".to_owned(),
        component_id: "core.observability.runtime".to_owned(),
        attributes: vec![CoreObservabilityAttribute {
            key: "progress".to_owned(),
            value: "1".to_owned(),
            privacy: ObservabilityPrivacy::Public,
        }],
        severity: ObservabilitySeverity::Info,
        close_outcome: ObservabilityOutcome::Succeeded,
        target: "area_matrix_core.observability.test".to_owned(),
        started: Instant::now(),
    };
    let mut visitor = SafeFieldVisitor::default();
    visitor
        .fields
        .insert("obs_public_progress".to_owned(), "2".to_owned());

    state.record(&mut visitor);

    assert_eq!(state.attributes.len(), 1);
    assert_eq!(state.attributes[0].value, "2");
}
