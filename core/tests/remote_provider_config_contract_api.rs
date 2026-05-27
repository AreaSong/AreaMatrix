use area_matrix_core::{
    enable_remote_ai_provider, test_remote_ai_provider, AiFeatureKind, CoreError, CoreResult,
    RemoteAiProviderKind, RemoteProviderConfigSnapshot, RemoteProviderEnableRequest,
    RemoteProviderTestRequest, RemoteProviderTestResult, RemoteProviderTestStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-11-c3-03-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-03-remote-provider-config.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const REMOTE_MODEL_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-03-remote-model-enable.md");
const AI_PRIVACY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-09-ai-privacy-rules.md");
const STAGE_3_INDEX: &str = include_str!("../../docs/ux/page-specs/stage-3-ai.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const REMOTE_PROVIDER_RS: &str = include_str!("../src/remote_provider_config.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn test_request() -> RemoteProviderTestRequest {
    RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::OpenAi,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: None,
        key_reference: "keychain:areamatrix-remote-openai".to_owned(),
    }
}

fn enable_request() -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: RemoteAiProviderKind::OpenAi,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: None,
        key_reference: "keychain:areamatrix-remote-openai".to_owned(),
        feature_scope: vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags],
        verification_token: "verify:remote-openai:001".to_owned(),
        data_flow_confirmed: true,
    }
}

#[test]
fn remote_provider_config_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_test(
        _: fn(String, RemoteProviderTestRequest) -> CoreResult<RemoteProviderTestResult>,
    ) {
    }
    fn assert_enable(
        _: fn(String, RemoteProviderEnableRequest) -> CoreResult<RemoteProviderConfigSnapshot>,
    ) {
    }

    assert_test(test_remote_ai_provider);
    assert_enable(enable_remote_ai_provider);

    let result = RemoteProviderTestResult {
        provider: RemoteAiProviderKind::OpenAi,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: None,
        status: RemoteProviderTestStatus::Succeeded,
        provider_verified: true,
        verification_token: Some("verify:remote-openai:001".to_owned()),
        sanitized_message: "Connection verified".to_owned(),
    };
    assert_eq!(result.status, RemoteProviderTestStatus::Succeeded);
    assert!(result.provider_verified);
    assert_eq!(
        result.verification_token.as_deref(),
        Some("verify:remote-openai:001")
    );

    let snapshot = RemoteProviderConfigSnapshot {
        provider_configured: true,
        provider_verified: true,
        remote_provider_enabled: true,
        provider: Some(RemoteAiProviderKind::OpenAi),
        model_id: Some("gpt-4.1-mini".to_owned()),
        endpoint_url: None,
        credential_configured: true,
        feature_scope: vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags],
        updated_at: Some(1_777_300_800),
        disabled_reason: None,
    };
    assert!(snapshot.provider_configured);
    assert!(snapshot.provider_verified);
    assert!(snapshot.remote_provider_enabled);
    assert!(snapshot.credential_configured);
    assert_eq!(snapshot.feature_scope.len(), 2);

    let documented_errors = [
        CoreError::config("invalid remote provider settings"),
        CoreError::permission_denied("credential unavailable"),
        CoreError::internal("provider runtime unavailable"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn remote_provider_config_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        test_remote_ai_provider(String::new(), test_request()),
        Err(CoreError::Config { .. })
    ));

    let mut raw_secret = test_request();
    raw_secret.key_reference = "sk-secret-key-material".to_owned();
    assert!(matches!(
        test_remote_ai_provider("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    let mut missing_endpoint = test_request();
    missing_endpoint.provider = RemoteAiProviderKind::Other;
    assert!(matches!(
        test_remote_ai_provider("/tmp/repo".to_owned(), missing_endpoint),
        Err(CoreError::Config { .. })
    ));

    let mut managed_endpoint = test_request();
    managed_endpoint.endpoint_url = Some("https://api.example.test".to_owned());
    assert!(matches!(
        test_remote_ai_provider("/tmp/repo".to_owned(), managed_endpoint),
        Err(CoreError::Config { .. })
    ));

    let mut empty_scope = enable_request();
    empty_scope.feature_scope.clear();
    assert!(matches!(
        enable_remote_ai_provider("/tmp/repo".to_owned(), empty_scope),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_scope = enable_request();
    duplicate_scope
        .feature_scope
        .push(AiFeatureKind::AutoSummaries);
    assert!(matches!(
        enable_remote_ai_provider("/tmp/repo".to_owned(), duplicate_scope),
        Err(CoreError::Config { .. })
    ));

    let mut no_consent = enable_request();
    no_consent.data_flow_confirmed = false;
    assert!(matches!(
        enable_remote_ai_provider("/tmp/repo".to_owned(), no_consent),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn remote_provider_config_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-11: C3-03 contract-api",
        "为 C3-03 remote-provider-config 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-03 remote-provider-config",
        "- S3-03 remote-model-enable",
        "- S3-09 ai-privacy-rules",
        "计划新增：`test_remote_ai_provider`、`enable_remote_ai_provider`",
        "provider、model、key reference、allowed scopes。",
        "provider_configured",
        "provider_verified",
        "remote_provider_enabled",
        "feature_scope",
        "保存 provider metadata 和 scope，不保存 key 明文。",
        "key 进入 Keychain 或平台安全存储。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Internal`",
        "远程 provider 必须显式测试和确认数据流向后启用。",
        "API key 不进入日志、诊断、错误文案。",
        "本地模型失败不得自动启用远程 provider。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-03 | remote-model-enable | C3-03, C3-09 | provider test/enable | provider metadata, Keychain ref",
        "| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate",
        "AI 默认关闭，本地优先。",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "RemoteProviderTestResult test_remote_ai_provider(",
        "string repo_path, RemoteProviderTestRequest request",
        "RemoteProviderConfigSnapshot enable_remote_ai_provider(",
        "string repo_path, RemoteProviderEnableRequest request",
        "dictionary RemoteProviderTestRequest",
        "RemoteAiProviderKind provider;",
        "string key_reference;",
        "dictionary RemoteProviderEnableRequest",
        "sequence<AiFeatureKind> feature_scope;",
        "boolean data_flow_confirmed;",
        "dictionary RemoteProviderConfigSnapshot",
        "boolean provider_configured;",
        "boolean provider_verified;",
        "boolean remote_provider_enabled;",
        "boolean credential_configured;",
        "dictionary RemoteProviderTestResult",
        "RemoteProviderTestStatus status;",
        "string sanitized_message;",
        "enum RemoteAiProviderKind",
        "\"OpenAi\"",
        "\"Anthropic\"",
        "\"Other\"",
        "enum RemoteProviderTestStatus",
        "\"Succeeded\"",
        "\"ProviderRejected\"",
        "\"ConnectionFailed\"",
        "\"UnsupportedProvider\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `test_remote_ai_provider(repo, request)` | ai | √ | Config / PermissionDenied / Internal |",
        "| `enable_remote_ai_provider(repo, request)` | ai | √ | Config / PermissionDenied / Internal |",
        "### `test_remote_ai_provider(repoPath: String, request: RemoteProviderTestRequest) throws -> RemoteProviderTestResult`",
        "### `enable_remote_ai_provider(repoPath: String, request: RemoteProviderEnableRequest) throws -> RemoteProviderConfigSnapshot`",
        "不接受 API key 明文",
        "不得发送文件名、repo-relative path、提取文本",
        "只保存远程 provider metadata、Keychain reference 和 scope",
        "privacy_gate_enabled` 由 C3-09 管理",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Internal"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn remote_provider_config_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "选择远程 provider。",
        "输入 API key，并保存到 Keychain。",
        "选择使用范围：分类、摘要、标签、语义搜索。",
        "测试连接，且测试不发送用户文件内容。",
        "provider_configured",
        "provider_verified",
        "remote_provider_enabled",
        "feature_scope",
        "privacy_gate_enabled",
        "远程调用允许条件固定为",
        "Test connection 只发送 provider/model/key 可用性的最小探测请求",
        "点击 `Enable remote AI` 成功后必须一次性保存",
        "所有字段类型都受隐私规则 gate 约束。",
    ] {
        assert_contains(REMOTE_MODEL_PAGE, fragment);
    }

    for fragment in [
        "provider_configured",
        "provider_verified",
        "remote_provider_enabled",
        "feature_scope",
        "privacy_gate_enabled",
        "本区是隐私 gate，不是 provider 禁用页",
        "Block remote AI with privacy gate` 不得被实现为 S3-03 的 `Disable remote AI`",
        "`feature_scope` 不包含某 AI 功能",
    ] {
        assert_contains(AI_PRIVACY_PAGE, fragment);
    }

    for fragment in [
        "AI 默认关闭；本地模型为默认推荐路径。",
        "远程模型必须由用户显式配置 key、选择使用范围、测试连接成功并确认数据流向后启用",
        "API key 只允许存入 Keychain",
        "AI 失败不得自动切换远程 provider；本地模型失败不得自动启用远程 AI。",
    ] {
        assert_contains(STAGE_3_INDEX, fragment);
    }

    assert_contains(
        REMOTE_PROVIDER_RS,
        "C3-03 remote provider configuration contract types",
    );
    for fragment in [
        "API keys are never returned",
        "validate_feature_scope",
        "validate_verification_token",
        "looks_sensitive",
    ] {
        assert_contains(REMOTE_PROVIDER_RS, fragment);
    }

    for fragment in [
        "Tests a C3-03 remote AI provider without sending user file content.",
        "Core must never accept or return raw API keys",
        "Enables a C3-03 remote AI provider after successful test and consent.",
        "C3-09 remains responsible for",
    ] {
        assert_contains(API_RS, fragment);
    }
}
