use area_matrix_core::{
    search_files, write_note, CoreError, SearchDiagnosticKind, SearchIndexStatus, SearchMatchField,
    SearchMatchKind, SearchPagination, SearchScope, SearchSort, SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;

const BEYOND_PREVIOUS_ROW_LIMIT: i64 = 10_005;

#[path = "support/search_query_files.rs"]
mod search_query_files_support;

use search_query_files_support::{
    active_file_count, change_log_count, default_filter, first_page, initialized_repo,
    insert_change, insert_copied_file, insert_file, insert_many_searchable_files, insert_tag,
    open_db, path_string,
};

#[test]
fn search_query_files_implementation_finds_name_path_note_category_and_change_log() {
    let repo = initialized_repo();
    let contract_id =
        insert_copied_file(repo.path(), "docs/contracts/client-a.pdf", "docs", 100, 110);
    let invoice_id =
        insert_copied_file(repo.path(), "finance/invoice-2026.pdf", "finance", 200, 220);
    write_note(
        path_string(repo.path()),
        contract_id,
        "等待客户回签合同扫描件".to_owned(),
    )
    .expect("write searchable note");
    insert_change(
        repo.path(),
        invoice_id,
        "renamed",
        r#"{"from":"draft","to":"付款合同"}"#,
    );

    let page = search_files(
        path_string(repo.path()),
        "合同".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search files");

    assert_eq!(page.query, "合同");
    assert_eq!(page.total_count, 2);
    assert_eq!(page.index_status, SearchIndexStatus::Ready);
    assert!(page
        .results
        .iter()
        .any(|result| result.entry.id == contract_id
            && result
                .matches
                .iter()
                .any(|matched| matched.field == SearchMatchField::Note)
            && result.note_snippet.as_deref() == Some("等待客户回签合同扫描件")));
    assert!(page
        .results
        .iter()
        .any(|result| result.entry.id == invoice_id
            && result
                .matches
                .iter()
                .any(|matched| matched.field == SearchMatchField::ChangeLog)));

    let category_page = search_files(
        path_string(repo.path()),
        "finance".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search category");
    assert_eq!(category_page.total_count, 1);
    assert_eq!(category_page.results[0].entry.id, invoice_id);

    let path_page = search_files(
        path_string(repo.path()),
        "contracts".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search path");
    assert_eq!(path_page.total_count, 1);
    assert_eq!(path_page.results[0].entry.id, contract_id);
    assert!(path_page.results[0]
        .matches
        .iter()
        .any(|matched| matched.field == SearchMatchField::Path));
}

#[test]
fn search_query_files_implementation_filters_scope_tags_and_advanced_fields() {
    let repo = initialized_repo();
    let finance_id =
        insert_copied_file(repo.path(), "finance/report-2026.pdf", "finance", 300, 330);
    let docs_id = insert_copied_file(repo.path(), "docs/report-2026.md", "docs", 100, 120);
    insert_tag(repo.path(), finance_id, "urgent");

    let mut filter = default_filter();
    filter.scope = SearchScope::CurrentNode;
    filter.current_path = Some("finance".to_owned());
    filter.tags = vec!["urgent".to_owned()];
    let page = search_files(
        path_string(repo.path()),
        "report kind:pdf cat:finance tag:urgent".to_owned(),
        filter,
        SearchSort::NewestImported,
        first_page(),
    )
    .expect("search with scope and advanced fields");

    assert_eq!(page.total_count, 1);
    assert_eq!(page.results[0].entry.id, finance_id);
    assert_ne!(page.results[0].entry.id, docs_id);
}

#[test]
fn search_query_files_implementation_refreshes_results_with_full_c2_02_filter_state() {
    let repo = initialized_repo();
    let copied_finance = insert_file(
        repo.path(),
        "docs/contracts/copied-contract.pdf",
        "docs",
        "copied",
        100,
        300,
    );
    let copied_signed = insert_file(
        repo.path(),
        "docs/contracts/signed-contract.pdf",
        "docs",
        "copied",
        110,
        310,
    );
    let moved_finance = insert_file(
        repo.path(),
        "docs/contracts/moved-contract.pdf",
        "docs",
        "moved",
        120,
        320,
    );
    insert_tag(repo.path(), copied_finance, "Finance");
    insert_tag(repo.path(), copied_finance, "Signed");
    insert_tag(repo.path(), copied_signed, "Signed");
    insert_tag(repo.path(), moved_finance, "Finance");
    insert_tag(repo.path(), moved_finance, "Signed");

    let mut filter = default_filter();
    filter.scope = SearchScope::CurrentNode;
    filter.current_path = Some("docs/contracts".to_owned());
    filter.category = Some("docs".to_owned());
    filter.file_kind = Some("pdf".to_owned());
    filter.tags = vec!["finance".to_owned(), "signed".to_owned()];
    filter.tag_match_mode = SearchTagMatchMode::All;
    filter.storage_mode = Some(StorageMode::Copied);

    let all_page = search_files(
        path_string(repo.path()),
        "contract".to_owned(),
        filter.clone(),
        SearchSort::NewestImported,
        first_page(),
    )
    .expect("search with all tag and storage filters");
    assert_eq!(all_page.total_count, 1);
    assert_eq!(all_page.results[0].entry.id, copied_finance);

    filter.tag_match_mode = SearchTagMatchMode::Any;
    let any_page = search_files(
        path_string(repo.path()),
        "contract".to_owned(),
        filter.clone(),
        SearchSort::NewestImported,
        first_page(),
    )
    .expect("search refreshes after tag match mode changes");
    assert_eq!(any_page.total_count, 2);
    assert_eq!(
        any_page
            .results
            .iter()
            .map(|result| result.entry.id)
            .collect::<Vec<_>>(),
        vec![copied_signed, copied_finance]
    );

    filter.storage_mode = Some(StorageMode::Moved);
    let moved_page = search_files(
        path_string(repo.path()),
        "contract".to_owned(),
        filter,
        SearchSort::NewestImported,
        first_page(),
    )
    .expect("search refreshes after storage mode changes");
    assert_eq!(moved_page.total_count, 1);
    assert_eq!(moved_page.results[0].entry.id, moved_finance);
}

#[test]
fn search_query_files_implementation_sorts_paginates_and_returns_empty_distinctly() {
    let repo = initialized_repo();
    let older_id = insert_copied_file(repo.path(), "docs/a-report.pdf", "docs", 100, 300);
    let newer_id = insert_copied_file(repo.path(), "docs/b-report.pdf", "docs", 200, 100);

    let page = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        default_filter(),
        SearchSort::NameAsc,
        SearchPagination {
            limit: 1,
            offset: 1,
        },
    )
    .expect("search with pagination");

    assert_eq!(page.total_count, 2);
    assert_eq!(page.results.len(), 1);
    assert_eq!(page.results[0].entry.id, newer_id);

    let modified_page = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        default_filter(),
        SearchSort::NewestModified,
        first_page(),
    )
    .expect("search newest modified");
    assert_eq!(modified_page.results[0].entry.id, older_id);

    let empty_page = search_files(
        path_string(repo.path()),
        "missing".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search empty result");
    assert_eq!(empty_page.total_count, 0);
    assert!(empty_page.results.is_empty());
    assert!(empty_page.diagnostics.is_empty());
}

#[test]
fn search_query_files_implementation_reports_query_parse_errors_without_db_or_fs_writes() {
    let repo = initialized_repo();
    let file_id = insert_copied_file(repo.path(), "docs/report.pdf", "docs", 100, 100);
    let before_files = active_file_count(repo.path());
    let before_changes = change_log_count(repo.path());

    let page = search_files(
        path_string(repo.path()),
        "kindd:pdf after:2026-13-01 (".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("parse query errors");

    assert_eq!(page.total_count, 0);
    assert!(page.results.is_empty());
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::UnknownField));
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::InvalidDate));
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::UnbalancedParentheses));
    assert_eq!(active_file_count(repo.path()), before_files);
    assert_eq!(change_log_count(repo.path()), before_changes);
    let remaining_id: i64 = open_db(repo.path())
        .query_row("SELECT id FROM files WHERE status = 'active'", [], |row| {
            row.get(0)
        })
        .expect("read remaining file id");
    assert_eq!(remaining_id, file_id);
}

#[test]
fn search_query_files_implementation_maps_uninitialized_repo_to_declared_db_error() {
    let repo = tempfile::tempdir().expect("create uninitialized temporary repository directory");

    let result = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
}

#[test]
fn search_query_files_implementation_rejects_invalid_scope_path() {
    let repo = initialized_repo();
    let mut filter = default_filter();
    filter.scope = SearchScope::CurrentNode;
    filter.current_path = Some("../outside".to_owned());

    let result = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        filter,
        SearchSort::Relevance,
        first_page(),
    );

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));
}

#[test]
fn search_query_files_implementation_total_count_is_not_capped_at_previous_candidate_limit() {
    let repo = initialized_repo();
    insert_many_searchable_files(repo.path(), BEYOND_PREVIOUS_ROW_LIMIT);

    let page = search_files(
        path_string(repo.path()),
        "contract".to_owned(),
        default_filter(),
        SearchSort::NewestImported,
        SearchPagination {
            limit: 5,
            offset: 10_000,
        },
    )
    .expect("search beyond previous candidate row cap");

    assert_eq!(page.total_count, BEYOND_PREVIOUS_ROW_LIMIT);
    assert_eq!(page.results.len(), 5);
    assert_eq!(page.results[0].entry.current_name, "contract-00004.txt");
    assert_eq!(page.results[4].entry.current_name, "contract-00000.txt");
}

#[test]
fn search_query_files_implementation_marks_fuzzy_and_initials_matches() {
    let repo = initialized_repo();
    let fuzzy_id = insert_copied_file(repo.path(), "docs/invoice.pdf", "docs", 100, 100);
    let initials_id = insert_copied_file(repo.path(), "docs/quarterly-total.pdf", "docs", 110, 110);
    let pinyin_id = insert_copied_file(repo.path(), "docs/合同-草案.pdf", "docs", 120, 120);

    let fuzzy_page = search_files(
        path_string(repo.path()),
        "invocie".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search fuzzy");
    assert_eq!(fuzzy_page.results[0].entry.id, fuzzy_id);
    assert_eq!(
        fuzzy_page.results[0].matches[0].kind,
        SearchMatchKind::Fuzzy
    );

    let initials_page = search_files(
        path_string(repo.path()),
        "qt".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search initials");
    assert_eq!(initials_page.results[0].entry.id, initials_id);
    assert_eq!(
        initials_page.results[0].matches[0].kind,
        SearchMatchKind::PinyinInitials
    );

    let pinyin_page = search_files(
        path_string(repo.path()),
        "ht".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search pinyin initials");
    assert_eq!(pinyin_page.results[0].entry.id, pinyin_id);
    assert_eq!(
        pinyin_page.results[0].matches[0].kind,
        SearchMatchKind::PinyinInitials
    );
}
