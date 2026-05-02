use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, predict_category, ClassifyReason, CoreError, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const S1_16_DRAG_HOVER: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-16-drag-hover.md");
const S1_17_IMPORT_SINGLE: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md");
const S1_18_IMPORT_BATCH: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md");
const S1_19_IMPORT_FOLDER: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md");
const S1_28_SETTINGS_CLASSIFIER: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md");
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
fn classify_preview_integration_verify_docs_api_and_udl_stay_aligned() {
    for fragment in [
        "`predict_category(repo_path, filename) -> ClassifyResult`",
        "- `category`",
        "- `suggested_name`",
        "- `reason`",
        "- `confidence`",
        "关键词命中优先于扩展名命中",
        "UI 可以用结果预填导入 sheet",
        "不能把 preview 当作最终导入",
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
        "UI 在拖入时调用以填充 ImportSheet",
        "`Config`：`repoPath` / `filename` 为空",
        "`Classify`：classifier 规则源无法作为文件读取",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classify_preview_integration_verify_control_map_matches_consuming_pages() {
    for page in [
        "- S1-16 drag-hover",
        "- S1-17 import-single-sheet",
        "- S1-18 import-batch-sheet",
        "- S1-19 import-folder-sheet",
        "- S1-28 settings-classifier",
    ] {
        assert_contains(CAPABILITY_SPEC, page);
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

    assert_contains(S1_16_DRAG_HOVER, "destination=autoClassify");
    assert_contains(S1_17_IMPORT_SINGLE, "Core `predict_category`");
    assert_contains(S1_18_IMPORT_BATCH, "Core `predict_category`");
    assert_contains(S1_19_IMPORT_FOLDER, "Suggested category");
    assert_contains(S1_28_SETTINGS_CLASSIFIER, "classifier.yaml");
}

#[test]
fn classify_preview_integration_verify_real_core_supports_import_preview_consumers() {
    let repo = initialized_repo();
    let before = snapshot_files(repo.path());

    let keyword = predict_category(path_string(repo.path()), "Invoice_2026.pdf".to_owned())
        .expect("predict keyword category for import preview");
    let extension = predict_category(path_string(repo.path()), "main.swift".to_owned())
        .expect("predict extension category for import preview");
    let fallback = predict_category(path_string(repo.path()), "unmatched.binaryxyz".to_owned())
        .expect("predict fallback category for import preview");

    assert_eq!(keyword.category, "finance");
    assert_eq!(keyword.suggested_name, "Invoice_2026.pdf");
    assert_eq!(keyword.reason, ClassifyReason::Keyword);
    assert_eq!(keyword.confidence, 0.9);

    assert_eq!(extension.category, "code");
    assert_eq!(extension.reason, ClassifyReason::Extension);
    assert_eq!(extension.confidence, 0.7);

    assert_eq!(fallback.category, "inbox");
    assert_eq!(fallback.reason, ClassifyReason::Default);
    assert_eq!(fallback.confidence, 0.0);
    assert_eq!(snapshot_files(repo.path()), before);
}

#[test]
fn classify_preview_integration_verify_errors_do_not_create_import_side_effects() {
    let repo = initialized_repo();
    let classifier = repo.path().join(".areamatrix/classifier.yaml");
    fs::write(
        &classifier,
        "version: 1\ndefault: missing\ncategories: []\n",
    )
    .expect("write invalid classifier fixture");
    let before = snapshot_files(repo.path());

    let result = predict_category(path_string(repo.path()), "invoice.pdf".to_owned());

    assert!(matches!(result, Err(CoreError::Config { .. })));

    assert_eq!(snapshot_files(repo.path()), before);
    assert!(!repo.path().join("invoice.pdf").exists());
}
