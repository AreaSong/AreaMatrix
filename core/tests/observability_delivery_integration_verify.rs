use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use area_matrix_core::{
    flush_observability, get_observability_health, import_file_observed, init_logging, init_repo,
    initialize_observability, update_observability_config, CoreError, CoreObservabilityAttribute,
    CoreObservabilityResourceRef, CoreTraceContext, DuplicateStrategy, ImportDestination,
    ImportOptions, ObservabilityConfig, ObservabilityMode, ObservabilityPrivacy,
    ObservabilitySeverity, OverviewOutput, RepoInitMode, RepoInitOptions, RepositoryLocalePolicy,
    StorageMode,
};

#[path = "support/observability_delivery.rs"]
mod delivery_support;

use delivery_support::{
    assert_span_tree, release_first_callback, wait_for_completed_callbacks,
    wait_for_first_callback, wait_for_sink_drop, CountingLegacySink, DropTrackingSink, PanicSink,
    RecordingSink, SinkState,
};

#[test]
fn delivery_preserves_fifo_and_isolates_authorization_and_callback_failures() {
    let session_id = uuid::Uuid::new_v4().to_string();
    let state = assert_bounded_fifo_delivery(&session_id);
    assert_tracing_span_delivery(&state);
    assert_source_redaction_is_fail_closed(&state);
    assert_sensitive_event_does_not_cross_authorization_generation(&session_id);
    assert_callback_deadline_and_replacement_budget(&session_id);
    assert_callback_panic_isolated_and_reconnects(&session_id);
    assert_legacy_callback_reconnects();
}

fn assert_bounded_fifo_delivery(session_id: &str) -> Arc<SinkState> {
    let state = Arc::new(SinkState::default());
    state.block_first.store(true, Ordering::Release);
    initialize_observability(
        config(session_id),
        Box::new(RecordingSink(Arc::clone(&state))),
    )
    .unwrap();
    assert!(update_observability_config(config(&uuid::Uuid::new_v4().to_string())).is_err());
    block_delivery_and_fill_queue(&state);
    assert_queue_delivery(&state, session_id);
    state
}

fn block_delivery_and_fill_queue(state: &SinkState) {
    tracing::info!(
        action_id = "observability.runtime.initialization",
        component_id = "core.observability.runtime",
        phase = "started",
        outcome = "started"
    );
    wait_for_first_callback(state);

    for index in 0..64_u64 {
        tracing::trace!(
            action_id = "core.tracing.event",
            component_id = "core.observability.runtime",
            phase = "queued",
            outcome = "none",
            obs_public_index = index
        );
    }
    tracing::error!(
        action_id = "core.tracing.span",
        component_id = "core.observability.runtime",
        phase = "queued",
        outcome = "failed"
    );
    let saturated = get_observability_health();
    assert_eq!(saturated.queue_depth, saturated.queue_capacity);
    assert!(saturated.dropped_trace >= 1);
    assert_eq!(saturated.dropped_error, 0);
    release_first_callback(state);
    flush_observability(5_000).unwrap();
}

fn assert_queue_delivery(state: &SinkState, session_id: &str) {
    let events = state.events.lock().unwrap();
    assert_eq!(events[0].session_id, session_id);
    assert_eq!(events[1].action_id, "core.tracing.event");
    let error_index = events
        .iter()
        .position(|event| event.action_id == "core.tracing.span")
        .expect("the admitted error is delivered");
    let last_trace_index = events
        .iter()
        .rposition(|event| event.action_id == "core.tracing.event")
        .expect("surviving trace events are delivered");
    assert!(last_trace_index < error_index);
    assert!(events
        .windows(2)
        .all(|pair| pair[0].sequence_number < pair[1].sequence_number));
    assert!(events.iter().all(|event| event.session_id == session_id));
    let drop_summary = events
        .iter()
        .find(|event| event.action_id == "observability.events_dropped")
        .expect("capacity recovery emits one aggregate drop summary");
    assert!(drop_summary
        .attributes
        .iter()
        .any(|attribute| attribute.key == "dropped.trace" && attribute.value != "0"));
}

fn assert_tracing_span_delivery(state: &SinkState) {
    let span_trace_id = uuid::Uuid::new_v4().to_string();
    let span_operation_id = uuid::Uuid::new_v4().to_string();
    {
        let root = tracing::info_span!(
            "observability_root",
            trace_id = span_trace_id.as_str(),
            operation_id = span_operation_id.as_str(),
            action_id = "repository.import.validation",
            component_id = "core.storage.import",
            outcome = "succeeded",
            obs_sensitive_source_name = "private.txt"
        );
        let _root_guard = root.enter();
        let child = tracing::debug_span!(
            "observability_child",
            action_id = "repository.import.staging",
            component_id = "core.storage.import"
        );
        let _child_guard = child.enter();
        tracing::info!(
            action_id = "repository.import.destination",
            component_id = "core.storage.import",
            phase = "event",
            outcome = "succeeded"
        );
    }
    flush_observability(5_000).unwrap();
    assert_span_tree(state, &span_trace_id, &span_operation_id);
}

fn assert_source_redaction_is_fail_closed(state: &SinkState) {
    let rejected_before = get_observability_health().redaction_rejected;
    tracing::warn!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "redaction_rejection",
        outcome = "degraded",
        obs_public_hostile = "Authorization: Bearer should-never-reach-a-sink"
    );
    let redaction_health = flush_observability(5_000).unwrap();
    assert_eq!(redaction_health.redaction_rejected, rejected_before + 1);
    assert_eq!(
        redaction_health.degraded_reason.as_deref(),
        Some("source-redaction-rejected-event")
    );

    let rejected_before = redaction_health.redaction_rejected;
    tracing::warn!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "unknown_privacy_prefix",
        outcome = "degraded",
        obs_unclassified_name = "benign.txt"
    );
    let unknown_privacy_health = flush_observability(5_000).unwrap();
    assert_eq!(
        unknown_privacy_health.redaction_rejected,
        rejected_before + 1
    );
    assert!(state
        .events
        .lock()
        .unwrap()
        .iter()
        .all(|event| event.phase != "unknown_privacy_prefix"));
}

fn assert_callback_deadline_and_replacement_budget(session_id: &str) {
    let dropped_error_before = get_observability_health().dropped_error;
    let slow_sink = Arc::new(SinkState::default());
    slow_sink.block_first.store(true, Ordering::Release);
    let (tracking_sink, dropped) = DropTrackingSink::new(Arc::clone(&slow_sink));
    initialize_observability(config(session_id), Box::new(tracking_sink)).unwrap();
    tracing::error!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "callback_deadline",
        outcome = "failed"
    );
    wait_for_first_callback(&slow_sink);
    let deadline_health = flush_observability(1).unwrap();
    assert!(deadline_health.degraded);
    assert_eq!(
        deadline_health.degraded_reason.as_deref(),
        Some("flush-deadline-exceeded")
    );
    let health = flush_observability(5_000).unwrap();
    assert!(!health.callback_connected);
    assert_eq!(
        health.degraded_reason.as_deref(),
        Some("callback-deadline-exceeded")
    );
    assert_eq!(health.dropped_error, dropped_error_before);
    release_first_callback(&slow_sink);
    wait_for_completed_callbacks(&slow_sink, 1);
    wait_for_sink_drop(&dropped);
    assert_callback_replacement_budget_is_bounded(session_id);
}

fn assert_callback_panic_isolated_and_reconnects(session_id: &str) {
    let dropped_error_before = get_observability_health().dropped_error;
    initialize_observability(config(session_id), Box::new(PanicSink)).unwrap();
    tracing::error!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "callback_panic",
        outcome = "failed"
    );
    assert_import_succeeds_while_callback_panics(session_id);
    let health = flush_observability(5_000).unwrap();
    assert!(health.degraded);
    assert_eq!(health.degraded_reason.as_deref(), Some("callback-panicked"));
    assert!(!health.callback_connected);
    assert!(health.dropped_error > dropped_error_before);

    let reconnected = Arc::new(SinkState::default());
    initialize_observability(
        config(session_id),
        Box::new(RecordingSink(Arc::clone(&reconnected))),
    )
    .unwrap();
    tracing::info!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "callback_reconnected",
        outcome = "succeeded"
    );
    let health = flush_observability(5_000).unwrap();
    assert!(health.callback_connected);
    assert!(reconnected
        .events
        .lock()
        .unwrap()
        .iter()
        .any(|event| event.phase == "callback_reconnected"));
}

fn assert_legacy_callback_reconnects() {
    let legacy_received = Arc::new(AtomicBool::new(false));
    init_logging(
        "info".to_owned(),
        Box::new(CountingLegacySink(Arc::clone(&legacy_received))),
    )
    .expect("legacy callback reconnect preserves the fixed runtime queue");
    assert_eq!(get_observability_health().queue_capacity, 64);
    tracing::info!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "legacy_reconnected",
        outcome = "succeeded"
    );
    flush_observability(5_000).unwrap();
    assert!(legacy_received.load(Ordering::Acquire));
}

fn assert_callback_replacement_budget_is_bounded(session_id: &str) {
    let mut timed_out_sinks = Vec::new();
    for _ in 0..4 {
        let sink = Arc::new(SinkState::default());
        sink.block_first.store(true, Ordering::Release);
        initialize_observability(
            config(session_id),
            Box::new(RecordingSink(Arc::clone(&sink))),
        )
        .unwrap();
        tracing::error!(
            action_id = "core.tracing.event",
            component_id = "core.observability.runtime",
            phase = "callback_deadline",
            outcome = "failed"
        );
        wait_for_first_callback(&sink);
        let health = flush_observability(5_000).unwrap();
        assert!(!health.callback_connected);
        timed_out_sinks.push(sink);
    }

    let rejected = initialize_observability(
        config(session_id),
        Box::new(RecordingSink(Arc::new(SinkState::default()))),
    )
    .unwrap_err();
    assert!(matches!(rejected, CoreError::Config { .. }));

    for sink in timed_out_sinks {
        release_first_callback(&sink);
        wait_for_completed_callbacks(&sink, 1);
    }
    initialize_observability(
        config(session_id),
        Box::new(RecordingSink(Arc::new(SinkState::default()))),
    )
    .expect("completed timeout callbacks release the replacement budget");
}

fn assert_sensitive_event_does_not_cross_authorization_generation(session_id: &str) {
    let old_sink = queue_sensitive_event_behind_blocked_sink(session_id);
    let new_sink = replace_sink_and_revoke_sensitive_authorization(session_id, &old_sink);
    assert_sensitive_event_is_redacted_after_reconfiguration(&old_sink, &new_sink);
}

fn queue_sensitive_event_behind_blocked_sink(session_id: &str) -> Arc<SinkState> {
    let old_sink = Arc::new(SinkState::default());
    old_sink.block_first.store(true, Ordering::Release);
    initialize_observability(
        sensitive_config(session_id),
        Box::new(RecordingSink(Arc::clone(&old_sink))),
    )
    .unwrap();
    tracing::info!(
        action_id = "observability.runtime.initialization",
        component_id = "core.observability.runtime",
        phase = "started",
        outcome = "started"
    );
    wait_for_first_callback(&old_sink);
    tracing::info!(
        action_id = "core.tracing.event",
        component_id = "core.observability.runtime",
        phase = "authorization_sensitive",
        outcome = "succeeded",
        obs_sensitive_source_name = "private-authorization-boundary.txt"
    );
    old_sink
}

fn replace_sink_and_revoke_sensitive_authorization(
    session_id: &str,
    old_sink: &SinkState,
) -> Arc<SinkState> {
    let new_sink = Arc::new(SinkState::default());
    initialize_observability(
        sensitive_config(session_id),
        Box::new(RecordingSink(Arc::clone(&new_sink))),
    )
    .unwrap();
    update_observability_config(config(session_id)).unwrap();
    release_first_callback(old_sink);
    flush_observability(5_000).unwrap();
    new_sink
}

fn assert_sensitive_event_is_redacted_after_reconfiguration(
    old_sink: &SinkState,
    new_sink: &SinkState,
) {
    assert!(old_sink
        .events
        .lock()
        .unwrap()
        .iter()
        .all(|event| event.phase != "authorization_sensitive"));
    let events = new_sink.events.lock().unwrap();
    let sensitive = events
        .iter()
        .find(|event| event.phase == "authorization_sensitive")
        .expect("queued event is delivered to the replacement sink");
    assert_eq!(sensitive.privacy_level, ObservabilityPrivacy::Sensitive);
    assert_eq!(sensitive.attributes[0].value, "[REDACTED]");
    assert!(events.iter().all(|event| {
        event
            .attributes
            .iter()
            .all(|attribute| attribute.value != "private-authorization-boundary.txt")
    }));
}

fn config(session_id: &str) -> ObservabilityConfig {
    ObservabilityConfig {
        session_id: session_id.to_owned(),
        mode: ObservabilityMode::Developer,
        minimum_severity: ObservabilitySeverity::Trace,
        queue_capacity: 64,
        include_sensitive: false,
    }
}

fn sensitive_config(session_id: &str) -> ObservabilityConfig {
    ObservabilityConfig {
        include_sensitive: true,
        ..config(session_id)
    }
}

fn assert_import_succeeds_while_callback_panics(session_id: &str) {
    let repo = tempfile::tempdir().unwrap();
    init_repo(
        repo.path().to_string_lossy().into_owned(),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .unwrap();
    let source_root = tempfile::tempdir().unwrap();
    let source = source_root.path().join("callback-failure.txt");
    std::fs::write(&source, b"business state must commit").unwrap();
    let entry = import_file_observed(
        repo.path().to_string_lossy().into_owned(),
        source.to_string_lossy().into_owned(),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::AutoClassify,
            target_directory: None,
            override_category: Some("inbox".to_owned()),
            override_filename: None,
            duplicate_strategy: DuplicateStrategy::Skip,
            content_locale: area_matrix_core::ContentLocale::En,
        },
        trace_context(session_id),
    )
    .expect("callback failures never change the import result");
    assert!(source.exists());
    assert_eq!(
        std::fs::read(repo.path().join(entry.path)).unwrap(),
        b"business state must commit"
    );
}

fn trace_context(session_id: &str) -> CoreTraceContext {
    CoreTraceContext {
        session_id: session_id.to_owned(),
        trace_id: uuid::Uuid::new_v4().to_string(),
        parent_span_id: None,
        incident_id: None,
        operation_id: Some(uuid::Uuid::new_v4().to_string()),
        retry_of_operation_id: None,
        action_id: "repository.import.confirmed".to_owned(),
        component_id: "core.storage.import".to_owned(),
        resource_refs: vec![CoreObservabilityResourceRef {
            resource_id: uuid::Uuid::new_v4().to_string(),
            alias: "file.0123456789abcdef01234567".to_owned(),
            extension: Some("txt".to_owned()),
            size_bucket: Some("lt_1mb".to_owned()),
            storage_mode: Some("copied".to_owned()),
        }],
        attributes: vec![CoreObservabilityAttribute {
            key: "source.name".to_owned(),
            value: "callback-failure.txt".to_owned(),
            privacy: ObservabilityPrivacy::Sensitive,
        }],
    }
}
