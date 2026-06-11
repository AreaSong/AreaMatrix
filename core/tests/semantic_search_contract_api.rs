use area_matrix_core::{
    build_embedding_index, semantic_search, CoreError, CoreResult, FileEntry, FileOrigin,
    SearchFileResult, SearchFilter, SearchIndexStatus, SearchMatch, SearchMatchField,
    SearchMatchKind, SearchPagination, SearchScope, SearchTagMatchMode, SemanticIndexBuildReport,
    SemanticIndexScope, SemanticIndexStatus, SemanticNormalSearchMatch,
    SemanticSearchFallbackReason, SemanticSearchInputField, SemanticSearchMatch,
    SemanticSearchResultPage, SemanticSearchRoute, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-36-c3-08-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-08-semantic-search.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const SEMANTIC_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-08-semantic-search-results.md");
const FALLBACK_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-10-ai-fallback.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const SEMANTIC_RS: &str = include_str!("../src/semantic_search.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected text not to contain `{needle}`"
    );
}

fn filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: Some("finance".to_owned()),
        file_kind: Some("pdf".to_owned()),
        tags: vec!["invoice".to_owned()],
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: Some(StorageMode::Copied),
        include_deleted: Some(false),
    }
}

fn current_node_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::CurrentNode,
        current_path: Some("finance/invoices".to_owned()),
        ..filter()
    }
}

fn pagination() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

fn search_result() -> SearchFileResult {
    SearchFileResult {
        entry: FileEntry {
            id: 42,
            path: "finance/invoices/invoice_0426.pdf".to_owned(),
            original_name: "invoice_0426.pdf".to_owned(),
            current_name: "invoice_0426.pdf".to_owned(),
            category: "finance".to_owned(),
            size_bytes: 2048,
            hash_sha256: "hash".to_owned(),
            storage_mode: StorageMode::Copied,
            origin: FileOrigin::Imported,
            source_path: None,
            availability_status: area_matrix_core::FileAvailabilityStatus::Available,
            imported_at: 1_777_300_000,
            updated_at: 1_777_300_900,
        },
        score: 0.91,
        matches: vec![SearchMatch {
            field: SearchMatchField::Name,
            kind: SearchMatchKind::Exact,
            snippet: "invoice_0426.pdf".to_owned(),
            start: Some(0),
            end: Some(7),
        }],
        note_snippet: Some("last month invoice".to_owned()),
    }
}

fn index_scope() -> SemanticIndexScope {
    SemanticIndexScope {
        filter: current_node_filter(),
        route: Some(SemanticSearchRoute::Local),
        privacy_policy_ref: Some("default-remote-gate".to_owned()),
        confirmed: true,
    }
}

#[test]
fn semantic_search_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_search(
        _: fn(
            String,
            String,
            SearchFilter,
            SearchPagination,
        ) -> CoreResult<SemanticSearchResultPage>,
    ) {
    }
    fn assert_build(_: fn(String, SemanticIndexScope) -> CoreResult<SemanticIndexBuildReport>) {}
    assert_search(semantic_search);
    assert_build(build_embedding_index);

    let semantic_row = SemanticSearchMatch {
        result: search_result(),
        relevance: 0.91,
        matched_reason: "filename and AI summary match invoice".to_owned(),
        used_fields: vec![
            SemanticSearchInputField::FileName,
            SemanticSearchInputField::AiSummary,
        ],
        route: SemanticSearchRoute::Local,
        also_matched_normal_search: true,
        call_log_id: Some(7),
        privacy_rule_id: None,
    };
    let normal_row = SemanticNormalSearchMatch {
        result: search_result(),
        deduped_by_semantic: true,
    };
    let page = SemanticSearchResultPage {
        query: "last month invoice".to_owned(),
        semantic_total_count: 1,
        normal_total_count: 1,
        semantic_matches: vec![semantic_row],
        normal_matches: vec![normal_row],
        deduped_normal_count: 1,
        index_status: SemanticIndexStatus::Ready,
        route: Some(SemanticSearchRoute::Local),
        fallback_reason: None,
        fallback_message: None,
        call_log_id: Some(7),
        privacy_rule_id: None,
        low_confidence: false,
    };
    assert_eq!(page.semantic_total_count, 1);
    assert_eq!(page.normal_total_count, 1);
    assert_eq!(page.semantic_matches[0].relevance, 0.91);
    assert!(page.semantic_matches[0].also_matched_normal_search);
    assert!(page.normal_matches[0].deduped_by_semantic);

    let fallback = SemanticSearchResultPage {
        query: "last month invoice".to_owned(),
        semantic_total_count: 0,
        normal_total_count: 3,
        semantic_matches: Vec::new(),
        normal_matches: Vec::new(),
        deduped_normal_count: 0,
        index_status: SemanticIndexStatus::NotReady,
        route: None,
        fallback_reason: Some(SemanticSearchFallbackReason::SemanticIndexNotReady),
        fallback_message: Some("Semantic index is not ready".to_owned()),
        call_log_id: Some(8),
        privacy_rule_id: None,
        low_confidence: false,
    };
    assert_eq!(
        fallback.fallback_reason,
        Some(SemanticSearchFallbackReason::SemanticIndexNotReady)
    );

    let build_report = SemanticIndexBuildReport {
        status: SemanticIndexStatus::Building,
        route: Some(SemanticSearchRoute::Local),
        total_count: 20,
        processed_count: 0,
        skipped_count: 2,
        failed_count: 0,
        privacy_skipped_count: 2,
        provider_name: Some("Local embedding model".to_owned()),
        call_log_id: Some(9),
        fallback_reason: None,
        message: Some("Semantic index build started".to_owned()),
    };
    assert_eq!(build_report.status, SemanticIndexStatus::Building);
    assert_eq!(build_report.privacy_skipped_count, 2);

    let documented_errors = [
        CoreError::config("invalid semantic search request"),
        CoreError::permission_denied("semantic metadata unavailable"),
        CoreError::db("semantic index metadata unavailable"),
        CoreError::internal("semantic runtime unavailable"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn semantic_search_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        semantic_search(String::new(), "invoice".to_owned(), filter(), pagination()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        semantic_search(
            "/tmp/repo".to_owned(),
            " ".to_owned(),
            filter(),
            pagination()
        ),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_filter = filter();
    invalid_filter.current_path = Some("../private".to_owned());
    assert!(matches!(
        semantic_search(
            "/tmp/repo".to_owned(),
            "invoice".to_owned(),
            invalid_filter,
            pagination()
        ),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_pagination = pagination();
    invalid_pagination.limit = 0;
    assert!(matches!(
        semantic_search(
            "/tmp/repo".to_owned(),
            "invoice".to_owned(),
            filter(),
            invalid_pagination
        ),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        semantic_search(
            "/tmp/repo".to_owned(),
            "invoice".to_owned(),
            filter(),
            pagination()
        ),
        Err(CoreError::Db { .. })
    ));

    let mut missing_confirmation = index_scope();
    missing_confirmation.confirmed = false;
    assert!(matches!(
        build_embedding_index("/tmp/repo".to_owned(), missing_confirmation),
        Err(CoreError::Config { .. })
    ));

    let mut raw_secret = index_scope();
    raw_secret.privacy_policy_ref = Some("sk-secret-key-material".to_owned());
    assert!(matches!(
        build_embedding_index("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        build_embedding_index("/tmp/repo".to_owned(), index_scope()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn semantic_search_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-36: C3-08 contract-api",
        "为 C3-08 semantic-search 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-08 semantic-search",
        "- S3-08 semantic-search-results",
        "计划新增：`semantic_search(repo_path, query, filter, pagination) -> SemanticSearchResultPage`",
        "计划新增：`build_embedding_index(repo_path, scope)`",
        "自然语言 query、filter、embedding index scope。",
        "语义搜索结果、score、matched reason、fallback 状态。",
        "普通搜索引用数据或 fallback hint",
        "- `Config`",
        "- `Db`",
        "- `PermissionDenied`",
        "- `Internal`",
        "普通搜索失败不依赖语义搜索。",
        "隐私规则阻止的文件不进入 embedding。",
        "provider 失败时能回退到普通搜索。",
        "Core 不生成不可解释的单一混合分数。",
        "OCR embedding 和跨设备 embedding sync 属于 Stage 4+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 | semantic search / embedding | embedding metadata, ai_call_log |",
        "| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log |",
        "AI 默认关闭，本地优先。",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "SemanticSearchResultPage semantic_search(",
        "string repo_path,",
        "string query,",
        "SearchFilter filter,",
        "SearchPagination pagination",
        "SemanticIndexBuildReport build_embedding_index(",
        "string repo_path, SemanticIndexScope scope",
        "dictionary SemanticSearchMatch",
        "f32 relevance;",
        "string matched_reason;",
        "sequence<SemanticSearchInputField> used_fields;",
        "boolean also_matched_normal_search;",
        "dictionary SemanticNormalSearchMatch",
        "boolean deduped_by_semantic;",
        "dictionary SemanticSearchResultPage",
        "i64 semantic_total_count;",
        "i64 normal_total_count;",
        "sequence<SemanticSearchMatch> semantic_matches;",
        "sequence<SemanticNormalSearchMatch> normal_matches;",
        "SemanticIndexStatus index_status;",
        "SemanticSearchFallbackReason? fallback_reason;",
        "dictionary SemanticIndexScope",
        "SearchFilter filter;",
        "boolean confirmed;",
        "dictionary SemanticIndexBuildReport",
        "i64 privacy_skipped_count;",
        "enum SemanticSearchRoute { \"Local\", \"Remote\" };",
        "enum SemanticSearchInputField",
        "\"AiSummary\"",
        "enum SemanticIndexStatus",
        "\"NotReady\"",
        "\"Partial\"",
        "enum SemanticSearchFallbackReason",
        "\"SemanticIndexNotReady\"",
        "\"NormalSearchUnavailable\"",
        "\"RateLimited\"",
        "\"Timeout\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_not_contains(
        CAPABILITY_SPEC,
        "semantic_search(repo_path, query, filter, pagination) -> SearchResultPage",
    );

    for fragment in [
        "| `semantic_search(repo, query, filter, pagination)` | ai/search | √ | Config / PermissionDenied / Db / Internal |",
        "| `build_embedding_index(repo, scope)` | ai/search | √ | Config / PermissionDenied / Db / Internal |",
        "### `semantic_search(repoPath: String, query: String, filter: SearchFilter, pagination: SearchPagination) throws -> SemanticSearchResultPage`",
        "### `build_embedding_index(repoPath: String, scope: SemanticIndexScope) throws -> SemanticIndexBuildReport`",
        "C3-08 的语义搜索入口",
        "`S3-08 semantic-search-results`",
        "`S3-10 ai-fallback`",
        "`Semantic matches` / `Normal search matches`",
        "`RateLimited` 或 `Timeout`",
        "本 API 不创建或刷新 embedding index",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Db", "Internal"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn semantic_search_contract_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "语义模式默认同时请求 semantic search API 和 Stage 2 normal search API",
        "第一组固定为 `Semantic matches`",
        "第二组固定为 `Normal search matches`",
        "如果同一文件同时出现在两组，默认只在 `Semantic matches` 显示一次",
        "AI 总开关关闭：显示 fallback",
        "语义索引未建立：显示 `Semantic index is not ready`",
        "Build semantic index` 前必须检查 AI 总开关、语义搜索功能开关、provider 状态",
        "隐私跳过必须写入 S3-05 调用日志，sent fields 为 none。",
    ] {
        assert_contains(SEMANTIC_PAGE, fragment);
    }

    for fragment in [
        "Semantic search is unavailable",
        "Semantic index is not ready yet.",
        "`semantic_index_not_ready`",
        "`rate_limited`",
        "`timeout`",
        "`Build semantic index`",
        "`Use normal search`",
        "Retry 只重试同一 provider、同一 model、同一 feature scope 和同一输入快照",
    ] {
        assert_contains(FALLBACK_PAGE, fragment);
    }

    for fragment in [
        "C3-08 semantic search contract types and entry points",
        "pub enum SemanticSearchRoute",
        "pub enum SemanticSearchInputField",
        "pub enum SemanticIndexStatus",
        "pub enum SemanticSearchFallbackReason",
        "RateLimited",
        "Timeout",
        "pub struct SemanticSearchMatch",
        "pub struct SemanticNormalSearchMatch",
        "pub struct SemanticSearchResultPage",
        "pub struct SemanticIndexScope",
        "pub struct SemanticIndexBuildReport",
        "pub fn semantic_search(",
        "pub fn build_embedding_index(",
        "validate_index_scope",
        "looks_sensitive",
    ] {
        assert_contains(SEMANTIC_RS, fragment);
    }

    for fragment in [
        "pub use semantic_search::{",
        "semantic_search, SemanticIndexBuildReport",
        "SemanticSearchFallbackReason",
        "SemanticSearchResultPage",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for forbidden in [
        "execute_remote",
        "enable_remote_ai_provider(",
        "update_ai_config(",
        "save_ai_summary(",
        "apply_ai_tag_suggestions(",
        "import_file(",
        "delete_file(",
        "move_to_category(",
    ] {
        assert!(
            !SEMANTIC_RS.contains(forbidden),
            "C3-08 contract must not implement adjacent capability `{forbidden}`"
        );
    }

    for fragment in ["SemanticSearch", "semantic_search"] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    let normal_status = SearchIndexStatus::Ready;
    assert_eq!(normal_status, SearchIndexStatus::Ready);

    let fallback_reasons = [
        SemanticSearchFallbackReason::SemanticIndexNotReady,
        SemanticSearchFallbackReason::RateLimited,
        SemanticSearchFallbackReason::Timeout,
    ];
    assert_eq!(fallback_reasons.len(), 3);
}
