use area_matrix_core::{
    get_ai_fallback_status, init_repo, AiCallLogRoute, AiCallLogStatus,
    AiCategorySuggestionSkipReason, AiFallbackAction, AiFallbackCategory, AiFallbackKind,
    AiFallbackOperation, AiFallbackProviderErrorKind, AiFallbackStatus, AiFallbackStatusRequest,
    AiPrivacyDecision, AiPrivacySkippedReason, CoreError, CoreResult, OverviewOutput, RepoInitMode,
    RepoInitOptions, SemanticSearchFallbackReason,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const AI_FALLBACK_RS: &str = include_str!("../src/ai_fallback.rs");
const AI_FALLBACK_VALIDATION_RS: &str = include_str!("../src/ai_fallback/validation.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn initialized_repo_path() -> String {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let repo_path = repo.path().to_string_lossy().into_owned();
    init_repo(
        repo_path.clone(),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo.keep().to_string_lossy().into_owned()
}

fn privacy_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::ClassificationSuggestion,
        route: None,
        provider_error: None,
        provider_error_code: None,
        privacy_decision: Some(AiPrivacyDecision::Denied),
        privacy_skipped_reason: Some(AiPrivacySkippedReason::PrivacyRule),
        category_skipped_reason: Some(AiCategorySuggestionSkipReason::PrivacyRule),
        semantic_fallback_reason: None,
        call_log_status: Some(AiCallLogStatus::Skipped),
        call_log_id: Some(7),
        privacy_rule_id: Some("rule:private-folder".to_owned()),
        retry_after: None,
    }
}

fn remote_failed_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::SemanticSearch,
        route: Some(AiCallLogRoute::Remote),
        provider_error: Some(AiFallbackProviderErrorKind::RemoteFailed),
        provider_error_code: Some("ProviderUnavailable".to_owned()),
        privacy_decision: Some(AiPrivacyDecision::Allowed),
        privacy_skipped_reason: None,
        category_skipped_reason: None,
        semantic_fallback_reason: None,
        call_log_status: Some(AiCallLogStatus::Failed),
        call_log_id: Some(8),
        privacy_rule_id: None,
        retry_after: None,
    }
}

#[test]
fn ai_fallback_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_status(_: fn(String, AiFallbackStatusRequest) -> CoreResult<AiFallbackStatus>) {}
    assert_status(get_ai_fallback_status);

    let repo_path = initialized_repo_path();
    let privacy_status =
        get_ai_fallback_status(repo_path.clone(), privacy_request()).expect("status");
    assert_eq!(privacy_status.kind, AiFallbackKind::PrivacySkipped);
    assert_eq!(privacy_status.category, AiFallbackCategory::Skipped);
    assert!(!privacy_status.retryable);
    assert_eq!(
        privacy_status.primary_action,
        Some(AiFallbackAction::ViewPrivacyRule)
    );
    assert_eq!(
        privacy_status.secondary_action,
        Some(AiFallbackAction::ViewCallLog)
    );
    assert_eq!(
        privacy_status.non_ai_fallback_action,
        AiFallbackAction::ClassifyManually
    );

    let remote_status =
        get_ai_fallback_status(repo_path.clone(), remote_failed_request()).expect("status");
    assert_eq!(remote_status.kind, AiFallbackKind::RemoteFailed);
    assert_eq!(remote_status.category, AiFallbackCategory::Error);
    assert!(remote_status.retryable);
    assert_eq!(remote_status.primary_action, Some(AiFallbackAction::Retry));
    assert_eq!(
        remote_status.non_ai_fallback_action,
        AiFallbackAction::UseNormalSearch
    );

    let semantic_index_status = get_ai_fallback_status(
        repo_path,
        AiFallbackStatusRequest {
            operation: AiFallbackOperation::EmbeddingIndexBuild,
            route: Some(AiCallLogRoute::Local),
            provider_error: None,
            provider_error_code: None,
            privacy_decision: Some(AiPrivacyDecision::Allowed),
            privacy_skipped_reason: None,
            category_skipped_reason: None,
            semantic_fallback_reason: Some(SemanticSearchFallbackReason::SemanticIndexNotReady),
            call_log_status: Some(AiCallLogStatus::Unavailable),
            call_log_id: None,
            privacy_rule_id: None,
            retry_after: None,
        },
    )
    .expect("status");
    assert_eq!(
        semantic_index_status.primary_action,
        Some(AiFallbackAction::BuildSemanticIndex)
    );
    assert_eq!(
        semantic_index_status.secondary_action,
        Some(AiFallbackAction::UseNormalSearch)
    );

    let documented_errors = [
        CoreError::config("invalid AI fallback request"),
        CoreError::permission_denied("fallback metadata unavailable"),
        CoreError::internal("fallback status resolution failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn ai_fallback_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        get_ai_fallback_status(String::new(), privacy_request()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        get_ai_fallback_status("/tmp/repo/.areamatrix".to_owned(), privacy_request()),
        Err(CoreError::Config { .. })
    ));

    let mut missing_reason = privacy_request();
    missing_reason.provider_error = None;
    missing_reason.provider_error_code = None;
    missing_reason.privacy_decision = None;
    missing_reason.privacy_skipped_reason = None;
    missing_reason.category_skipped_reason = None;
    missing_reason.semantic_fallback_reason = None;
    missing_reason.call_log_status = None;
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), missing_reason),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_log = privacy_request();
    invalid_log.call_log_id = Some(0);
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), invalid_log),
        Err(CoreError::Config { .. })
    ));

    let mut raw_secret = remote_failed_request();
    raw_secret.provider_error_code = Some("sk-secret-key-material".to_owned());
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    let mut unsafe_rule = privacy_request();
    unsafe_rule.privacy_rule_id = Some("rules/private-folder".to_owned());
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), unsafe_rule),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_retry = remote_failed_request();
    invalid_retry.retry_after = Some(-1);
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), invalid_retry),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn ai_fallback_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "AiFallbackStatus get_ai_fallback_status(",
        "string repo_path, AiFallbackStatusRequest request",
        "dictionary AiFallbackStatusRequest",
        "AiFallbackOperation operation;",
        "AiFallbackProviderErrorKind? provider_error;",
        "AiPrivacyDecision? privacy_decision;",
        "SemanticSearchFallbackReason? semantic_fallback_reason;",
        "dictionary AiFallbackStatus",
        "AiFallbackKind kind;",
        "AiFallbackCategory category;",
        "boolean retryable;",
        "AiFallbackAction non_ai_fallback_action;",
        "enum AiFallbackOperation",
        "\"ClassificationSuggestion\"",
        "\"EmbeddingIndexBuild\"",
        "enum AiFallbackKind",
        "\"PrivacySkipped\"",
        "\"SemanticIndexNotReady\"",
        "enum AiFallbackAction",
        "\"OpenLocalModelStatus\"",
        "\"UseNormalSearch\"",
        "\"ClassifyManually\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `get_ai_fallback_status(repoPath: String, request: AiFallbackStatusRequest) throws -> AiFallbackStatus`",
        "AI fallback 的 AI fallback 状态标准化入口",
        "AI fallback surface 可以从 `kind`、`category`、`title`、`message`、`retryable`",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn ai_fallback_contract_documents_consumer_state_and_safety_boundaries() {
    for fragment in [
        "Normalizes AI fallback metadata",
        "must not include raw provider output",
        "does not execute AI calls, switch providers, enable remote AI",
        "Returns `CoreError::Config { reason }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Internal { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "AI fallback status",
        "AI operation whose failure or skipped state needs standard fallback UI",
        "Standard AI fallback status returned to AI fallback surface consumers",
        "Remote AI could not be reached. Your files were not changed.",
    ] {
        assert_contains(AI_FALLBACK_RS, fragment);
    }

    for fragment in [
        "AI fallback repository path must not point inside metadata",
        "AI fallback provider error code is invalid",
        "AI fallback privacy rule id is invalid",
    ] {
        assert_contains(AI_FALLBACK_VALIDATION_RS, fragment);
    }

    for error_name in ["Config", "Internal", "PermissionDenied"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
