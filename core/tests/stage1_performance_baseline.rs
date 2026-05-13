use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

use area_matrix_core::{
    import_file, init_repo, list_files, list_tree_json, reindex_from_filesystem, DuplicateStrategy,
    FileFilter, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};

const ONE_MIB: usize = 1024 * 1024;
const IMPORT_ONE_MIB_THRESHOLD_MS: u128 = 30;
const IMPORT_100_FILES_THRESHOLD_MS: u128 = 5_000;
const REINDEX_10K_FILES_THRESHOLD_MS: u128 = 30_000;
const LIST_FILES_200_THRESHOLD_US: u128 = 5_000;
const LIST_TREE_1K_THRESHOLD_MS: u128 = 30;

#[test]
#[ignore = "Stage 1 release performance baseline; run explicitly with --release --ignored --test-threads=1"]
fn stage1_import_one_mebibyte_copy_under_threshold() {
    let repo = initialized_repo(true);
    let source_root = tempfile::tempdir().expect("create source root");
    let source = write_source_file(source_root.path(), "invoice.pdf", ONE_MIB);

    let elapsed = measure(|| {
        import_file(
            path_string(repo.path()),
            path_string(&source),
            copied_options(Some("finance")),
        )
        .expect("import one MiB file");
    });

    report_ms(
        "import_file 1 MiB copied",
        elapsed,
        IMPORT_ONE_MIB_THRESHOLD_MS,
    );
    assert!(
        elapsed.as_millis() < IMPORT_ONE_MIB_THRESHOLD_MS,
        "1 MiB copied import exceeded Stage 1 threshold"
    );
}

#[test]
#[ignore = "Stage 1 release performance baseline; run explicitly with --release --ignored --test-threads=1"]
fn stage1_import_one_hundred_files_under_threshold() {
    let repo = initialized_repo(true);
    let source_root = tempfile::tempdir().expect("create source root");
    let sources = write_source_files(source_root.path(), 100, 4 * 1024);

    let elapsed = measure(|| {
        for source in &sources {
            import_file(
                path_string(repo.path()),
                path_string(source),
                copied_options(Some("docs")),
            )
            .expect("import batch file");
        }
        let mut filter = default_filter();
        filter.category = Some("docs".to_owned());
        filter.limit = 100;
        assert_eq!(
            list_files(path_string(repo.path()), filter)
                .expect("list imported batch")
                .len(),
            100
        );
    });

    report_ms(
        "100 file copied batch import + list",
        elapsed,
        IMPORT_100_FILES_THRESHOLD_MS,
    );
    assert!(
        elapsed.as_millis() < IMPORT_100_FILES_THRESHOLD_MS,
        "100 file copied batch import exceeded Stage 1 threshold"
    );
}

#[test]
#[ignore = "Stage 1 release performance baseline; run explicitly with --release --ignored --test-threads=1"]
fn stage1_reindex_ten_thousand_files_under_threshold() {
    let repo = initialized_repo(false);
    write_repository_dataset(repo.path(), 10_000, 128);

    let elapsed = measure(|| {
        let report =
            reindex_from_filesystem(path_string(repo.path())).expect("reindex ten thousand files");
        assert_eq!(report.inserted, 10_000);
        assert_eq!(report.errors, Vec::<String>::new());
    });

    report_ms(
        "reindex_from_filesystem 10k files",
        elapsed,
        REINDEX_10K_FILES_THRESHOLD_MS,
    );
    assert!(
        elapsed.as_millis() < REINDEX_10K_FILES_THRESHOLD_MS,
        "10k file reindex exceeded Stage 1 threshold"
    );
}

#[test]
#[ignore = "Stage 1 release performance baseline; run explicitly with --release --ignored --test-threads=1"]
fn stage1_tree_and_list_responses_under_thresholds() {
    let repo = initialized_repo(false);
    write_repository_dataset(repo.path(), 1_000, 128);
    let report =
        reindex_from_filesystem(path_string(repo.path())).expect("seed metadata for list_files");
    assert_eq!(report.inserted, 1_000);

    let tree_elapsed = measure(|| {
        let tree_json =
            list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list tree JSON");
        assert!(tree_json.contains("\"file_count\":1000"));
    });

    let mut filter = default_filter();
    filter.category = Some("docs".to_owned());
    filter.limit = 200;
    let list_elapsed = measure(|| {
        let files = list_files(path_string(repo.path()), filter.clone()).expect("list 200 files");
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
    assert!(
        tree_elapsed.as_millis() < LIST_TREE_1K_THRESHOLD_MS,
        "1k file tree response exceeded Stage 1 threshold"
    );
    assert!(
        list_elapsed.as_micros() < LIST_FILES_200_THRESHOLD_US,
        "200 row list response exceeded Stage 1 threshold"
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
        },
    )
    .expect("initialize repository");
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
    }
}

fn default_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 200,
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
        "STAGE1_PERF name=\"{}\" value_ms={} threshold_ms={} result={}",
        name,
        elapsed.as_millis(),
        threshold_ms,
        pass_label(elapsed.as_millis(), threshold_ms)
    );
}

fn report_us(name: &str, elapsed: Duration, threshold_us: u128) {
    eprintln!(
        "STAGE1_PERF name=\"{}\" value_us={} threshold_us={} result={}",
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
