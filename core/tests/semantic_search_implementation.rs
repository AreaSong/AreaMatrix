use std::fs;

use area_matrix_core::{
    build_embedding_index, semantic_search, CoreError, SearchPagination, SearchScope,
    SemanticIndexScope, SemanticIndexStatus, SemanticSearchFallbackReason,
    SemanticSearchInputField, SemanticSearchRoute,
};
use pretty_assertions::assert_eq;

#[path = "support/semantic_search_common.rs"]
mod semantic_search_common;
use semantic_search_common::*;

#[test]
fn semantic_search_builds_index_and_returns_explainable_groups() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let invoice_id = insert_file(
        repo.path(),
        "finance/invoices/invoice-2026.pdf",
        "finance",
        Some("last month invoice paid by client"),
    );
    insert_file(repo.path(), "docs/report.txt", "docs", None);
    enable_local_semantic_search(repo.path());

    let report =
        build_embedding_index(repo_path.clone(), semantic_scope()).expect("build semantic index");
    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("semantic search");

    assert_eq!(report.status, SemanticIndexStatus::Ready);
    assert_eq!(report.total_count, 2);
    assert_eq!(report.processed_count, 2);
    assert_eq!(page.index_status, SemanticIndexStatus::Ready);
    assert_eq!(page.fallback_reason, None);
    assert_eq!(page.semantic_total_count, 1);
    assert_eq!(page.normal_total_count, 1);
    assert_eq!(page.semantic_matches[0].result.entry.id, invoice_id);
    assert_eq!(page.semantic_matches[0].route, SemanticSearchRoute::Local);
    assert_ne!(page.semantic_matches[0].relevance, 0.8);
    assert!(page.semantic_matches[0]
        .matched_reason
        .contains("file name"));
    assert!(page.semantic_matches[0].matched_reason.contains("invoice"));
    assert!(page.semantic_matches[0]
        .used_fields
        .contains(&SemanticSearchInputField::FileName));
    assert!(page.semantic_matches[0]
        .used_fields
        .contains(&SemanticSearchInputField::NoteSummary));
    assert!(page.semantic_matches[0].also_matched_normal_search);
    assert_eq!(page.normal_matches[0].deduped_by_semantic, true);
    assert_eq!(page.deduped_normal_count, 1);

    let search_log = ai_log_row(repo.path(), page.call_log_id.expect("search log id"));
    assert_eq!(search_log.0, "success");
    assert_eq!(search_log.1.as_deref(), Some("local"));
    assert!(search_log.2.contains("filename"));
    assert!(repo_config_value(repo.path(), "semantic_index_metadata").is_some());
}

#[test]
fn semantic_search_applies_filter_and_pagination_to_semantic_group() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let first = insert_file(
        repo.path(),
        "finance/invoices/invoice-alpha.txt",
        "finance",
        Some("invoice alpha"),
    );
    let second = insert_file(
        repo.path(),
        "finance/invoices/invoice-beta.txt",
        "finance",
        Some("invoice beta"),
    );
    let other = insert_file(
        repo.path(),
        "docs/invoice-out-of-scope.txt",
        "docs",
        Some("invoice other"),
    );
    insert_tag(repo.path(), first, "payable");
    insert_tag(repo.path(), second, "payable");
    insert_tag(repo.path(), other, "payable");
    enable_local_semantic_search(repo.path());

    let mut filter = default_filter();
    filter.scope = SearchScope::CurrentNode;
    filter.current_path = Some("finance/invoices".to_owned());
    filter.category = Some("finance".to_owned());
    filter.tags = vec!["payable".to_owned()];
    let report = build_embedding_index(
        repo_path.clone(),
        SemanticIndexScope {
            filter: filter.clone(),
            route: Some(SemanticSearchRoute::Local),
            privacy_policy_ref: None,
            confirmed: true,
        },
    )
    .expect("build filtered semantic index");
    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        filter,
        SearchPagination {
            limit: 1,
            offset: 1,
        },
    )
    .expect("filtered paginated semantic search");

    assert_eq!(report.total_count, 2);
    assert_eq!(report.processed_count, 2);
    assert_eq!(page.semantic_total_count, 2);
    assert_eq!(page.semantic_matches.len(), 1);
    assert_eq!(page.normal_matches.len(), 1);
    assert!(page
        .semantic_matches
        .iter()
        .all(|item| item.result.entry.category == "finance"));
    assert_ne!(page.semantic_matches[0].result.entry.id, other);
}

#[test]
fn semantic_search_indexes_limited_file_content_excerpt() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = insert_file_with_body(
        repo.path(),
        "research/semantic-body.txt",
        "research",
        None,
        "archive dossier mentions nebula reconciliation only in the file body",
    );
    enable_local_semantic_search(repo.path());

    build_embedding_index(repo_path.clone(), semantic_scope()).expect("build semantic index");
    let page = semantic_search(
        repo_path,
        "nebula".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("semantic search uses file content");

    assert_eq!(page.semantic_total_count, 1);
    let row = &page.semantic_matches[0];
    assert_eq!(row.result.entry.id, file_id);
    assert!(row
        .used_fields
        .contains(&SemanticSearchInputField::ExtractedTextExcerpt));
    assert!(row.matched_reason.contains("extracted text excerpt"));
    assert!(row.result.matches.iter().any(|matched| {
        matched.snippet.contains("nebula") && matched.start.is_some() && matched.end.is_some()
    }));
}

#[test]
fn semantic_search_privacy_rules_skip_matching_files_without_indexing_content() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");
    let private_id = insert_file_with_body(
        repo.path(),
        "finance/private/secret-invoice.txt",
        "finance",
        Some("invoice private"),
        "invoice secret private body",
    );
    let public_id = insert_file_with_body(
        repo.path(),
        "finance/public/invoice.txt",
        "finance",
        Some("invoice public"),
        "invoice public body",
    );
    save_privacy_rules(
        repo.path(),
        r#"{"rules":[{"id":"rule:folder:private-finance","type":"Folder","pattern":"finance/private","applies_to":"Local and remote AI","enabled":true}]}"#,
    );
    enable_local_semantic_search(repo.path());

    let report = build_embedding_index(repo_path.clone(), semantic_scope())
        .expect("build with privacy rule");
    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("semantic search skips private rule match");

    assert_eq!(report.status, SemanticIndexStatus::Partial);
    assert_eq!(report.total_count, 2);
    assert_eq!(report.processed_count, 1);
    assert_eq!(report.privacy_skipped_count, 1);
    assert_eq!(page.semantic_total_count, 1);
    assert_eq!(page.semantic_matches[0].result.entry.id, public_id);
    assert_ne!(page.semantic_matches[0].result.entry.id, private_id);
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn semantic_search_privacy_rules_skip_body_keyword_before_index_write() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let private_id = insert_file_with_body(
        repo.path(),
        "research/private-body.txt",
        "research",
        None,
        "quiet memo hides embargoed-nebula only inside the file body",
    );
    let public_id = insert_file_with_body(
        repo.path(),
        "research/public-body.txt",
        "research",
        None,
        "public nebula reference can enter semantic search",
    );
    save_privacy_rules(
        repo.path(),
        r#"{"rules":[{"id":"rule:keyword:embargoed-nebula","type":"Keyword","pattern":"embargoed-nebula","applies_to":"Local and remote AI","enabled":true}]}"#,
    );
    enable_local_semantic_search(repo.path());

    let report =
        build_embedding_index(repo_path.clone(), semantic_scope()).expect("build with body rule");
    let page = semantic_search(
        repo_path,
        "nebula".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("semantic search skips private body match");

    assert_eq!(report.status, SemanticIndexStatus::Partial);
    assert_eq!(report.processed_count, 1);
    assert_eq!(report.privacy_skipped_count, 1);
    assert_eq!(page.semantic_total_count, 1);
    assert_eq!(page.semantic_matches[0].result.entry.id, public_id);
    assert_ne!(page.semantic_matches[0].result.entry.id, private_id);
    let metadata = repo_config_value(repo.path(), "semantic_index_metadata")
        .expect("semantic metadata exists");
    assert!(metadata.contains("rule:keyword:embargoed-nebula"));
}

#[test]
fn semantic_search_falls_back_to_normal_search_when_index_is_not_ready() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    insert_file(repo.path(), "finance/invoice.txt", "finance", None);
    enable_local_semantic_search(repo.path());

    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("semantic fallback page");

    assert_eq!(
        page.fallback_reason,
        Some(SemanticSearchFallbackReason::SemanticIndexNotReady)
    );
    assert_eq!(page.semantic_total_count, 0);
    assert_eq!(page.normal_total_count, 1);
    assert_eq!(page.normal_matches.len(), 1);
    assert_eq!(page.normal_matches[0].deduped_by_semantic, false);
    assert!(page.call_log_id.is_some());
}

#[test]
fn semantic_search_keeps_semantic_group_when_normal_search_is_unavailable() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let invoice_id = insert_file(
        repo.path(),
        "finance/invoices/invoice-2026.txt",
        "finance",
        Some("last month invoice paid by client"),
    );
    enable_local_semantic_search(repo.path());
    build_embedding_index(repo_path.clone(), semantic_scope()).expect("build semantic index");
    open_db(repo.path())
        .execute("DROP TABLE tags", [])
        .expect("simulate normal-search metadata failure");

    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("semantic search keeps semantic results");

    assert_eq!(
        page.fallback_reason,
        Some(SemanticSearchFallbackReason::NormalSearchUnavailable)
    );
    assert_eq!(page.semantic_total_count, 1);
    assert_eq!(page.semantic_matches.len(), 1);
    assert_eq!(page.semantic_matches[0].result.entry.id, invoice_id);
    assert_eq!(page.semantic_matches[0].also_matched_normal_search, false);
    assert_eq!(page.normal_total_count, 0);
    assert!(page.normal_matches.is_empty());
    assert!(page.call_log_id.is_some());
}

#[test]
fn semantic_search_privacy_gate_skips_embedding_without_touching_user_files() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");
    insert_file(repo.path(), "finance/private-invoice.txt", "finance", None);
    save_privacy_rules(
        repo.path(),
        r#"{"rules":[{"id":"rule:keyword:private-invoice","type":"Keyword","pattern":"private-invoice","applies_to":"Local and remote AI","enabled":true}]}"#,
    );
    enable_local_semantic_search(repo.path());

    let report = build_embedding_index(repo_path.clone(), semantic_scope())
        .expect("privacy-filtered build report");
    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("privacy skip search report");

    assert_eq!(
        report.fallback_reason,
        Some(SemanticSearchFallbackReason::PrivacyRule)
    );
    assert_eq!(report.status, SemanticIndexStatus::NotReady);
    assert_eq!(report.privacy_skipped_count, 1);
    assert_eq!(
        page.fallback_reason,
        Some(SemanticSearchFallbackReason::PrivacyRule)
    );
    assert_eq!(
        page.privacy_rule_id.as_deref(),
        Some("rule:keyword:private-invoice")
    );
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README"),
        "user readme\n"
    );
    let metadata =
        repo_config_value(repo.path(), "semantic_index_metadata").expect("privacy metadata exists");
    assert!(metadata.contains("rule:keyword:private-invoice"));
}

#[test]
fn semantic_search_returns_config_for_unconfirmed_build() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    enable_local_semantic_search(repo.path());
    let mut scope = semantic_scope();
    scope.confirmed = false;

    let result = build_embedding_index(repo_path, scope);

    assert!(matches!(result, Err(CoreError::Config { .. })));
}
