use std::{fs, path::Path};

use area_matrix_core::{
    build_embedding_index, semantic_search, SearchPagination, SemanticIndexStatus,
    SemanticSearchFallbackReason, SemanticSearchInputField, SemanticSearchRoute,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[allow(dead_code)]
#[path = "support/semantic_search_common.rs"]
mod semantic_search_common;
use semantic_search_common::{
    default_filter, enable_local_semantic_search, first_page, initialized_repo, insert_file,
    path_string, repo_config_value, semantic_scope,
};

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-39-c3-08-validation.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-08-semantic-search.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const LIB_RS: &str = include_str!("../src/lib.rs");
const SEMANTIC_RS: &str = include_str!("../src/semantic_search.rs");
const SEMANTIC_IMPL_RS: &str = include_str!("../src/semantic_search/implementation.rs");
const SEMANTIC_STORE_RS: &str = include_str!("../src/semantic_search/store.rs");
const SEMANTIC_MATCHES_RS: &str = include_str!("../src/semantic_search/matches.rs");
const SEMANTIC_PRIVACY_RS: &str = include_str!("../src/semantic_search/privacy.rs");
const SEMANTIC_CALL_LOG_RS: &str = include_str!("../src/semantic_search/call_log.rs");
const CONTRACT_TEST: &str = include_str!("semantic_search_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("semantic_search_implementation.rs");
const FAILURE_TEST: &str = include_str!("semantic_search_failure_recovery.rs");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn table_count(repo: &Path, table: &str) -> i64 {
    if !table_exists(repo, table) {
        return 0;
    }
    open_db(repo)
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .expect("count table rows")
}

fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(true),
        )
        .unwrap_or(false)
}

fn semantic_index_entry_count(repo: &Path) -> i64 {
    table_count(repo, "semantic_index_entries")
}

#[test]
fn semantic_search_validation_proves_ui_ready_success_and_fallback_paths() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let invoice_id = insert_file(
        repo.path(),
        "finance/invoices/invoice-validation.txt",
        "finance",
        Some("last month invoice validation note"),
    );

    let fallback = semantic_search(
        repo_path.clone(),
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("default AI-off semantic fallback");
    assert_eq!(
        fallback.fallback_reason,
        Some(SemanticSearchFallbackReason::AiDisabled)
    );
    assert_eq!(fallback.semantic_total_count, 0);
    assert_eq!(fallback.normal_total_count, 1);
    assert_eq!(semantic_index_entry_count(repo.path()), 0);

    assert_ready_index_after_build(repo.path(), repo_path, invoice_id);
}

fn assert_ready_index_after_build(repo: &Path, repo_path: String, invoice_id: i64) {
    enable_local_semantic_search(repo);
    let report =
        build_embedding_index(repo_path.clone(), semantic_scope()).expect("build semantic index");
    let page = semantic_search(
        repo_path,
        "invoice validation".to_owned(),
        default_filter(),
        SearchPagination {
            limit: 25,
            offset: 0,
        },
    )
    .expect("semantic search after index build");

    assert_eq!(report.status, SemanticIndexStatus::Ready);
    assert_eq!(report.processed_count, 1);
    assert_eq!(report.privacy_skipped_count, 0);
    assert_eq!(page.index_status, SemanticIndexStatus::Ready);
    assert_eq!(page.route, Some(SemanticSearchRoute::Local));
    assert_eq!(page.fallback_reason, None);
    assert_eq!(page.semantic_total_count, 1);
    assert_eq!(page.semantic_matches[0].result.entry.id, invoice_id);
    assert!(page.semantic_matches[0]
        .used_fields
        .contains(&SemanticSearchInputField::FileName));
    assert!(page.semantic_matches[0].also_matched_normal_search);
    assert_eq!(page.normal_matches[0].deduped_by_semantic, true);
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read user README"),
        "user readme\n"
    );
    assert!(repo_config_value(repo, "semantic_index_metadata").is_some());
}

#[test]
fn semantic_search_validation_locks_api_udl_and_rust_surface() {
    assert_task_and_docs_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_contract_and_implementation_alignment();
    assert_existing_success_and_failure_tests_are_present();
}

fn assert_task_and_docs_alignment() {
    for fragment in [
        "# 4-2/task-39: C3-08 validation",
        "为 C3-08 semantic-search 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "./dev check task 4-2/task-39",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "计划新增：`semantic_search(repo_path, query, filter, pagination) -> SemanticSearchResultPage`",
        "计划新增：`build_embedding_index(repo_path, scope)`",
        "普通搜索失败不依赖语义搜索。",
        "隐私规则阻止的文件不进入 embedding。",
        "provider 失败时能回退到普通搜索。",
        "Core 不生成不可解释的单一混合分数。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    assert_contains(
        CONTROL_MAP,
        "| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 | semantic search / embedding |",
    );
    for fragment in ["Rust 单元测试", "集成测试目录", "tempfile::TempDir"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "SemanticSearchResultPage semantic_search(",
        "SemanticIndexBuildReport build_embedding_index(",
        "dictionary SemanticSearchMatch",
        "dictionary SemanticNormalSearchMatch",
        "dictionary SemanticSearchResultPage",
        "dictionary SemanticIndexScope",
        "dictionary SemanticIndexBuildReport",
        "enum SemanticSearchRoute { \"Local\", \"Remote\" };",
        "enum SemanticSearchInputField",
        "enum SemanticIndexStatus",
        "enum SemanticSearchFallbackReason",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for field in [
        "query",
        "semantic_total_count",
        "normal_total_count",
        "semantic_matches",
        "normal_matches",
        "deduped_normal_count",
        "index_status",
        "fallback_reason",
        "fallback_message",
        "privacy_rule_id",
        "low_confidence",
    ] {
        assert_contains(CORE_API, field);
        assert_contains(UDL, field);
        assert_contains(SEMANTIC_RS, &format!("pub {field}:"));
    }

    for reason in [
        "AiDisabled",
        "FeatureDisabled",
        "ProviderUnavailable",
        "PrivacyRule",
        "SemanticIndexNotReady",
        "CallLogUnavailable",
        "NoEligibleInput",
        "NormalSearchUnavailable",
        "RateLimited",
        "Timeout",
    ] {
        assert_contains(CORE_API, reason);
        assert_contains(UDL, reason);
        assert_contains(SEMANTIC_RS, reason);
    }
}

fn assert_rust_contract_and_implementation_alignment() {
    assert_rust_public_surface_alignment();
    assert_rust_implementation_alignment();
}

fn assert_rust_public_surface_alignment() {
    for fragment in [
        "pub use semantic_search::{",
        "build_embedding_index, semantic_search",
        "SemanticSearchResultPage",
        "SemanticIndexBuildReport",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "pub fn semantic_search(",
        "pub fn build_embedding_index(",
        "validate_repo_path",
        "validate_query",
        "validate_filter",
        "validate_pagination",
        "validate_index_scope",
        "looks_sensitive",
    ] {
        assert_contains(SEMANTIC_RS, fragment);
    }
}

fn assert_rust_implementation_alignment() {
    for fragment in [
        "normal_search(",
        "fallback_search_page_from_normal_result",
        "load_semantic_index",
        "load_indexed_files",
        "save_semantic_index",
        "insert_call_log",
    ] {
        assert_contains(SEMANTIC_IMPL_RS, fragment);
    }

    for fragment in [
        "PrivacyEvaluator::from_rules_json",
        "build_index_groups",
        "semantic_index_entries",
        "SearchLog::success",
    ] {
        assert_contains(SEMANTIC_PRIVACY_RS, "blocking_rule");
        assert_contains(SEMANTIC_MATCHES_RS, "deduped_by_semantic");
        assert_contains(SEMANTIC_STORE_RS, "semantic_index_metadata");
        assert_contains(SEMANTIC_CALL_LOG_RS, "semantic_search");
        assert_contains(
            &format!(
                "{SEMANTIC_IMPL_RS}\n{SEMANTIC_PRIVACY_RS}\n{SEMANTIC_MATCHES_RS}\n{SEMANTIC_STORE_RS}\n{SEMANTIC_CALL_LOG_RS}"
            ),
            fragment,
        );
    }
}

fn assert_existing_success_and_failure_tests_are_present() {
    let tests = format!("{CONTRACT_TEST}\n{IMPLEMENTATION_TEST}\n{FAILURE_TEST}");
    for fragment in [
        "semantic_search_contract_docs_api_udl_and_control_map_stay_aligned",
        "semantic_search_contract_rejects_invalid_inputs_without_fake_success",
        "semantic_search_builds_index_and_returns_explainable_groups",
        "semantic_search_privacy_rules_skip_matching_files_without_indexing_content",
        "semantic_search_keeps_semantic_group_when_normal_search_is_unavailable",
        "semantic_search_failure_invalid_inputs_are_config_errors_without_writes",
        "semantic_search_failure_permission_denied_on_content_read_is_structured_and_non_mutating",
        "semantic_search_failure_call_log_abort_rolls_back_index_metadata",
        "semantic_search_failure_privacy_skip_and_remote_gate_do_not_leak_key_material",
    ] {
        assert_contains(&tests, fragment);
    }
}
