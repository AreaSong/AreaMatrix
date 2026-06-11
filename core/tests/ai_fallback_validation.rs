#[path = "support/ai_fallback_validation.rs"]
mod validation_support;

use std::fs;

use area_matrix_core::{
    get_ai_fallback_status, load_remote_ai_provider_config, AiCallLogRoute,
    AiCategorySuggestionSkipReason, AiFallbackAction, AiFallbackCategory, AiFallbackKind,
    AiFallbackOperation, CoreError,
};
use pretty_assertions::assert_eq;
use validation_support::{
    ai_disabled_request, assert_contains, assert_non_ai_paths_still_work, assert_secret_free,
    assert_status, initialized_repo, local_model_not_ready_request, path_string,
    privacy_skipped_request, remote_failed_request, snapshot,
};

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-49-c3-10-validation.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-10-ai-fallback.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const AI_FALLBACK_RS: &str = include_str!("../src/ai_fallback.rs");
const AI_FALLBACK_VALIDATION_RS: &str = include_str!("../src/ai_fallback/validation.rs");
const AI_FALLBACK_CALL_LOG_RS: &str = include_str!("../src/ai_fallback/call_log.rs");
const CONTRACT_TEST: &str = include_str!("ai_fallback_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("ai_fallback_implementation.rs");
const FAILURE_TEST: &str = include_str!("ai_fallback_failure_recovery.rs");

#[test]
fn ai_fallback_validation_proves_ui_ready_reason_matrix_and_non_ai_continuity() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let before = snapshot(repo.path());
    let provider_before =
        load_remote_ai_provider_config(repo_path.clone()).expect("load default provider config");

    let remote_failed =
        get_ai_fallback_status(repo_path.clone(), remote_failed_request()).expect("remote failed");
    assert_status(
        &remote_failed,
        AiFallbackKind::RemoteFailed,
        AiFallbackCategory::Error,
        Some(AiFallbackAction::Retry),
        Some(AiFallbackAction::ViewCallLog),
        AiFallbackAction::UseNormalSearch,
        true,
    );
    assert_eq!(remote_failed.route, Some(AiCallLogRoute::Remote));
    assert_secret_free(&serde_json::to_string(&remote_failed).expect("serialize fallback status"));

    let privacy =
        get_ai_fallback_status(repo_path.clone(), privacy_skipped_request()).expect("privacy skip");
    assert_status(
        &privacy,
        AiFallbackKind::PrivacySkipped,
        AiFallbackCategory::Skipped,
        Some(AiFallbackAction::ViewPrivacyRule),
        Some(AiFallbackAction::ViewCallLog),
        AiFallbackAction::ClassifyManually,
        false,
    );
    assert_eq!(
        privacy.privacy_rule_id.as_deref(),
        Some("rule:private-folder")
    );

    let disabled =
        get_ai_fallback_status(repo_path.clone(), ai_disabled_request()).expect("AI disabled");
    assert_status(
        &disabled,
        AiFallbackKind::AiDisabled,
        AiFallbackCategory::Disabled,
        Some(AiFallbackAction::OpenAiSettings),
        None,
        AiFallbackAction::UseNormalSearch,
        false,
    );

    let local_model = get_ai_fallback_status(repo_path.clone(), local_model_not_ready_request())
        .expect("local model fallback");
    assert_status(
        &local_model,
        AiFallbackKind::LocalModelNotReady,
        AiFallbackCategory::Unavailable,
        Some(AiFallbackAction::OpenLocalModelStatus),
        None,
        AiFallbackAction::UseNormalSearch,
        false,
    );
    assert_eq!(local_model.route, Some(AiCallLogRoute::Local));

    let provider_after = load_remote_ai_provider_config(repo_path.clone())
        .expect("load provider config after C3-10");
    assert_eq!(provider_after, provider_before);
    assert!(!provider_after.remote_provider_enabled);
    assert_non_ai_paths_still_work(repo.path(), repo_path);
    let after = snapshot(repo.path());
    assert_eq!(after.user_readme, before.user_readme);
    assert!(after.ai_call_log_rows >= before.ai_call_log_rows + 4);
}

#[test]
fn ai_fallback_validation_covers_failure_paths_before_metadata_writes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    get_ai_fallback_status(repo_path.clone(), remote_failed_request())
        .expect("seed valid fallback log");
    let before = snapshot(repo.path());

    let invalid_cases = [
        {
            let mut request = remote_failed_request();
            request.provider_error = None;
            request.provider_error_code = None;
            request.privacy_decision = None;
            request.call_log_status = None;
            request
        },
        {
            let mut request = privacy_skipped_request();
            request.operation = AiFallbackOperation::SemanticSearch;
            request.category_skipped_reason = Some(AiCategorySuggestionSkipReason::PrivacyRule);
            request
        },
        {
            let mut request = remote_failed_request();
            request.provider_error_code = Some("provider/raw/path".to_owned());
            request
        },
        {
            let mut request = privacy_skipped_request();
            request.privacy_rule_id = Some("sk-secret-rule".to_owned());
            request
        },
        {
            let mut request = remote_failed_request();
            request.call_log_id = Some(0);
            request
        },
        {
            let mut request = remote_failed_request();
            request.retry_after = Some(1_800_000_000);
            request
        },
    ];

    for request in invalid_cases {
        let error = get_ai_fallback_status(repo_path.clone(), request)
            .expect_err("invalid fallback request must fail");
        assert!(matches!(error, CoreError::Config { .. }));
    }

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_fallback_validation_locks_core_api_udl_rust_docs_and_existing_tests() {
    assert_task_and_docs_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_surface_alignment();
    assert_existing_c3_10_tests_are_present();
}

fn assert_task_and_docs_alignment() {
    for fragment in [
        "# 4-2/task-49: C3-10 validation",
        "为 C3-10 ai-fallback 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-2/task-49",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-10 ai-fallback",
        "计划新增：`get_ai_fallback_status`。",
        "AI operation、provider error、privacy decision。",
        "fallback kind、user message、retry ability。",
        "记录 AI call failure。",
        "AI 失败不阻断导入、普通搜索、本地规则分类。",
        "不自动切换远程 provider。",
        "UI 能展示是失败、禁用、隐私跳过还是模型不可用。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 |",
        "| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 |",
        "| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status |",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "AiFallbackStatus get_ai_fallback_status(",
        "string repo_path, AiFallbackStatusRequest request",
        "dictionary AiFallbackStatusRequest",
        "AiFallbackProviderErrorKind? provider_error;",
        "string? provider_error_code;",
        "AiPrivacyDecision? privacy_decision;",
        "AiCategorySuggestionSkipReason? category_skipped_reason;",
        "SemanticSearchFallbackReason? semantic_fallback_reason;",
        "AiCallLogStatus? call_log_status;",
        "dictionary AiFallbackStatus",
        "AiFallbackKind kind;",
        "AiFallbackCategory category;",
        "boolean retryable;",
        "AiFallbackAction? primary_action;",
        "AiFallbackAction non_ai_fallback_action;",
        "enum AiFallbackOperation",
        "\"EmbeddingIndexBuild\"",
        "enum AiFallbackKind",
        "\"LocalModelNotReady\"",
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
        "C3-10 的 AI fallback 状态标准化入口",
        "本 API 只标准化 fallback 状态；不得执行 AI、切换 provider、自动启用远程 AI",
        "自动 provider failover 不在 Stage 3",
        "S3-10 可以从 `kind`、`category`、`title`、`message`、`retryable`",
        "`Config`",
        "`PermissionDenied`",
        "`Internal`",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_surface_alignment() {
    for fragment in [
        "pub use ai_fallback::{",
        "AiFallbackAction",
        "AiFallbackCategory",
        "AiFallbackKind",
        "AiFallbackOperation",
        "AiFallbackStatusRequest",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "pub fn get_ai_fallback_status(",
        "does not execute AI calls, switch providers, enable remote AI",
        "Returns `CoreError::Config { reason }`",
        "CoreError::PermissionDenied",
        "CoreError::Internal",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "pub struct AiFallbackStatusRequest",
        "pub struct AiFallbackStatus",
        "validation::validate_request(&request)?",
        "call_log::insert_fallback_call_log",
        "AiFallbackKind::PrivacySkipped",
        "AiFallbackKind::LocalModelNotReady",
        "AiFallbackAction::UseNormalSearch",
    ] {
        assert_contains(AI_FALLBACK_RS, fragment);
    }

    for fragment in [
        "validate_repo_path",
        "validate_request",
        "AI fallback provider error code is invalid",
        "AI fallback privacy rule id is invalid",
        "looks_sensitive",
    ] {
        assert_contains(AI_FALLBACK_VALIDATION_RS, fragment);
    }

    for fragment in [
        "insert_fallback_call_log",
        "sent_fields_json: \"[]\"",
        "privacy_rule_id: status.privacy_rule_id.clone()",
        "map_metadata_error",
        "remote_provider",
        "local_model",
    ] {
        assert_contains(AI_FALLBACK_CALL_LOG_RS, fragment);
    }
}

fn assert_existing_c3_10_tests_are_present() {
    let tests = format!("{CONTRACT_TEST}\n{IMPLEMENTATION_TEST}\n{FAILURE_TEST}");
    for fragment in [
        "ai_fallback_contract_exposes_signature_inputs_outputs_and_errors",
        "ai_fallback_contract_rejects_invalid_inputs_without_fake_success",
        "ai_fallback_contract_docs_api_udl_and_control_map_stay_aligned",
        "ai_fallback_implementation_records_sanitized_failure_log_without_user_file_changes",
        "ai_fallback_implementation_records_privacy_skip_with_rule_traceability",
        "ai_fallback_implementation_keeps_existing_call_log_reference_without_duplication",
        "ai_fallback_failure_rejects_invalid_edge_inputs_before_metadata_writes",
        "ai_fallback_failure_maps_permission_denied_and_keeps_user_files_unchanged",
        "ai_fallback_failure_rolls_back_call_log_insert_when_schema_rejects_status",
        "ai_fallback_failure_rate_limit_maps_to_retry_later_without_provider_failover",
    ] {
        assert_contains(&tests, fragment);
    }
}
