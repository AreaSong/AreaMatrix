use area_matrix_core::{
    preview_conflict_versions, resolve_icloud_conflict, CoreError, CoreResult,
    ICloudConflictPreviewReport, ICloudConflictPreviewStatus, ICloudConflictResolution,
    ICloudConflictResolutionOption, ICloudConflictResolveReport, ICloudConflictStatus,
    ICloudConflictVersionMetadata, ICloudConflictVersionRole,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-1-stage2-experience/task-76-c2-16-contract-api.md");
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-16-icloud-conflict-visual.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const S2_20_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-20-icloud-conflict-visual.md");
const S1_36_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn icloud_conflict_visual_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_preview(_: fn(String, String) -> CoreResult<ICloudConflictPreviewReport>) {}
    fn assert_resolve(
        _: fn(String, String, ICloudConflictResolution) -> CoreResult<ICloudConflictResolveReport>,
    ) {
    }

    assert_preview(preview_conflict_versions);
    assert_resolve(resolve_icloud_conflict);

    let version = ICloudConflictVersionMetadata {
        version_id: "original".to_owned(),
        role: ICloudConflictVersionRole::Original,
        path: "docs/report.pdf".to_owned(),
        modified_at: Some(1_000),
        size_bytes: Some(860_000),
        hash_sha256: Some("a84f".to_owned()),
        preview_summary: Some("metadata-only preview".to_owned()),
        preview_status: ICloudConflictPreviewStatus::MetadataOnly,
    };
    let option = ICloudConflictResolutionOption {
        resolution: ICloudConflictResolution::KeepOriginal,
        destructive: true,
        requires_trash: true,
        enabled: false,
        disabled_reason: Some("Trash unavailable".to_owned()),
    };
    let preview = ICloudConflictPreviewReport {
        conflict_id: "docs/report.pdf::conflicted-copy".to_owned(),
        versions: vec![version],
        default_resolution: ICloudConflictResolution::KeepBoth,
        resolution_options: vec![option],
        metadata_complete: true,
        trash_available: false,
        can_keep_both: true,
        can_resolve_destructive: false,
        blocked_reason: Some("Trash unavailable".to_owned()),
    };

    assert_eq!(
        preview.default_resolution,
        ICloudConflictResolution::KeepBoth
    );
    assert_eq!(
        preview.versions[0].role,
        ICloudConflictVersionRole::Original
    );
    assert_eq!(
        preview.versions[0].preview_status,
        ICloudConflictPreviewStatus::MetadataOnly
    );
    assert!(preview.can_keep_both);
    assert!(!preview.can_resolve_destructive);

    let report = ICloudConflictResolveReport {
        conflict_id: preview.conflict_id.clone(),
        resolution: ICloudConflictResolution::KeepBoth,
        status: ICloudConflictStatus::Resolved,
        kept_paths: vec![
            "docs/report.pdf".to_owned(),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
        ],
        trashed_paths: Vec::new(),
        undo_token: None,
        change_log_action: "icloud_conflict_resolved".to_owned(),
    };

    assert_eq!(report.status, ICloudConflictStatus::Resolved);
    assert_eq!(report.resolution, ICloudConflictResolution::KeepBoth);
    assert!(report.trashed_paths.is_empty());

    let documented_errors = [
        CoreError::icloud_placeholder("metadata still unavailable"),
        CoreError::permission_denied("trash unavailable"),
        CoreError::conflict("stale conflict preview"),
        CoreError::io("trash move failed"),
        CoreError::db("conflict state failed"),
    ];
    assert_eq!(documented_errors.len(), 5);
}

#[test]
fn icloud_conflict_visual_contract_has_no_fake_success_before_implementation() {
    assert!(matches!(
        preview_conflict_versions(
            "/tmp/repo".to_owned(),
            "docs/report.pdf::conflicted-copy".to_owned()
        ),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        resolve_icloud_conflict(
            "/tmp/repo".to_owned(),
            "docs/report.pdf::conflicted-copy".to_owned(),
            ICloudConflictResolution::KeepBoth
        ),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn icloud_conflict_visual_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-1/task-76: C2-16 contract-api",
        "为 C2-16 icloud-conflict-visual 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C2-16 icloud-conflict-visual",
        "- S2-20 icloud-conflict-visual",
        "- S1-36 icloud-conflict-list",
        "- `list_icloud_conflicts`",
        "计划新增：`preview_conflict_versions`、`resolve_icloud_conflict`",
        "conflict_id、resolution。",
        "版本 metadata、预览摘要、解决报告。",
        "默认 Keep both。",
        "丢弃版本必须走 Trash，不直接删除。",
        "- `ICloudPlaceholder`",
        "- `PermissionDenied`",
        "- `Conflict`",
        "- `Io`",
        "- `Db`",
        "冲突解决失败时保持 unresolved。",
        "不自动删除任一版本。",
        "预览失败不能继续 destructive resolution。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-20 | icloud-conflict-visual | C2-16, C1-25 | conflict preview/resolve | conflict state, Trash",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ICloudConflictPreviewReport preview_conflict_versions(",
        "string repo_path, string conflict_id",
        "ICloudConflictResolveReport resolve_icloud_conflict(",
        "ICloudConflictResolution resolution",
        "dictionary ICloudConflictVersionMetadata",
        "ICloudConflictVersionRole role;",
        "ICloudConflictPreviewStatus preview_status;",
        "dictionary ICloudConflictResolutionOption",
        "boolean destructive;",
        "boolean requires_trash;",
        "dictionary ICloudConflictPreviewReport",
        "ICloudConflictResolution default_resolution;",
        "boolean can_keep_both;",
        "boolean can_resolve_destructive;",
        "dictionary ICloudConflictResolveReport",
        "sequence<string> kept_paths;",
        "sequence<string> trashed_paths;",
        "enum ICloudConflictVersionRole { \"Original\", \"ConflictedCopy\" };",
        "enum ICloudConflictPreviewStatus { \"Available\", \"MetadataOnly\", \"Unavailable\" };",
        "enum ICloudConflictResolution { \"KeepBoth\", \"KeepOriginal\", \"KeepConflictedCopy\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `preview_conflict_versions(repo, conflict_id)` | conflict | √ | ICloudPlaceholder / PermissionDenied / Conflict / Io / Db |",
        "| `resolve_icloud_conflict(repo, conflict_id, resolution)` | conflict | √ | ICloudPlaceholder / PermissionDenied / Conflict / Io / Db |",
        "### `preview_conflict_versions(repoPath, conflictId) throws -> ICloudConflictPreviewReport`",
        "### `resolve_icloud_conflict(repoPath, conflictId, resolution) throws -> ICloudConflictResolveReport`",
        "`default_resolution`：必须为 `KeepBoth`",
        "`KeepBoth`：保留所有版本，只把冲突状态写为 resolved / acknowledged。",
        "`KeepOriginal`：保留原始版本，将 conflicted copy 移到系统 Trash。",
        "`KeepConflictedCopy`：保留 conflicted copy，将原始版本移到系统 Trash。",
        "任一阶段失败必须保持 conflict unresolved",
        "S1-36 仍只消费 `list_icloud_conflicts`，S2-20",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in [
        "ICloudPlaceholder",
        "PermissionDenied",
        "Conflict",
        "Io",
        "Db",
    ] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn icloud_conflict_visual_contract_matches_consuming_page_state_without_adjacent_scope() {
    for fragment in [
        "展示两个版本 metadata。",
        "尽量提供 QuickLook 或文本预览。",
        "提供保留两份、保留左侧、保留右侧。",
        "删除的一侧必须进 Trash。",
        "默认选择 Keep both。",
        "Trash 不可用时禁用 Keep left/right。",
        "Keep both 必须保留所有版本",
        "失败时保持 unresolved",
        "Cancel 和 Decide later 不改变任何文件或 DB 记录。",
    ] {
        assert_contains(S2_20_PAGE, fragment);
    }

    for fragment in [
        "展示当前资料库中的 iCloud 冲突副本列表。",
        "提供单项 Resolve 入口。",
        "Resolve 只打开单项解决 sheet，不在列表页直接删除或移动任何版本。",
        "列表页不会自动删除或移动任何冲突副本。",
    ] {
        assert_contains(S1_36_PAGE, fragment);
    }

    for fragment in [
        "Version role inside a C2-16 iCloud conflict preview.",
        "User resolution choices supported by C2-16.",
        "C2-16 preview report for comparing and resolving iCloud conflict versions.",
        "C2-16 resolution result returned after explicit user confirmation.",
        "Versions moved to Trash; empty for KeepBoth.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for forbidden in [
        "import conflict batch",
        "AI provider",
        "remote provider",
        "Cloud SDK",
    ] {
        assert!(
            !API_RS.contains(forbidden),
            "C2-16 API contract should not implement adjacent scope: {forbidden}"
        );
    }
}
