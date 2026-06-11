use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, validate_repo_path, CoreError, CoreResult, OverviewOutput, RepoConfig,
    RepoInitMode, RepoInitOptions, RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-06-c4-02-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-02-mobile-repo-connect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const CONNECT_REPO_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-01-connect-repo.md");
const INIT_CONFIRM_PAGE: &str = include_str!(
    "../../docs/ux/page-specs/stage-4-multiplatform/S4-X-04-repository-init-confirm.md"
);
const ADOPT_CONFIRM_PAGE: &str = include_str!(
    "../../docs/ux/page-specs/stage-4-multiplatform/S4-X-05-repository-adopt-confirm.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn mobile_repo_connect_contract_exports_documented_signatures_and_errors() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);
    assert_load_config(load_config);

    let errors = [
        CoreError::permission_denied("permission denied"),
        CoreError::invalid_path("invalid path"),
        CoreError::icloud_placeholder("icloud placeholder"),
    ];
    assert_eq!(errors.len(), 3);
}

#[test]
fn mobile_repo_connect_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "# 4-3/task-06: C4-02 contract-api",
        "为 C4-02 mobile-repo-connect 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-02 mobile-repo-connect",
        "- S4-IOS-01 connect-repo",
        "- S4-X-04 repository-init-confirm",
        "- S4-X-05 repository-adopt-confirm",
        "- `validate_repo_path`",
        "- `init_repo`",
        "- `load_config`",
        "iOS security-scoped URL / provider path",
        "repo connection status 和推荐初始化/接管模式",
        "由平台层申请权限；Core 只处理授权后的路径。",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "- `ICloudPlaceholder`",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-01 | connect-repo | C4-02, C4-08 | repo validate/init/adopt | iOS security-scoped URL",
        "| S4-X-04 | repository-init-confirm | C4-02, C4-09, C4-10 | init confirm | 不绕过确认",
        "| S4-X-05 | repository-adopt-confirm | C4-02, C4-09, C4-10 | adopt confirm | 不移动/删除/覆盖用户文件",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfig load_config(string repo_path);",
        "dictionary RepoPathValidation",
        "RepoInitMode? recommended_mode;",
        "sequence<RepoPathIssue> issues;",
        "dictionary RepoInitOptions",
        "RepoInitMode mode;",
        "dictionary RepoConfig",
        "enum RepoInitMode { \"CreateEmpty\", \"AdoptExisting\" };",
        "PermissionDenied(string path);",
        "InvalidPath(string path);",
        "ICloudPlaceholder(string path);",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`",
        "### `init_repo(repoPath: String, options: RepoInitOptions) throws`",
        "### `load_config(repoPath: String) throws -> RepoConfig`",
        "recommendedMode",
        "`PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。",
        "`ICloudPlaceholder`：候选路径或关键 metadata 仍是未下载的 iCloud 占位符。",
        "不触发 iCloud 占位符下载。",
        "`AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`InvalidPath { path }`",
        "`ICloudPlaceholder { path }`",
        "`PermissionDenied { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn mobile_repo_connect_consumers_can_route_from_structured_status() {
    let empty_repo = tempfile::tempdir().expect("create empty repository directory");
    let empty_validation =
        validate_repo_path(path_string(empty_repo.path())).expect("validate empty directory");
    assert_eq!(
        empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert!(empty_validation.issues.is_empty());

    let non_empty_repo = tempfile::tempdir().expect("create non-empty repository directory");
    fs::write(non_empty_repo.path().join("README.md"), "owned by user\n")
        .expect("write user README");
    let adopt_validation =
        validate_repo_path(path_string(non_empty_repo.path())).expect("validate non-empty path");
    assert_eq!(
        adopt_validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        adopt_validation.issues,
        vec![RepoPathIssue::NonEmptyDirectory]
    );
    assert!(!non_empty_repo.path().join(".areamatrix").exists());

    let initialized_repo = tempfile::tempdir().expect("create initialized repository directory");
    init_repo(
        path_string(initialized_repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");

    let initialized_validation = validate_repo_path(path_string(initialized_repo.path()))
        .expect("validate initialized path");
    let config = load_config(path_string(initialized_repo.path())).expect("load mobile config");

    assert!(initialized_validation.is_initialized);
    assert_eq!(initialized_validation.recommended_mode, None);
    assert_eq!(
        initialized_validation.issues,
        vec![RepoPathIssue::AlreadyInitialized]
    );
    assert_eq!(config.repo_path, path_string(initialized_repo.path()));
}

#[test]
fn mobile_repo_connect_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "security scoped 访问凭证",
        "校验所选目录是否包含 `.areamatrix/`",
        "用户选择已有 repo：显示路径校验通过，自动进入移动端资料库浏览。",
        "用户选择空目录：进入 `S4-X-04 repository-init-confirm`",
        "用户选择非空普通目录：必须进入 `S4-X-05 repository-adopt-confirm`",
        "连接前只读取目录结构；初始化或接管目录会在下一步单独确认。",
    ] {
        assert_contains(CONNECT_REPO_PAGE, fragment);
    }

    for fragment in [
        "页面打开时重新做只读路径校验，不依赖上一页缓存。",
        "点击 `Create Repository` 执行初始化。",
        "Core init empty repo API。",
        "写入前能看到完整路径和 `.areamatrix/` 影响说明。",
    ] {
        assert_contains(INIT_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "页面打开时重新检查目录状态和 `.areamatrix/` 是否存在。",
        "Core adopt existing folder API。",
        "不移动、不删除、不重命名、不覆盖用户文件",
        "未勾选确认项不能继续。",
    ] {
        assert_contains(ADOPT_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "C4-02 mobile repository connection contract reuses the same surface",
        "iOS security-scoped URL or",
        "Core receives only the authorized filesystem path",
        "mobile shells call this only after the shared init/adopt",
        "does not refresh platform permissions or create metadata",
    ] {
        assert_contains(API_RS, fragment);
    }
}
