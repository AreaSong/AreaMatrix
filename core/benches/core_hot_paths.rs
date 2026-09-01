use std::{
    fs,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};

use area_matrix_core::{
    flush_observability, import_file, init_repo, initialize_observability, list_files,
    list_tree_json, reindex_from_filesystem, CoreObservabilityEvent, CoreObservabilitySink,
    DuplicateStrategy, FileFilter, ImportDestination, ImportOptions, ObservabilityConfig,
    ObservabilityMode, ObservabilitySeverity, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};

const ONE_MIB: usize = 1024 * 1024;
const IMPORT_ONE_MIB_THRESHOLD_MS: u128 = 30;
const IMPORT_100_FILES_THRESHOLD_MS: u128 = 5_000;
const REINDEX_10K_FILES_THRESHOLD_MS: u128 = 30_000;
const LIST_FILES_200_THRESHOLD_US: u128 = 5_000;
const LIST_TREE_1K_THRESHOLD_MS: u128 = 30;
const OBSERVABILITY_100K_THRESHOLD_MS: u128 = 2_000;

#[test]
#[ignore = "Core hot path benchmark; run explicitly with --release --bench core_hot_paths"]
fn core_hot_path_benchmarks_emit_threshold_results() {
    core_import_one_mebibyte_copy_bench();
    core_import_one_hundred_files_bench();
    core_reindex_ten_thousand_files_bench();
    core_tree_and_list_response_bench();
    core_observability_one_hundred_thousand_events_bench();
}

struct CountingSink(Arc<AtomicU64>);

impl CoreObservabilitySink for CountingSink {
    fn on_event(&self, _event: CoreObservabilityEvent) {
        self.0.fetch_add(1, Ordering::Relaxed);
    }
}

fn core_observability_one_hundred_thousand_events_bench() {
    const EVENT_COUNT: u64 = 100_000;
    let delivered = Arc::new(AtomicU64::new(0));
    initialize_observability(
        ObservabilityConfig {
            session_id: uuid::Uuid::new_v4().to_string(),
            mode: ObservabilityMode::Developer,
            minimum_severity: ObservabilitySeverity::Trace,
            queue_capacity: 65_536,
            include_sensitive: false,
        },
        Box::new(CountingSink(Arc::clone(&delivered))),
    )
    .expect("initialize observability throughput benchmark");

    let start = Instant::now();
    for index in 0..EVENT_COUNT {
        tracing::info!(
            action_id = "core.tracing.event",
            component_id = "core.observability.runtime",
            phase = "delivery",
            outcome = "succeeded",
            obs_public_index = index
        );
    }
    let health = flush_observability(5_000).expect("flush observability throughput benchmark");
    let elapsed = start.elapsed();
    let delivered_count = delivered.load(Ordering::Acquire);
    let dropped_count = health
        .dropped_trace
        .saturating_add(health.dropped_debug)
        .saturating_add(health.dropped_info)
        .saturating_add(health.dropped_warn)
        .saturating_add(health.dropped_error);

    assert!(delivered_count > 0);
    assert_eq!(health.queue_depth, 0);
    assert_eq!(health.redaction_rejected, 0);
    assert!(health.callback_connected);
    eprintln!(
        "CORE_HOT_PATH_BENCH name=\"observability 100k delivery accounting\" submitted={EVENT_COUNT} delivered={delivered_count} dropped={dropped_count}"
    );
    report_ms(
        "observability 100k submit + delivery",
        elapsed,
        OBSERVABILITY_100K_THRESHOLD_MS,
    );
}

fn core_import_one_mebibyte_copy_bench() {
    let repo = initialized_repo(true);
    let source_root = tempfile::tempdir().expect("create source root for 1 MiB import bench");
    let source = write_source_file(source_root.path(), "invoice.pdf", ONE_MIB);

    let elapsed = measure(|| {
        import_file(
            path_string(repo.path()),
            path_string(&source),
            copied_options(Some("finance")),
        )
        .expect("import one MiB file during core hot path bench");
    });

    report_ms(
        "import_file 1 MiB copied",
        elapsed,
        IMPORT_ONE_MIB_THRESHOLD_MS,
    );
}

fn core_import_one_hundred_files_bench() {
    let repo = initialized_repo(true);
    let source_root = tempfile::tempdir().expect("create source root for batch bench");
    let sources = write_source_files(source_root.path(), 100, 4 * 1024);

    let elapsed = measure(|| {
        for source in &sources {
            import_file(
                path_string(repo.path()),
                path_string(source),
                copied_options(Some("docs")),
            )
            .expect("import batch file during core hot path bench");
        }
        let files = list_files(path_string(repo.path()), category_filter("docs", 100))
            .expect("list imported batch during core hot path bench");
        assert_eq!(files.len(), 100);
    });

    report_ms(
        "100 file copied batch import + list",
        elapsed,
        IMPORT_100_FILES_THRESHOLD_MS,
    );
}

fn core_reindex_ten_thousand_files_bench() {
    let repo = initialized_repo(false);
    write_repository_dataset(repo.path(), 10_000, 128);

    let elapsed = measure(|| {
        let report = reindex_from_filesystem(path_string(repo.path()))
            .expect("reindex core benchmark dataset");
        assert_eq!(report.inserted, 10_000);
        assert!(report.errors.is_empty());
    });

    report_ms(
        "reindex_from_filesystem 10k files",
        elapsed,
        REINDEX_10K_FILES_THRESHOLD_MS,
    );
}

fn core_tree_and_list_response_bench() {
    let repo = initialized_repo(false);
    write_repository_dataset(repo.path(), 1_000, 128);
    reindex_from_filesystem(path_string(repo.path())).expect("seed core tree/list metadata");

    let tree_elapsed = measure(|| {
        let tree_json =
            list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list tree JSON");
        assert!(tree_json.contains("\"file_count\":1000"));
    });
    let list_elapsed = measure(|| {
        let files = list_files(path_string(repo.path()), category_filter("docs", 200))
            .expect("list core benchmark files");
        assert_eq!(files.len(), 200);
    });

    report_ms(
        "list_tree_json 1k files",
        tree_elapsed,
        LIST_TREE_1K_THRESHOLD_MS,
    );
    report_us(
        "list_files 200 rows",
        list_elapsed,
        LIST_FILES_200_THRESHOLD_US,
    );
}

fn initialized_repo(create_default_categories: bool) -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize temporary repository");
    repo
}

fn copied_options(category: Option<&str>) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: category.map(str::to_owned),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

fn category_filter(category: &str, limit: i64) -> FileFilter {
    FileFilter {
        category: Some(category.to_owned()),
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit,
        offset: 0,
    }
}

fn write_source_files(root: &Path, count: usize, bytes: usize) -> Vec<PathBuf> {
    (0..count)
        .map(|index| {
            let path = root.join(format!("batch-{index:03}.txt"));
            fs::create_dir_all(root).expect("create source directory");
            fs::write(&path, deterministic_bytes(bytes, index)).expect("write source file");
            path
        })
        .collect()
}

fn write_source_file(root: &Path, name: &str, bytes: usize) -> PathBuf {
    fs::create_dir_all(root).expect("create source directory");
    let path = root.join(name);
    fs::write(&path, deterministic_bytes(bytes, 0)).expect("write source file");
    path
}

fn write_repository_dataset(repo: &Path, count: usize, bytes: usize) {
    for index in 0..count {
        let path = repo.join(format!("docs/bucket-{}/file-{index:05}.txt", index % 100));
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create dataset parent");
        }
        fs::write(path, deterministic_bytes(bytes, index)).expect("write dataset file");
    }
}

fn deterministic_bytes(bytes: usize, seed: usize) -> Vec<u8> {
    (0..bytes)
        .map(|index| ((index + seed) % 251) as u8)
        .collect()
}

fn measure(action: impl FnOnce()) -> Duration {
    let start = Instant::now();
    action();
    start.elapsed()
}

fn report_ms(name: &str, elapsed: Duration, threshold_ms: u128) {
    eprintln!(
        "CORE_HOT_PATH_BENCH name=\"{}\" value_ms={} threshold_ms={} result={}",
        name,
        elapsed.as_millis(),
        threshold_ms,
        pass_label(elapsed.as_millis(), threshold_ms)
    );
}

fn report_us(name: &str, elapsed: Duration, threshold_us: u128) {
    eprintln!(
        "CORE_HOT_PATH_BENCH name=\"{}\" value_us={} threshold_us={} result={}",
        name,
        elapsed.as_micros(),
        threshold_us,
        pass_label(elapsed.as_micros(), threshold_us)
    );
}

fn pass_label(value: u128, threshold: u128) -> &'static str {
    if value < threshold {
        "PASS"
    } else {
        "FAIL"
    }
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}
