use area_matrix_core::{
    batch_rename, preview_batch_rename, BatchRenameConflict, BatchRenameDateSource,
    BatchRenameItemResult, BatchRenameMode, BatchRenamePreviewItem, BatchRenamePreviewReport,
    BatchRenamePreviewStatus, BatchRenameReport, BatchRenameResultStatus, BatchRenameRule,
    CoreError, CoreResult, FileEntry, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const BATCH_RENAME_RS: &str = include_str!("../src/batch_rename.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn batch_rename_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_preview(
        _: fn(String, Vec<i64>, BatchRenameRule) -> CoreResult<BatchRenamePreviewReport>,
    ) {
    }
    fn assert_apply(
        _: fn(String, Vec<i64>, BatchRenameRule, String) -> CoreResult<BatchRenameReport>,
    ) {
    }

    assert_preview(preview_batch_rename);
    assert_apply(batch_rename);

    let rule = BatchRenameRule {
        mode: BatchRenameMode::Prefix,
        prefix: Some("ProjectA_".to_owned()),
        date_source: None,
        date_format: None,
        separator: None,
        start_number: None,
        padding: None,
        find: None,
        replacement: None,
        case_sensitive: false,
    };
    assert_eq!(rule.mode, BatchRenameMode::Prefix);

    let preview = BatchRenamePreviewReport {
        requested_file_count: 5,
        rule: rule.clone(),
        preview_token: "preview:batch-rename:42".to_owned(),
        will_rename_count: 2,
        display_only_count: 1,
        unchanged_count: 1,
        blocked_count: 2,
        conflict_count: 1,
        items: vec![
            BatchRenamePreviewItem {
                file_id: 10,
                current_path: Some("reports/a.pdf".to_owned()),
                original_name: Some("a.pdf".to_owned()),
                new_name: Some("ProjectA_a.pdf".to_owned()),
                target_path: Some("reports/ProjectA_a.pdf".to_owned()),
                storage_mode: Some(StorageMode::Copied),
                index_only: false,
                will_rename_file: true,
                status: BatchRenamePreviewStatus::Ok,
                reason: None,
            },
            BatchRenamePreviewItem {
                file_id: 11,
                current_path: Some("/external/b.pdf".to_owned()),
                original_name: Some("b.pdf".to_owned()),
                new_name: Some("ProjectA_b.pdf".to_owned()),
                target_path: None,
                storage_mode: Some(StorageMode::Indexed),
                index_only: true,
                will_rename_file: false,
                status: BatchRenamePreviewStatus::DisplayOnly,
                reason: None,
            },
            BatchRenamePreviewItem {
                file_id: 12,
                current_path: Some("reports/conflict.pdf".to_owned()),
                original_name: Some("conflict.pdf".to_owned()),
                new_name: Some("ProjectA_conflict.pdf".to_owned()),
                target_path: Some("reports/ProjectA_conflict.pdf".to_owned()),
                storage_mode: Some(StorageMode::Copied),
                index_only: false,
                will_rename_file: false,
                status: BatchRenamePreviewStatus::NameConflict,
                reason: Some("target already exists".to_owned()),
            },
        ],
        conflicts: vec![BatchRenameConflict {
            file_id: 12,
            conflicting_file_id: Some(13),
            conflict_path: Some("reports/ProjectA_conflict.pdf".to_owned()),
            reason: "duplicate generated name".to_owned(),
        }],
        can_apply: false,
        apply_blocked_reason: Some("resolve rename conflicts".to_owned()),
    };
    assert_eq!(preview.requested_file_count, 5);
    assert_eq!(preview.will_rename_count, 2);
    assert_eq!(preview.display_only_count, 1);
    assert_eq!(preview.items[0].status, BatchRenamePreviewStatus::Ok);
    assert_eq!(
        preview.items[1].status,
        BatchRenamePreviewStatus::DisplayOnly
    );
    assert_eq!(
        preview.items[2].status,
        BatchRenamePreviewStatus::NameConflict
    );
    assert!(!preview.can_apply);

    let updated = FileEntry {
        id: 10,
        path: "reports/ProjectA_a.pdf".to_owned(),
        original_name: "a.pdf".to_owned(),
        current_name: "ProjectA_a.pdf".to_owned(),
        category: "reports".to_owned(),
        size_bytes: 128,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/a.pdf".to_owned()),
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 100,
        updated_at: 200,
    };
    let report = BatchRenameReport {
        requested_file_count: 5,
        renamed_count: 2,
        display_name_updated_count: 1,
        unchanged_count: 1,
        skipped_count: 0,
        failed_count: 1,
        item_results: vec![
            BatchRenameItemResult {
                file_id: 10,
                original_name: Some("a.pdf".to_owned()),
                final_name: Some("ProjectA_a.pdf".to_owned()),
                final_path: Some("reports/ProjectA_a.pdf".to_owned()),
                status: BatchRenameResultStatus::Renamed,
                error: None,
            },
            BatchRenameItemResult {
                file_id: 11,
                original_name: Some("b.pdf".to_owned()),
                final_name: Some("ProjectA_b.pdf".to_owned()),
                final_path: Some("/external/b.pdf".to_owned()),
                status: BatchRenameResultStatus::DisplayNameUpdated,
                error: None,
            },
            BatchRenameItemResult {
                file_id: 12,
                original_name: Some("conflict.pdf".to_owned()),
                final_name: None,
                final_path: None,
                status: BatchRenameResultStatus::Failed,
                error: Some("target already exists".to_owned()),
            },
        ],
        updated_files: vec![updated],
        undo_token: Some("undo:rename-files:42".to_owned()),
    };
    assert_eq!(report.renamed_count, 2);
    assert_eq!(report.display_name_updated_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchRenameResultStatus::Renamed
    );
    assert_eq!(
        report.item_results[1].status,
        BatchRenameResultStatus::DisplayNameUpdated
    );
    assert_eq!(
        report.item_results[2].status,
        BatchRenameResultStatus::Failed
    );
    assert_eq!(
        report.updated_files[0].current_name,
        "ProjectA_a.pdf".to_owned()
    );
    assert_eq!(report.undo_token.as_deref(), Some("undo:rename-files:42"));

    let documented_errors = [
        CoreError::invalid_path("bad name"),
        CoreError::conflict("stale preview"),
        CoreError::file_not_found("missing file"),
        CoreError::permission_denied("read only"),
        CoreError::io("rename failed"),
        CoreError::db("metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 6);
}

#[test]
fn batch_rename_contract_validates_inputs_without_fake_success() {
    let uninitialized_repo = tempfile::tempdir().expect("create uninitialized repository");
    let uninitialized_repo_path = uninitialized_repo.path().to_string_lossy().into_owned();

    let prefix_rule = BatchRenameRule {
        mode: BatchRenameMode::Prefix,
        prefix: Some("ProjectA_".to_owned()),
        date_source: None,
        date_format: None,
        separator: None,
        start_number: None,
        padding: None,
        find: None,
        replacement: None,
        case_sensitive: false,
    };
    assert!(matches!(
        preview_batch_rename(String::new(), vec![1], prefix_rule.clone()),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        preview_batch_rename("/tmp/repo".to_owned(), Vec::new(), prefix_rule.clone()),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_rename("/tmp/repo".to_owned(), vec![0], prefix_rule.clone()),
        Err(CoreError::FileNotFound { .. })
    ));

    let replace_rule = BatchRenameRule {
        mode: BatchRenameMode::ReplaceText,
        prefix: None,
        date_source: None,
        date_format: None,
        separator: None,
        start_number: None,
        padding: None,
        find: Some(String::new()),
        replacement: Some("final".to_owned()),
        case_sensitive: false,
    };
    assert!(matches!(
        preview_batch_rename("/tmp/repo".to_owned(), vec![1], replace_rule),
        Err(CoreError::InvalidPath { .. })
    ));

    let sequence_rule = BatchRenameRule {
        mode: BatchRenameMode::KeepBaseSequence,
        prefix: None,
        date_source: None,
        date_format: None,
        separator: Some("_".to_owned()),
        start_number: Some(1),
        padding: Some(2),
        find: None,
        replacement: None,
        case_sensitive: false,
    };
    assert!(matches!(
        batch_rename(
            "/tmp/repo".to_owned(),
            vec![1],
            sequence_rule.clone(),
            String::new()
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert!(matches!(
        batch_rename(
            uninitialized_repo_path,
            vec![1, 1],
            sequence_rule,
            "preview:batch-rename:42".to_owned()
        ),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn batch_rename_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "BatchRenamePreviewReport preview_batch_rename(",
        "sequence<i64> file_ids",
        "BatchRenameRule rule",
        "BatchRenameReport batch_rename(",
        "string preview_token",
        "dictionary BatchRenameRule",
        "BatchRenameMode mode;",
        "BatchRenameDateSource? date_source;",
        "dictionary BatchRenamePreviewItem",
        "BatchRenamePreviewStatus status;",
        "dictionary BatchRenamePreviewReport",
        "i64 will_rename_count;",
        "i64 display_only_count;",
        "i64 unchanged_count;",
        "i64 blocked_count;",
        "i64 conflict_count;",
        "sequence<BatchRenameConflict> conflicts;",
        "boolean can_apply;",
        "dictionary BatchRenameItemResult",
        "BatchRenameResultStatus status;",
        "dictionary BatchRenameReport",
        "i64 renamed_count;",
        "i64 display_name_updated_count;",
        "sequence<FileEntry> updated_files;",
        "string? undo_token;",
        "enum BatchRenameMode { \"Prefix\", \"DatePrefix\", \"KeepBaseSequence\", \"ReplaceText\" };",
        "enum BatchRenameDateSource { \"Imported\", \"Modified\", \"Today\" };",
        "enum BatchRenameResultStatus { \"Renamed\", \"DisplayNameUpdated\", \"Unchanged\", \"Skipped\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    assert_contains(
        CORE_API,
        "\"Ok\", \"Error\", \"NameConflict\", \"Missing\", \"ReadOnly\"",
    );
    assert_contains(
        UDL,
        "\"Ok\", \"Error\", \"NameConflict\", \"Missing\", \"ReadOnly\"",
    );

    for fragment in [
        "| `preview_batch_rename(repo, file_ids, rule)` | storage | √ | InvalidPath / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "| `batch_rename(repo, file_ids, rule, preview_token)` | storage | √ | InvalidPath / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "### `preview_batch_rename(repoPath, fileIds, rule) throws -> BatchRenamePreviewReport`",
        "### `batch_rename(repoPath, fileIds, rule, previewToken) throws -> BatchRenameReport`",
        "`batch rename surface`",
        "`undo toast`",
        "`preview_token`",
        "`BatchRenameRule`",
        "`will_rename_count`",
        "`display_only_count`",
        "`conflict_count`",
        "`conflicts`",
        "`updated_files`",
        "`undo_token`",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn batch_rename_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "batch rename contract",
        "BatchRenamePreviewReport",
        "BatchRenameReport",
        "preview_batch_rename",
        "batch_rename",
        "without mutating files or metadata",
        "build_batch_rename_plan",
        "apply_batch_rename_plan",
        "must not change extensions",
    ] {
        assert_contains(BATCH_RENAME_RS, fragment);
    }

    for fragment in [
        "pub fn preview_batch_rename(",
        "batch_rename_mod::preview_batch_rename",
        "pub fn batch_rename(",
        "batch_rename_mod::batch_rename",
        "batch rename surface",
        "batch rename",
        "must not implement AI naming",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in [
        "InvalidPath",
        "Conflict",
        "FileNotFound",
        "PermissionDenied",
        "Io",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn batch_rename_rule_variants_cover_batch_rename_strategies() {
    let variants = [
        BatchRenameMode::Prefix,
        BatchRenameMode::DatePrefix,
        BatchRenameMode::KeepBaseSequence,
        BatchRenameMode::ReplaceText,
    ];
    assert_eq!(variants.len(), 4);
    assert_eq!(
        BatchRenameDateSource::Imported,
        BatchRenameDateSource::Imported
    );
    assert_eq!(
        BatchRenameDateSource::Modified,
        BatchRenameDateSource::Modified
    );
    assert_eq!(BatchRenameDateSource::Today, BatchRenameDateSource::Today);
}
