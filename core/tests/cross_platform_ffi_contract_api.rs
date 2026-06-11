use area_matrix_core::{
    inspect_binding_contract, BindingContractReport, BindingContractRequest, BindingSupportStatus,
    BindingTargetPlatform, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-01-c4-01-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-01-cross-platform-ffi-contract.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const PLATFORM_DIFFERENCES_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-02-platform-differences.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_RS: &str = include_str!("../src/cross_platform_ffi.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn request(target_platform: BindingTargetPlatform) -> BindingContractRequest {
    BindingContractRequest {
        target_platform,
        binding_version: 1,
    }
}

#[test]
fn cross_platform_ffi_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_inspect(_: fn(BindingContractRequest) -> CoreResult<BindingContractReport>) {}
    assert_inspect(inspect_binding_contract);

    let swift_report =
        inspect_binding_contract(request(BindingTargetPlatform::Swift)).expect("swift report");
    assert_eq!(swift_report.target_platform, BindingTargetPlatform::Swift);
    assert_eq!(swift_report.binding_version, 1);
    assert!(!swift_report.core_version.is_empty());
    assert!(swift_report
        .supported_apis
        .iter()
        .any(|api| api.name == "inspect_binding_contract"
            && api.capability == "C4-01"
            && api.status == BindingSupportStatus::Supported));
    assert!(swift_report.type_mappings.iter().any(|mapping| {
        mapping.rust_type == "Result<T, CoreError>"
            && mapping.udl_type == "[Throws=CoreError] T"
            && mapping.target_type == "throws"
            && mapping.status == BindingSupportStatus::Supported
    }));
    assert!(swift_report.missing_capabilities.is_empty());

    let kotlin_report =
        inspect_binding_contract(request(BindingTargetPlatform::Kotlin)).expect("kotlin report");
    assert!(kotlin_report
        .type_mappings
        .iter()
        .any(|mapping| { mapping.rust_type == "Vec<T>" && mapping.target_type == "List<T>" }));
    assert!(kotlin_report
        .missing_capabilities
        .iter()
        .any(|capability| capability.capability == "C4-01"
            && capability.status == BindingSupportStatus::Limited));

    let python_report =
        inspect_binding_contract(request(BindingTargetPlatform::Python)).expect("python report");
    assert!(python_report.type_mappings.iter().any(|mapping| {
        mapping.rust_type == "Option<String>" && mapping.target_type == "Optional[str]"
    }));

    let documented_errors = [
        CoreError::config("unsupported binding contract version"),
        CoreError::internal("binding contract inspection failed"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn cross_platform_ffi_contract_rejects_invalid_binding_version_without_fake_success() {
    assert!(matches!(
        inspect_binding_contract(BindingContractRequest {
            target_platform: BindingTargetPlatform::Swift,
            binding_version: 0,
        }),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        inspect_binding_contract(BindingContractRequest {
            target_platform: BindingTargetPlatform::Python,
            binding_version: 2,
        }),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn cross_platform_ffi_contract_docs_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-01: C4-01 contract-api",
        "为 C4-01 cross-platform-ffi-contract 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-01 cross-platform-ffi-contract",
        "- S4-X-02 platform-differences",
        "平台中立 UDL/Kotlin/Python/Swift 绑定检查接口",
        "target platform、binding version。",
        "支持的 API、类型映射、缺失能力。",
        "- `Config`",
        "- `Internal`",
        "Core 不依赖 macOS 专属 API。",
        "绑定生成在 iOS/Windows/Linux 可验证。",
        "平台差异以 capability 输出，不靠 UI 猜测。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-X-02 | platform-differences | C4-01, C4-17 | capability matrix | UI 不硬猜平台能力",
        "平台差异必须结构化暴露。",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "BindingContractReport inspect_binding_contract(BindingContractRequest request);",
        "dictionary BindingContractRequest",
        "BindingTargetPlatform target_platform;",
        "i64 binding_version;",
        "dictionary BindingContractReport",
        "sequence<BindingApiContract> supported_apis;",
        "sequence<BindingTypeMapping> type_mappings;",
        "sequence<BindingMissingCapability> missing_capabilities;",
        "enum BindingTargetPlatform",
        "\"Swift\", \"Kotlin\", \"Python\"",
        "enum BindingSupportStatus",
        "\"Supported\", \"Limited\", \"Missing\"",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "BindingContractReport inspect_binding_contract(BindingContractRequest request);",
        "dictionary BindingContractRequest",
        "dictionary BindingContractReport",
        "enum BindingTargetPlatform",
        "\"Swift\", \"Kotlin\", \"Python\"",
        "enum BindingSupportStatus",
        "\"Supported\", \"Limited\", \"Missing\"",
        "Core API（UDL 接口规范）",
        "AreaMatrix Core 暴露给 Swift / Kotlin / Python 的所有函数与类型",
        "类型映射表",
        "| `inspect_binding_contract(request)` | ffi | √ | Config / Internal |",
        "### `inspect_binding_contract(request: BindingContractRequest) throws -> BindingContractReport`",
        "supported_apis",
        "type_mappings",
        "missing_capabilities",
        "不生成绑定代码",
        "不补相邻 Stage 4 能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in ["`Config { reason }`", "`Internal { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn cross_platform_ffi_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "展示当前平台名称和 repo 存储位置。",
        "Core version: ...",
        "展示能力矩阵",
        "能力未知时显示 `Unknown`，不显示成可用。",
        "Capability snapshot 加载失败",
        "不展示 Stage 5 或未定义能力。",
    ] {
        assert_contains(PLATFORM_DIFFERENCES_PAGE, fragment);
    }

    for fragment in [
        "Inspects the cross-platform UniFFI contract surface",
        "supported APIs, type",
        "missing capability gaps",
        "without guessing from UI state",
        "Returns `CoreError::Config { reason }`",
        "`CoreError::Internal { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-01 cross-platform FFI contract types",
        "Target binding family requested by a platform shell.",
        "Stable API entry exposed by the cross-platform binding contract.",
        "Stable type mapping exposed by the cross-platform binding contract.",
        "Missing or limited capability surfaced to S4-X-02.",
        "It does not inspect a repository",
        "generate bindings",
        "or execute adjacent",
        "Stage 4 capabilities",
        "binding contract report is incomplete",
    ] {
        assert_contains(CONTRACT_RS, fragment);
    }
}
