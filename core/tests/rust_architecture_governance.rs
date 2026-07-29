use std::fs;
use std::path::{Path, PathBuf};

struct LegacyDependencyException {
    violation: &'static str,
    owner: &'static str,
    rationale: &'static str,
    exit_condition: &'static str,
}

const LEGACY_DEPENDENCY_EXCEPTIONS: &[LegacyDependencyException] = &[LegacyDependencyException {
    violation: "src/storage/staging_row.rs:3:crate::db",
    owner: "transactional staging recovery",
    rationale: "The staging row adapter still shares the DB row contract used by recovery transactions.",
    exit_condition: concat!(
        "When staging recovery is next changed with explicit file-safety approval, move the shared row ",
        "contract into domain and remove this reverse dependency."
    ),
}];

#[test]
fn stable_core_layers_do_not_reverse_the_documented_dependency_direction() {
    let core = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let rules = [
        LayerRule {
            roots: &["src/domain.rs", "src/domain", "src/error.rs", "src/error"],
            forbidden: &["crate::api", "crate::db", "crate::storage"],
        },
        LayerRule {
            roots: &["src/db.rs", "src/db"],
            forbidden: &["crate::api", "crate::storage"],
        },
        LayerRule {
            roots: &["src/storage.rs", "src/storage"],
            forbidden: &["crate::api", "crate::db"],
        },
    ];

    let mut violations = rules
        .iter()
        .flat_map(|rule| layer_violations(&core, rule))
        .collect::<Vec<_>>();
    violations.sort();

    let expected = LEGACY_DEPENDENCY_EXCEPTIONS
        .iter()
        .map(|exception| exception.violation.to_owned())
        .collect::<Vec<_>>();
    assert_eq!(
        violations, expected,
        concat!(
            "Core layer dependencies must follow api/feature -> domain|db|storage and db|storage -> domain; ",
            "legacy exceptions are exact and cannot grow"
        )
    );
}

#[test]
fn legacy_dependency_exceptions_document_owner_rationale_and_exit_condition() {
    let incomplete = LEGACY_DEPENDENCY_EXCEPTIONS
        .iter()
        .filter(|exception| {
            exception.owner.is_empty()
                || exception.rationale.is_empty()
                || exception.exit_condition.is_empty()
        })
        .map(|exception| exception.violation)
        .collect::<Vec<_>>();

    assert!(
        incomplete.is_empty(),
        "legacy dependency exceptions need an owner, rationale, and exit condition: {incomplete:?}"
    );
}

#[test]
fn core_source_stays_free_of_apple_ui_and_event_stream_dependencies() {
    let core = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let forbidden = [
        "std::os::macos",
        "use AppKit",
        "extern crate AppKit",
        "use SwiftUI",
        "extern crate SwiftUI",
        "CoreServices::FSEvent",
    ];
    let violations = rust_files(&core.join("src"))
        .into_iter()
        .flat_map(|path| text_violations(&core, &path, &forbidden))
        .collect::<Vec<_>>();

    assert!(
        violations.is_empty(),
        "Rust Core must remain platform-neutral; Apple UI/event-stream capabilities belong in Swift: {violations:?}"
    );
}

struct LayerRule {
    roots: &'static [&'static str],
    forbidden: &'static [&'static str],
}

fn layer_violations(core: &Path, rule: &LayerRule) -> Vec<String> {
    rule.roots
        .iter()
        .flat_map(|relative| {
            let path = core.join(relative);
            if path.is_dir() {
                rust_files(&path)
            } else if path.is_file() {
                vec![path]
            } else {
                Vec::new()
            }
        })
        .flat_map(|path| text_violations(core, &path, rule.forbidden))
        .collect()
}

fn text_violations(core: &Path, path: &Path, forbidden: &[&str]) -> Vec<String> {
    let source = fs::read_to_string(path).expect("read governed Rust source");
    source
        .lines()
        .enumerate()
        .flat_map(|(index, line)| {
            forbidden
                .iter()
                .filter(move |term| line.contains(*term))
                .map(move |term| {
                    format!(
                        "{}:{}:{term}",
                        path.strip_prefix(core)
                            .expect("governed Rust source under Core")
                            .display(),
                        index + 1
                    )
                })
        })
        .collect()
}

fn rust_files(directory: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    collect_rust_files(directory, &mut files);
    files
}

fn collect_rust_files(directory: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(directory).expect("read governed Rust directory") {
        let path = entry.expect("read governed Rust entry").path();
        if path.is_dir() {
            collect_rust_files(&path, files);
        } else if path.extension().and_then(|value| value.to_str()) == Some("rs") {
            files.push(path);
        }
    }
}
