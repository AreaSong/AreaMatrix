use std::{
    fs,
    path::Path,
    sync::{Arc, Mutex},
};

use area_matrix_core::{
    CoreObservabilityAttribute, CoreObservabilityEvent, CoreObservabilityResourceRef,
    CoreObservabilitySink, CoreTraceContext, DuplicateStrategy, ImportDestination, ImportOptions,
    ObservabilityPrivacy, StorageMode,
};

pub(crate) struct RecordingSink(pub(crate) Arc<Mutex<Vec<CoreObservabilityEvent>>>);

impl CoreObservabilitySink for RecordingSink {
    fn on_event(&self, event: CoreObservabilityEvent) {
        self.0.lock().unwrap().push(event);
    }
}

pub(crate) fn import_options(mode: StorageMode) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::KeepBoth,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

pub(crate) fn trace_context() -> CoreTraceContext {
    CoreTraceContext {
        session_id: uuid::Uuid::new_v4().to_string(),
        trace_id: uuid::Uuid::new_v4().to_string(),
        parent_span_id: Some(uuid::Uuid::new_v4().to_string()),
        incident_id: Some(uuid::Uuid::new_v4().to_string()),
        operation_id: Some(uuid::Uuid::new_v4().to_string()),
        retry_of_operation_id: Some(uuid::Uuid::new_v4().to_string()),
        action_id: "repository.import.confirmed".to_owned(),
        component_id: "core.storage.import".to_owned(),
        resource_refs: vec![CoreObservabilityResourceRef {
            resource_id: uuid::Uuid::new_v4().to_string(),
            alias: "file.89abcdef0123456789abcdef".to_owned(),
            extension: Some("txt".to_owned()),
            size_bucket: Some("lt_1mb".to_owned()),
            storage_mode: Some("copied".to_owned()),
        }],
        attributes: vec![CoreObservabilityAttribute {
            key: "source.name".to_owned(),
            value: "private-name.txt".to_owned(),
            privacy: ObservabilityPrivacy::Sensitive,
        }],
    }
}

pub(crate) fn import_mutation_snapshot(repo: &Path) -> (Vec<String>, i64, i64) {
    let staging_dir = repo.join(".areamatrix/staging");
    let mut staging_entries = fs::read_dir(staging_dir)
        .into_iter()
        .flatten()
        .map(|entry| {
            entry
                .expect("read staging entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect::<Vec<_>>();
    staging_entries.sort();
    let connection = rusqlite::Connection::open(repo.join(".areamatrix/index.db")).unwrap();
    let (file_rows, staging_rows) = connection
        .query_row(
            "SELECT COUNT(*), COALESCE(SUM(status = 'staging'), 0) FROM files",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    (staging_entries, file_rows, staging_rows)
}

pub(crate) fn assert_schema_two_build_context_round_trip(events: &[CoreObservabilityEvent]) {
    let loaded_context = area_matrix_core::get_observability_build_context();
    assert!(!events.is_empty());
    assert!(events
        .iter()
        .all(|event| { event.schema_version == 2 && event.build_context == loaded_context }));
    let event = events
        .iter()
        .find(|event| !event.attributes.is_empty())
        .expect("schema 2 fixture includes an event attribute");
    let encoded = serde_json::to_vec(event).unwrap();
    let object = serde_json::from_slice::<serde_json::Value>(&encoded)
        .unwrap()
        .as_object()
        .cloned()
        .expect("schema 2 event encodes as a JSON object");
    assert!(object.contains_key("privacy_level"));
    assert!(object.contains_key("phase"));
    assert!(!object.contains_key("privacy"));
    assert!(!object.contains_key("lifecycle_step"));
    let attribute = object
        .get("attributes")
        .and_then(serde_json::Value::as_array)
        .and_then(|attributes| attributes.first())
        .and_then(serde_json::Value::as_object)
        .expect("schema 2 event attribute encodes as a JSON object");
    assert!(attribute.contains_key("privacy"));
    assert!(!attribute.contains_key("privacy_level"));
    let decoded: CoreObservabilityEvent = serde_json::from_slice(&encoded).unwrap();
    assert_eq!(&decoded, event);
}

pub(crate) fn root_started<'a>(
    events: &'a [CoreObservabilityEvent],
    context: &CoreTraceContext,
) -> &'a CoreObservabilityEvent {
    events
        .iter()
        .find(|event| {
            event.trace_id == context.trace_id
                && event.action_id == context.action_id
                && event.phase == "started"
        })
        .expect("operation root started event is present")
}

pub(crate) fn assert_child_identity(
    event: &CoreObservabilityEvent,
    root: &CoreObservabilityEvent,
    context: &CoreTraceContext,
) {
    assert_eq!(event.parent_span_id.as_deref(), Some(root.span_id.as_str()));
    assert_eq!(event.operation_id, context.operation_id);
    assert_eq!(event.retry_of_operation_id, context.retry_of_operation_id);
    assert_eq!(event.incident_id, context.incident_id);
}
