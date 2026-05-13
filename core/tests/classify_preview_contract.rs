use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, predict_category, ClassifyReason, ClassifyResult, CoreError, CoreResult,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn write_classifier(repo: &Path, content: &str) {
    fs::write(repo.join(".areamatrix/classifier.yaml"), content).expect("write classifier fixture");
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

fn snapshot_files(root: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut files = BTreeMap::new();
    collect_files(root, root, &mut files);
    files
}

fn collect_files(root: &Path, current: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
    for entry in fs::read_dir(current).expect("read snapshot directory") {
        let path = entry.expect("read snapshot entry").path();
        if path.is_dir() {
            collect_files(root, &path, files);
            continue;
        }

        let relative = path
            .strip_prefix(root)
            .expect("snapshot path under root")
            .to_path_buf();
        let content = fs::read(&path).expect("read snapshot file content");
        files.insert(relative, content);
    }
}

#[test]
fn classify_preview_contract_exports_callable_signature() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}

    assert_predict(predict_category);
}

#[test]
fn classify_preview_contract_docs_udl_and_control_map_stay_aligned() {
    for fragment in [
        "`predict_category(repo_path, filename) -> ClassifyResult`",
        "- `repo_path`",
        "- `filename`",
        "- `category`",
        "- `suggested_name`",
        "- `reason`",
        "- `confidence`",
        "- `Config`",
        "- `Classify`",
        "读取 `.areamatrix/classifier.yaml`",
        "不创建、不移动、不删除文件",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "dictionary ClassifyResult",
        "string category;",
        "string suggested_name;",
        "ClassifyReason reason;",
        "f32 confidence;",
        "enum ClassifyReason { \"Keyword\", \"Extension\", \"AiPredicted\", \"Default\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `predict_category(repo, name)` | classify | √ | Config / Classify |",
        "无写入副作用：只读取 `.areamatrix/classifier.yaml`",
        "`Config`：`repoPath` / `filename` 为空",
        "`Classify`：classifier 规则源无法作为文件读取",
        "UI 在拖入时调用以填充 ImportSheet",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "| S1-16 | drag-hover | C1-05 | `predict_category`",
        "| S1-17 | import-single-sheet | C1-05, C1-06, C1-07, C1-08 | `predict_category`, `import_file`",
        "| S1-18 | import-batch-sheet | C1-05, C1-06, C1-09 | `predict_category`, `import_file`",
        "| S1-19 | import-folder-sheet | C1-05, C1-06, C1-08 | `predict_category`, `import_file`",
        "| S1-28 | settings-classifier | C1-04, C1-05 | `load_config`, `predict_category`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for error_name in ["Config", "Classify"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn classify_preview_contract_keyword_priority_over_extension() {
    let repo = initialized_repo();

    let result = predict_category(path_string(repo.path()), "Invoice_2026_Q1.pdf".to_owned())
        .expect("predict keyword category");

    assert_eq!(result.category, "finance");
    assert_eq!(result.suggested_name, "Invoice_2026_Q1.pdf");
    assert_eq!(result.reason, ClassifyReason::Keyword);
    assert_eq!(result.confidence, 0.9);
}

#[test]
fn classify_preview_contract_extension_match_when_no_keyword_hits() {
    let repo = initialized_repo();

    let result = predict_category(path_string(repo.path()), "main.swift".to_owned())
        .expect("predict extension category");

    assert_eq!(result.category, "code");
    assert_eq!(result.suggested_name, "main.swift");
    assert_eq!(result.reason, ClassifyReason::Extension);
    assert_eq!(result.confidence, 0.7);
}

#[test]
fn classify_preview_contract_default_fallback_does_not_error() {
    let repo = initialized_repo();

    let result = predict_category(path_string(repo.path()), "unmatched.binaryxyz".to_owned())
        .expect("predict default category");

    assert_eq!(result.category, "inbox");
    assert_eq!(result.suggested_name, "unmatched.binaryxyz");
    assert_eq!(result.reason, ClassifyReason::Default);
    assert_eq!(result.confidence, 0.0);
}

#[test]
fn classify_preview_contract_normalizes_case_cjk_and_full_width_keywords() {
    let repo = initialized_repo();

    for filename in [
        "INVOICE_2026.PDF",
        "2026年第一季度发票.pdf",
        "Ｉｎｖｏｉｃｅ.pdf",
    ] {
        let result = predict_category(path_string(repo.path()), filename.to_owned())
            .expect("predict normalized keyword category");

        assert_eq!(result.category, "finance");
        assert_eq!(result.reason, ClassifyReason::Keyword);
    }
}

#[test]
fn classify_preview_contract_invalid_classifier_yaml_returns_config_error() {
    let repo = initialized_repo();
    write_classifier(
        repo.path(),
        "version: 1\ndefault: missing\ncategories: []\n",
    );

    let result = predict_category(path_string(repo.path()), "invoice.pdf".to_owned());

    assert!(matches!(result, Err(CoreError::Config { .. })));
}

#[test]
fn classify_preview_contract_rejects_invalid_classifier_schema_edges() {
    let cases = [
        (
            "extension with dot",
            "version: 1\ndefault: docs\ncategories:\n  - slug: docs\n    extensions: [.pdf]\n",
        ),
        (
            "unknown field",
            "version: 1\ndefault: docs\ncategories:\n  - slug: docs\n    extensoins: [pdf]\n",
        ),
        (
            "duplicate keyword",
            "version: 1\ndefault: docs\ncategories:\n  - slug: docs\n    keywords: [report, report]\n",
        ),
        (
            "priority out of range",
            "version: 1\ndefault: docs\ncategories:\n  - slug: docs\n    priority: 1001\n",
        ),
    ];

    for (name, yaml) in cases {
        let repo = initialized_repo();
        write_classifier(repo.path(), yaml);

        assert!(
            matches!(
                predict_category(path_string(repo.path()), "report.pdf".to_owned()),
                Err(CoreError::Config { .. })
            ),
            "{name} should be rejected"
        );
    }
}

#[test]
fn classify_preview_contract_renders_supported_naming_template_placeholders() {
    let repo = initialized_repo();
    write_classifier(
        repo.path(),
        r#"version: 1
default: inbox
categories:
  - slug: invoices
    keywords: [invoice]
    priority: 20
    naming_template: "{slug}_{stem}.{ext}_{original}_{unknown}"
  - slug: inbox
"#,
    );

    let result = predict_category(path_string(repo.path()), "invoice.pdf".to_owned())
        .expect("predict templated category");

    assert_eq!(result.category, "invoices");
    assert_eq!(result.reason, ClassifyReason::Keyword);
    assert_eq!(
        result.suggested_name,
        "invoices_invoice.pdf_invoice.pdf_{unknown}"
    );
}

#[test]
fn classify_preview_contract_unreadable_classifier_source_returns_classify_error() {
    let repo = initialized_repo();
    let classifier_path = repo.path().join(".areamatrix/classifier.yaml");
    fs::remove_file(&classifier_path).expect("remove classifier file");
    fs::create_dir(&classifier_path).expect("replace classifier file with directory");

    let result = predict_category(path_string(repo.path()), "invoice.pdf".to_owned());

    assert!(matches!(result, Err(CoreError::Classify { .. })));
}

#[test]
fn classify_preview_contract_empty_inputs_return_config_error() {
    let repo = initialized_repo();

    assert!(matches!(
        predict_category(String::new(), "invoice.pdf".to_owned()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        predict_category(path_string(repo.path()), "   ".to_owned()),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn classify_preview_contract_has_no_filesystem_or_db_write_side_effects() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme").expect("write user readme");
    fs::write(repo.path().join("draft.txt"), "draft").expect("write user file");
    let before = snapshot_files(repo.path());

    let result = predict_category(path_string(repo.path()), "contract.pdf".to_owned())
        .expect("predict category without side effects");

    assert_eq!(result.category, "finance");
    assert_eq!(before, snapshot_files(repo.path()));
}
