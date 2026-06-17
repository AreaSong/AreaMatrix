use area_matrix_core::{
    batch_add_tags, BatchMutationItemResult, BatchMutationReport, BatchMutationStatus, CoreError,
    CoreResult,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DATA_MODEL: &str = include_str!("../../docs/architecture/data-model.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const TAGS_RS: &str = include_str!("../src/tags.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn batch_add_tags_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_batch(_: fn(String, Vec<i64>, Vec<String>) -> CoreResult<BatchMutationReport>) {}
    assert_batch(batch_add_tags);

    let report = BatchMutationReport {
        requested_file_count: 3,
        requested_tag_count: 2,
        added_count: 4,
        skipped_count: 1,
        failed_count: 1,
        item_results: vec![
            BatchMutationItemResult {
                file_id: 10,
                tag: "urgent".to_owned(),
                status: BatchMutationStatus::Added,
                error: None,
            },
            BatchMutationItemResult {
                file_id: 11,
                tag: "urgent".to_owned(),
                status: BatchMutationStatus::AlreadyHadTag,
                error: None,
            },
            BatchMutationItemResult {
                file_id: 12,
                tag: "clienta".to_owned(),
                status: BatchMutationStatus::Failed,
                error: Some("file not found".to_owned()),
            },
        ],
        undo_token: Some("undo:batch-tags:42".to_owned()),
    };

    assert_eq!(report.requested_file_count, 3);
    assert_eq!(report.requested_tag_count, 2);
    assert_eq!(report.added_count, 4);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 1);
    assert_eq!(report.item_results[0].status, BatchMutationStatus::Added);
    assert_eq!(
        report.item_results[1].status,
        BatchMutationStatus::AlreadyHadTag
    );
    assert_eq!(report.item_results[2].status, BatchMutationStatus::Failed);
    assert_eq!(report.undo_token.as_deref(), Some("undo:batch-tags:42"));

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::db("batch tag metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn batch_add_tags_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        batch_add_tags(String::new(), vec![1], vec!["urgent".to_owned()]),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        batch_add_tags(
            "/tmp/repo".to_owned(),
            Vec::new(),
            vec!["urgent".to_owned()]
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        batch_add_tags("/tmp/repo".to_owned(), vec![0], vec!["urgent".to_owned()]),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        batch_add_tags("/tmp/repo".to_owned(), vec![1], Vec::new()),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        batch_add_tags("/tmp/repo".to_owned(), vec![1], vec!["bad/tag".to_owned()]),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        batch_add_tags(
            "/tmp/repo".to_owned(),
            vec![1, 1],
            vec!["Urgent".to_owned()]
        ),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn batch_add_tags_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "BatchMutationReport batch_add_tags(",
        "string repo_path, sequence<i64> file_ids, sequence<string> tags",
        "dictionary BatchMutationItemResult",
        "i64 file_id;",
        "string tag;",
        "BatchMutationStatus status;",
        "string? error;",
        "dictionary BatchMutationReport",
        "i64 requested_file_count;",
        "i64 requested_tag_count;",
        "i64 added_count;",
        "i64 skipped_count;",
        "i64 failed_count;",
        "sequence<BatchMutationItemResult> item_results;",
        "string? undo_token;",
        "enum BatchMutationStatus { \"Added\", \"AlreadyHadTag\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `batch_add_tags(repo, file_ids, tags)` | tags | √ | FileNotFound / Db |",
        "### `batch_add_tags(repoPath, fileIds, tags) throws -> BatchMutationReport`",
        "C2-06 的批量加标签入口",
        "`S2-09 batch-add-tags`",
        "`S2-10 undo-toast`",
        "`requested_file_count`",
        "`requested_tag_count`",
        "`added_count`",
        "`skipped_count`",
        "`failed_count`",
        "`item_results`",
        "`undo_token`",
        "`AlreadyHadTag`",
        "成功新增、重复跳过和失败项都必须在 `BatchMutationReport` 中可追踪",
        "批量 AI 标签建议属于 Stage 3",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "CREATE TABLE IF NOT EXISTS undo_actions",
        "token TEXT PRIMARY KEY",
        "kind TEXT NOT NULL",
        "summary_json TEXT NOT NULL",
        "inverse_json TEXT NOT NULL",
        "CHECK (status IN ('pending', 'executed', 'expired', 'blocked'))",
        "CREATE INDEX IF NOT EXISTS idx_undo_actions_status_time",
        "### undo_actions: INSERT",
        "### undo_actions: SELECT pending",
        "### undo_actions: MARK",
    ] {
        assert_contains(DATA_MODEL, fragment);
    }
}

#[test]
fn batch_add_tags_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "C2-06 batch tag mutation contract",
        "S2-09 uses this API",
        "S2-10 consumes the returned undo token",
        "already-present",
        "failed item counts",
        "real writes to `tags`, `change_log`, and the C2-07 undo action",
        "must never move, rename, delete, trash",
    ] {
        assert_contains(TAGS_RS, fragment);
    }

    for error_name in ["FileNotFound", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
