use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

const HARD_LIMIT: usize = 500;

struct LegacyOversizedFile {
    path: &'static str,
    owner: &'static str,
    rationale: &'static str,
    split_trigger: &'static str,
    maximum_line_count: usize,
}

const LEGACY_OVERSIZED_FILES: &[LegacyOversizedFile] = &[
    LegacyOversizedFile {
        path: "src/db/schema.rs",
        owner: "database schema lifecycle",
        rationale: "Schema creation, compatibility validation, and migration fixtures share one audited DB boundary.",
        split_trigger: "Before adding a schema revision, extract version-specific migration and fixture modules.",
        maximum_line_count: 1134,
    },
    LegacyOversizedFile {
        path: "src/repair.rs",
        owner: "repository repair and recovery",
        rationale: "Repair planning and execution remain colocated while recovery invariants are stabilized.",
        split_trigger: "Before adding a repair mode, separate read-only diagnosis from mutation execution.",
        maximum_line_count: 821,
    },
    LegacyOversizedFile {
        path: "src/classifier_rule_editor/config.rs",
        owner: "classifier rule configuration",
        rationale: "Parsing, validation, and compatibility behavior currently share one configuration contract.",
        split_trigger: "Before adding a rule format, extract parsing and semantic validation modules.",
        maximum_line_count: 813,
    },
    LegacyOversizedFile {
        path: "src/classifier_rule_editor.rs",
        owner: "classifier rule editing workflow",
        rationale: "The editor facade still coordinates several coupled rule mutation operations.",
        split_trigger: "Before adding an editor operation, extract operation-specific workflow modules.",
        maximum_line_count: 712,
    },
    LegacyOversizedFile {
        path: "src/semantic_search/implementation.rs",
        owner: "semantic search execution",
        rationale: "Query preparation, ranking, and result projection currently share one execution boundary.",
        split_trigger: "Before adding another ranking step, separate query preparation from result projection.",
        maximum_line_count: 654,
    },
    LegacyOversizedFile {
        path: "src/remote_provider_config.rs",
        owner: "remote provider configuration",
        rationale: "Provider validation and non-secret configuration persistence share one security-reviewed boundary.",
        split_trigger: "Before adding a provider type, extract provider-specific validation without moving secret handling into Core.",
        maximum_line_count: 643,
    },
    LegacyOversizedFile {
        path: "src/overview/mod.rs",
        owner: "overview generation orchestration",
        rationale: "Overview planning, generation, and public orchestration remain coupled at the feature boundary.",
        split_trigger: "Before adding an overview mode, extract orchestration state from public feature entry points.",
        maximum_line_count: 642,
    },
    LegacyOversizedFile {
        path: "src/db/sync/receipts.rs",
        owner: "external sync receipt lifecycle",
        rationale: "Receipt compatibility, recovery tokens, and query behavior share transactional invariants.",
        split_trigger: "Before changing receipt persistence, separate compatibility recovery from ordinary receipt queries.",
        maximum_line_count: 556,
    },
    LegacyOversizedFile {
        path: "tests/classifier_rule_editor_implementation.rs",
        owner: "classifier rule editor implementation tests",
        rationale: "The end-to-end editor scenarios retain one ordered contract narrative.",
        split_trigger: "Before adding a scenario, move repeated rule fixtures into tests/support.",
        maximum_line_count: 607,
    },
    LegacyOversizedFile {
        path: "tests/semantic_search_implementation.rs",
        owner: "semantic search implementation tests",
        rationale: "Indexing, query, ranking, and fallback assertions currently share one behavior suite.",
        split_trigger: "Before adding a ranking mode, extract shared search fixtures into tests/support.",
        maximum_line_count: 560,
    },
    LegacyOversizedFile {
        path: "tests/release_evidence_checklist.rs",
        owner: "release evidence contract tests",
        rationale: "Evidence checklist assertions span the same release-readiness source contract.",
        split_trigger: "Before adding an evidence family, extract source loaders and common assertions.",
        maximum_line_count: 538,
    },
    LegacyOversizedFile {
        path: "tests/release_evidence_residual_records.rs",
        owner: "release residual evidence tests",
        rationale: "Residual classification and evidence pinning remain one cross-source audit suite.",
        split_trigger: "Before adding a residual class, extract registry fixtures into tests/support.",
        maximum_line_count: 531,
    },
    LegacyOversizedFile {
        path: "tests/overview_regeneration_implementation.rs",
        owner: "overview regeneration implementation tests",
        rationale: "Prepare, execute, resume, and commit scenarios share one regeneration lifecycle.",
        split_trigger: "Before adding another lifecycle state, split operation fixtures from behavior assertions.",
        maximum_line_count: 529,
    },
    LegacyOversizedFile {
        path: "tests/load_update_config_contract.rs",
        owner: "repository configuration contract tests",
        rationale: "Load/update compare-and-swap behavior shares one revisioned contract suite.",
        split_trigger: "Before adding a config surface, extract patch and revision fixtures.",
        maximum_line_count: 529,
    },
    LegacyOversizedFile {
        path: "tests/classifier_rule_editor_failure_recovery.rs",
        owner: "classifier rule editor recovery tests",
        rationale: "Failure injection and recovery assertions share editor transaction fixtures.",
        split_trigger: "Before adding a failure point, extract recovery fixtures into tests/support.",
        maximum_line_count: 508,
    },
    LegacyOversizedFile {
        path: "tests/saved_search_implementation.rs",
        owner: "saved search implementation tests",
        rationale: "Saved-search CRUD and execution behavior remain one feature contract suite.",
        split_trigger: "Before adding a saved-search operation, extract repository fixtures.",
        maximum_line_count: 502,
    },
    LegacyOversizedFile {
        path: "tests/missing_file_recovery_failure_recovery.rs",
        owner: "missing-file recovery failure tests",
        rationale: "Failure recovery scenarios share filesystem and metadata consistency assertions.",
        split_trigger: "Before adding a failure point, extract filesystem fixtures into tests/support.",
        maximum_line_count: 501,
    },
];

#[test]
fn rust_source_files_stay_within_limit_or_an_exact_legacy_budget() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let actual = rust_source_line_counts(&manifest_dir.join("src"))
        .into_iter()
        .chain(rust_source_line_counts(&manifest_dir.join("tests")))
        .collect::<BTreeMap<_, _>>();
    let inventory = LEGACY_OVERSIZED_FILES
        .iter()
        .map(|item| (item.path, item))
        .collect::<BTreeMap<_, _>>();

    let oversized = actual
        .iter()
        .filter(|(_, line_count)| **line_count > HARD_LIMIT)
        .map(|(path, line_count)| (path.as_str(), *line_count))
        .collect::<BTreeMap<_, _>>();

    assert_eq!(
        oversized.keys().copied().collect::<Vec<_>>(),
        inventory.keys().copied().collect::<Vec<_>>(),
        "every Rust source above {HARD_LIMIT} lines must have an exact legacy budget"
    );

    let growth = oversized
        .iter()
        .filter_map(|(path, line_count)| {
            let budget = inventory[path];
            (*line_count > budget.maximum_line_count)
                .then(|| format!("{path}:{line_count}>{}", budget.maximum_line_count))
        })
        .collect::<Vec<_>>();
    assert!(
        growth.is_empty(),
        "legacy oversized Rust files cannot grow; split the documented boundary first: {growth:?}"
    );
}

#[test]
fn legacy_budgets_document_owner_rationale_and_exit_condition() {
    let incomplete = LEGACY_OVERSIZED_FILES
        .iter()
        .filter(|item| {
            item.owner.is_empty() || item.rationale.is_empty() || item.split_trigger.is_empty()
        })
        .map(|item| item.path)
        .collect::<Vec<_>>();

    assert!(
        incomplete.is_empty(),
        "legacy oversized Rust files need an owner, rationale, and split trigger: {incomplete:?}"
    );
}

fn rust_source_line_counts(source_root: &Path) -> BTreeMap<String, usize> {
    let mut files = Vec::new();
    collect_rust_files(source_root, &mut files);
    files
        .into_iter()
        .map(|path| {
            let relative = path
                .strip_prefix(source_root.parent().expect("Core source parent"))
                .expect("Rust source under Core")
                .to_string_lossy()
                .replace('\\', "/");
            let source = fs::read_to_string(&path).expect("read Rust source");
            (relative, source.lines().count())
        })
        .collect()
}

fn collect_rust_files(directory: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(directory).expect("read Rust source directory") {
        let path = entry.expect("read Rust source entry").path();
        if path.is_dir() {
            collect_rust_files(&path, files);
        } else if path.extension().and_then(|value| value.to_str()) == Some("rs") {
            files.push(path);
        }
    }
}
