use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use area_matrix_core::{
    flush_observability, import_file_observed, import_file_with_result_observed, init_repo,
    CoreError, CoreObservabilityEvent, CoreTraceContext, DuplicateStrategy, FileEntry,
    ImportOptions, ObservabilityConfig, ObservabilityMode, ObservabilityOutcome,
    ObservabilityPrivacy, ObservabilitySeverity, OverviewOutput, RepoInitMode, RepoInitOptions,
    RepositoryLocalePolicy, StorageMode,
};

mod support;

use support::system_trash_home::with_test_system_trash;

#[path = "support/import_observability.rs"]
mod import_support;

use import_support::{
    assert_child_identity, assert_schema_two_build_context_round_trip, import_mutation_snapshot,
    import_options, root_started, trace_context, RecordingSink,
};

struct ImportFixture {
    repo: tempfile::TempDir,
    _source_root: tempfile::TempDir,
    source: PathBuf,
    options: ImportOptions,
}

#[test]
fn observed_import_validates_context_before_mutation_and_preserves_trace_identity() {
    let fixture = primary_import_fixture();
    assert_invalid_trace_context_is_side_effect_free(&fixture);

    let events = Arc::new(Mutex::new(Vec::new()));
    let context = trace_context();
    initialize_test_observability(&context, &events);
    assert_session_mismatch_is_side_effect_free(&fixture, &context);
    assert_unregistered_catalog_ids_are_side_effect_free(
        fixture.repo.path(),
        &fixture.source,
        &fixture.options,
        &context,
        &events,
    );
    execute_primary_import(&fixture, &context);
    assert_primary_import_trace(&events, &context);

    assert_duplicate_trace_continuity(fixture.repo.path(), &events, &context.session_id);
    assert_trash_fallback_trace_continuity(fixture.repo.path(), &events, &context.session_id);

    #[cfg(unix)]
    assert_retained_move_roots_are_degraded(fixture.repo.path(), &events, &context.session_id);
}

fn primary_import_fixture() -> ImportFixture {
    let repo = tempfile::tempdir().unwrap();
    initialize_test_repo(repo.path());
    let source_root = tempfile::tempdir().unwrap();
    let source = source_root.path().join("private-name.txt");
    fs::write(&source, b"private body").unwrap();
    let mut options = import_options(StorageMode::Copied);
    options.duplicate_strategy = DuplicateStrategy::Skip;
    ImportFixture {
        repo,
        _source_root: source_root,
        source,
        options,
    }
}

fn initialize_test_repo(repo: &Path) {
    init_repo(
        repo.to_string_lossy().into_owned(),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .unwrap();
}

fn assert_invalid_trace_context_is_side_effect_free(fixture: &ImportFixture) {
    let mut invalid = trace_context();
    invalid.trace_id = "invalid".to_owned();
    assert!(import_file_observed(
        fixture.repo.path().to_string_lossy().into_owned(),
        fixture.source.to_string_lossy().into_owned(),
        fixture.options.clone(),
        invalid,
    )
    .is_err());
    assert!(fixture.source.exists());
    assert!(!fixture.repo.path().join("inbox/private-name.txt").exists());
}

fn initialize_test_observability(
    context: &CoreTraceContext,
    events: &Arc<Mutex<Vec<CoreObservabilityEvent>>>,
) {
    area_matrix_core::initialize_observability(
        ObservabilityConfig {
            session_id: context.session_id.clone(),
            mode: ObservabilityMode::Developer,
            minimum_severity: ObservabilitySeverity::Trace,
            queue_capacity: 64,
            include_sensitive: false,
        },
        Box::new(RecordingSink(Arc::clone(events))),
    )
    .unwrap();
}

fn assert_session_mismatch_is_side_effect_free(
    fixture: &ImportFixture,
    context: &CoreTraceContext,
) {
    let source_root = tempfile::tempdir().unwrap();
    let session_mismatch_source = source_root.path().join("session-mismatch.txt");
    fs::write(&session_mismatch_source, b"must remain untouched").unwrap();
    let mut session_mismatch = context.clone();
    session_mismatch.session_id = uuid::Uuid::new_v4().to_string();
    assert!(import_file_observed(
        fixture.repo.path().to_string_lossy().into_owned(),
        session_mismatch_source.to_string_lossy().into_owned(),
        fixture.options.clone(),
        session_mismatch,
    )
    .is_err());
    assert!(session_mismatch_source.exists());
    assert!(!fixture
        .repo
        .path()
        .join("inbox/session-mismatch.txt")
        .exists());
}

fn execute_primary_import(fixture: &ImportFixture, context: &CoreTraceContext) {
    import_file_observed(
        fixture.repo.path().to_string_lossy().into_owned(),
        fixture.source.to_string_lossy().into_owned(),
        fixture.options.clone(),
        context.clone(),
    )
    .unwrap();
    flush_observability(5_000).unwrap();
}

fn assert_primary_import_trace(
    events: &Arc<Mutex<Vec<CoreObservabilityEvent>>>,
    context: &CoreTraceContext,
) {
    let captured_events = events.lock().unwrap();
    let root_span_id = assert_root_trace_identity(&captured_events, context);
    let expected_stages = [
        "repository.import.validation",
        "repository.import.staging",
        "repository.import.fingerprint",
        "repository.import.duplicate_resolution",
        "repository.import.destination",
        "repository.import.staging_db_row",
        "repository.import.filesystem_commit",
        "repository.import.db_promotion",
        "repository.import.overview",
    ];
    for action_id in expected_stages {
        assert_stage_trace_identity(&captured_events, action_id, root_span_id, context);
    }
    assert_copy_source_removal(&captured_events, root_span_id, context);
    assert_schema_two_build_context_round_trip(&captured_events);
    let serialized = serde_json::to_string(&*captured_events).unwrap();
    assert!(!serialized.contains("private-name.txt"));
    assert!(!serialized.contains("private body"));
}

fn assert_root_trace_identity<'a>(
    events: &'a [CoreObservabilityEvent],
    context: &CoreTraceContext,
) -> &'a str {
    let operation_events = events
        .iter()
        .filter(|event| event.action_id == context.action_id)
        .collect::<Vec<_>>();
    assert_eq!(operation_events.len(), 2);
    assert!(operation_events.iter().all(|event| {
        event.trace_id == context.trace_id && event.span_id == operation_events[0].span_id
    }));
    operation_events[0].span_id.as_str()
}

fn assert_stage_trace_identity(
    events: &[CoreObservabilityEvent],
    action_id: &str,
    root_span_id: &str,
    context: &CoreTraceContext,
) {
    let stage_events = events
        .iter()
        .filter(|event| event.action_id == action_id)
        .collect::<Vec<_>>();
    assert_eq!(stage_events.len(), 2, "missing stage {action_id}");
    assert_eq!(stage_events[0].phase, "started");
    assert_eq!(stage_events[1].phase, "completed");
    assert!(stage_events.iter().all(|event| {
        event.trace_id == context.trace_id
            && event.operation_id == context.operation_id
            && event.retry_of_operation_id == context.retry_of_operation_id
            && event.incident_id == context.incident_id
            && event.parent_span_id.as_deref() == Some(root_span_id)
            && event.span_id == stage_events[0].span_id
            && event.resource_refs == context.resource_refs
            && event.attributes[0].value == "[REDACTED]"
            && event.privacy_level == ObservabilityPrivacy::Sensitive
    }));
}

fn assert_copy_source_removal(
    events: &[CoreObservabilityEvent],
    root_span_id: &str,
    context: &CoreTraceContext,
) {
    let source_removal = events
        .iter()
        .find(|event| event.action_id == "repository.import.source_removal")
        .expect("copy import reports source removal as skipped");
    assert_eq!(source_removal.phase, "skipped");
    assert_eq!(source_removal.parent_span_id.as_deref(), Some(root_span_id));
    assert_eq!(source_removal.resource_refs, context.resource_refs);
}

#[cfg(unix)]
fn assert_retained_move_roots_are_degraded(
    repo: &Path,
    events: &Arc<Mutex<Vec<CoreObservabilityEvent>>>,
    session_id: &str,
) {
    use std::os::unix::fs::PermissionsExt;

    for rich_result in [false, true] {
        let source_root = tempfile::tempdir().unwrap();
        let source_name = if rich_result {
            "retained-result.txt"
        } else {
            "retained-entry.txt"
        };
        let source = source_root.path().join(source_name);
        fs::write(&source, b"retained bytes").unwrap();
        let original_permissions = fs::metadata(source_root.path()).unwrap().permissions();
        let mut blocked_permissions = original_permissions.clone();
        blocked_permissions.set_mode(0o500);
        fs::set_permissions(source_root.path(), blocked_permissions).unwrap();

        let mut context = trace_context();
        context.session_id = session_id.to_owned();
        context.action_id = "repository.import.confirmed".to_owned();
        context.resource_refs[0].storage_mode = Some("moved".to_owned());
        context.attributes[0].value = source_name.to_owned();
        let call_result = retained_move_call(repo, &source, &context, rich_result);
        fs::set_permissions(source_root.path(), original_permissions).unwrap();
        let entry = call_result.expect("move remains committed when source removal fails");
        assert!(source.exists());
        assert!(repo.join(entry.path).exists());
        flush_observability(5_000).unwrap();

        let events = events.lock().unwrap();
        let terminal = events
            .iter()
            .find(|event| {
                event.trace_id == context.trace_id
                    && event.action_id == context.action_id
                    && event.phase == "completed"
            })
            .expect("observed move emits a root terminal event");
        assert_eq!(
            terminal.outcome,
            area_matrix_core::ObservabilityOutcome::Degraded
        );
        assert_eq!(terminal.severity, ObservabilitySeverity::Warn);
    }
}

fn assert_unregistered_catalog_ids_are_side_effect_free(
    repo: &Path,
    source: &Path,
    options: &ImportOptions,
    context: &CoreTraceContext,
    events: &Arc<Mutex<Vec<CoreObservabilityEvent>>>,
) {
    let event_count = events.lock().unwrap().len();
    let mutation_snapshot = import_mutation_snapshot(repo);
    let mut unknown_action = context.clone();
    unknown_action.action_id = "repository.import.unregistered".to_owned();
    assert!(matches!(
        import_file_observed(
            repo.to_string_lossy().into_owned(),
            source.to_string_lossy().into_owned(),
            options.clone(),
            unknown_action,
        ),
        Err(CoreError::Validation { .. })
    ));
    let mut unknown_component = context.clone();
    unknown_component.component_id = "core.storage.unregistered".to_owned();
    assert!(matches!(
        import_file_observed(
            repo.to_string_lossy().into_owned(),
            source.to_string_lossy().into_owned(),
            options.clone(),
            unknown_component,
        ),
        Err(CoreError::Validation { .. })
    ));
    assert!(source.exists());
    assert!(!repo.join("inbox/private-name.txt").exists());
    assert_eq!(events.lock().unwrap().len(), event_count);
    assert_eq!(import_mutation_snapshot(repo), mutation_snapshot);
}

fn assert_duplicate_trace_continuity(
    repo: &Path,
    events: &Arc<Mutex<Vec<CoreObservabilityEvent>>>,
    session_id: &str,
) {
    let source_root = tempfile::tempdir().unwrap();
    let source = source_root.path().join("duplicate-private.txt");
    fs::write(&source, b"private body").unwrap();
    let mut context = trace_context();
    context.session_id = session_id.to_owned();
    context.attributes[0].value = "duplicate-private.txt".to_owned();

    let mut options = import_options(StorageMode::Copied);
    options.duplicate_strategy = DuplicateStrategy::Skip;
    let result = import_file_observed(
        repo.to_string_lossy().into_owned(),
        source.to_string_lossy().into_owned(),
        options,
        context.clone(),
    );
    assert!(matches!(result, Err(CoreError::DuplicateFile { .. })));
    assert!(source.exists());
    assert!(!repo.join("inbox/duplicate-private.txt").exists());
    flush_observability(5_000).unwrap();

    let events = events.lock().unwrap();
    let root = root_started(&events, &context);
    let duplicate = events
        .iter()
        .find(|event| {
            event.trace_id == context.trace_id
                && event.action_id == "repository.import.duplicate.detected"
        })
        .expect("duplicate fallback event remains in the operation trace");
    assert_child_identity(duplicate, root, &context);
    assert_eq!(duplicate.outcome, ObservabilityOutcome::Failed);
}

fn assert_trash_fallback_trace_continuity(
    repo: &Path,
    events: &Arc<Mutex<Vec<CoreObservabilityEvent>>>,
    session_id: &str,
) {
    with_test_system_trash(|trash_dir| {
        import_replacement_fixture(repo, session_id, b"old bytes", DuplicateStrategy::KeepBoth);
        let (context, entry) = import_replacement_fixture(
            repo,
            session_id,
            b"new bytes",
            DuplicateStrategy::Overwrite,
        );
        flush_observability(5_000).unwrap();

        let captured = events.lock().unwrap();
        let root = root_started(&captured, &context);
        let fallback = captured
            .iter()
            .find(|event| {
                event.trace_id == context.trace_id
                    && event.action_id == "repository.file.trash.fallback"
            })
            .expect("Trash fallback remains in the replacement operation trace");
        assert_child_identity(fallback, root, &context);
        assert_eq!(fallback.outcome, ObservabilityOutcome::Degraded);
        drop(captured);

        assert_eq!(fs::read(repo.join(entry.path)).unwrap(), b"new bytes");
        let trashed = fs::read_dir(trash_dir)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect::<Vec<_>>();
        assert_eq!(trashed.len(), 1);
        assert_eq!(fs::read(&trashed[0]).unwrap(), b"old bytes");
    });
}

fn import_replacement_fixture(
    repo: &Path,
    session_id: &str,
    contents: &[u8],
    duplicate_strategy: DuplicateStrategy,
) -> (CoreTraceContext, FileEntry) {
    let source_root = tempfile::tempdir().unwrap();
    let source = source_root.path().join("replacement.txt");
    fs::write(&source, contents).unwrap();
    let mut context = trace_context();
    context.session_id = session_id.to_owned();
    context.attributes[0].value = "replacement.txt".to_owned();
    let mut options = import_options(StorageMode::Copied);
    options.duplicate_strategy = duplicate_strategy;
    let entry = import_file_observed(
        repo.to_string_lossy().into_owned(),
        source.to_string_lossy().into_owned(),
        options,
        context.clone(),
    )
    .unwrap();
    assert!(source.exists());
    (context, entry)
}

#[cfg(unix)]
fn retained_move_call(
    repo: &Path,
    source: &Path,
    context: &CoreTraceContext,
    rich_result: bool,
) -> area_matrix_core::CoreResult<area_matrix_core::FileEntry> {
    let repo_path = repo.to_string_lossy().into_owned();
    let source_path = source.to_string_lossy().into_owned();
    if rich_result {
        return import_file_with_result_observed(
            repo_path,
            source_path,
            import_options(StorageMode::Moved),
            context.clone(),
        )
        .map(|result| result.entry);
    }
    import_file_observed(
        repo_path,
        source_path,
        import_options(StorageMode::Moved),
        context.clone(),
    )
}
