use area_matrix_core::{
    list_command_targets, CommandIndex, CommandIndexContext, CommandTarget, CommandTargetAction,
    CommandTargetGroup, CommandTargetKind, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-11-command-index.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const COMMAND_PALETTE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-15-command-palette.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const COMMAND_INDEX_RS: &str = include_str!("../src/command_index.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn command_index_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_list(_: fn(String, CommandIndexContext) -> CoreResult<CommandIndex>) {}
    assert_list(list_command_targets);

    let context = CommandIndexContext {
        query: Some("tag".to_owned()),
        selected_file_ids: vec![10, 11],
        current_path: Some("reports/2026".to_owned()),
        include_file_candidates: true,
    };
    assert_eq!(context.query.as_deref(), Some("tag"));
    assert_eq!(context.selected_file_ids, vec![10, 11]);
    assert!(context.include_file_candidates);

    let rename_target = CommandTarget {
        id: "selection.rename".to_owned(),
        title: "Rename...".to_owned(),
        subtitle: Some("Rename 2 selected files".to_owned()),
        group: CommandTargetGroup::CurrentSelection,
        kind: CommandTargetKind::Command,
        action: CommandTargetAction::OpenConfirmation,
        route: Some("S2-14".to_owned()),
        shortcut: None,
        disabled: false,
        disabled_reason: None,
        requires_confirmation: true,
        file_id: None,
        saved_search_id: None,
    };
    let smart_list_target = CommandTarget {
        id: "smart-list:42".to_owned(),
        title: "Needs Review".to_owned(),
        subtitle: Some("Open Smart List".to_owned()),
        group: CommandTargetGroup::SmartLists,
        kind: CommandTargetKind::SmartList,
        action: CommandTargetAction::RunSmartList,
        route: None,
        shortcut: Some("Cmd+4".to_owned()),
        disabled: false,
        disabled_reason: None,
        requires_confirmation: false,
        file_id: None,
        saved_search_id: Some(42),
    };
    let index = CommandIndex {
        commands: vec![rename_target.clone()],
        navigation_targets: vec![CommandTarget {
            id: "settings".to_owned(),
            title: "Settings".to_owned(),
            subtitle: Some("Open settings".to_owned()),
            group: CommandTargetGroup::Navigation,
            kind: CommandTargetKind::Navigation,
            action: CommandTargetAction::Navigate,
            route: Some("settings".to_owned()),
            shortcut: Some("Cmd+,".to_owned()),
            disabled: false,
            disabled_reason: None,
            requires_confirmation: false,
            file_id: None,
            saved_search_id: None,
        }],
        current_selection_targets: vec![rename_target],
        recent_targets: vec![CommandTarget {
            id: "recent:import".to_owned(),
            title: "Import files...".to_owned(),
            subtitle: None,
            group: CommandTargetGroup::Recent,
            kind: CommandTargetKind::RecentCommand,
            action: CommandTargetAction::OpenSheet,
            route: Some("import".to_owned()),
            shortcut: Some("Cmd+I".to_owned()),
            disabled: false,
            disabled_reason: None,
            requires_confirmation: false,
            file_id: None,
            saved_search_id: None,
        }],
        smart_lists: vec![smart_list_target],
        file_candidates: vec![CommandTarget {
            id: "file:9".to_owned(),
            title: "contract.pdf".to_owned(),
            subtitle: Some("reports/contract.pdf".to_owned()),
            group: CommandTargetGroup::FileCandidates,
            kind: CommandTargetKind::FileCandidate,
            action: CommandTargetAction::FocusFile,
            route: None,
            shortcut: None,
            disabled: false,
            disabled_reason: None,
            requires_confirmation: false,
            file_id: Some(9),
            saved_search_id: None,
        }],
        generated_at: 1_000,
    };
    assert_eq!(index.commands.len(), 1);
    assert_eq!(
        index.navigation_targets[0].kind,
        CommandTargetKind::Navigation
    );
    assert!(index.current_selection_targets[0].requires_confirmation);
    assert_eq!(index.smart_lists[0].saved_search_id, Some(42));
    assert_eq!(index.file_candidates[0].file_id, Some(9));

    let documented_errors = [CoreError::db("command metadata unavailable")];
    assert_eq!(documented_errors.len(), 1);
}

#[test]
fn command_index_contract_validates_context_without_fake_success() {
    let valid = CommandIndexContext {
        query: None,
        selected_file_ids: Vec::new(),
        current_path: None,
        include_file_candidates: false,
    };
    assert!(matches!(
        list_command_targets(String::new(), valid.clone()),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_selection = valid.clone();
    invalid_selection.selected_file_ids = vec![0];
    assert!(matches!(
        list_command_targets("/tmp/repo".to_owned(), invalid_selection),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_path = valid;
    invalid_path.current_path = Some("../outside".to_owned());
    assert!(matches!(
        list_command_targets("/tmp/repo".to_owned(), invalid_path),
        Err(CoreError::Db { .. })
    ));

    let db_result = list_command_targets(
        "/tmp/repo".to_owned(),
        CommandIndexContext {
            query: Some("smart".to_owned()),
            selected_file_ids: vec![1],
            current_path: Some("docs".to_owned()),
            include_file_candidates: true,
        },
    );
    assert!(matches!(db_result, Err(CoreError::Db { .. })));
}

#[test]
fn command_index_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-11 command-index",
        "- S2-15 command-palette",
        "计划新增：`list_command_targets(repo_path) -> CommandIndex`",
        "repo_path、当前 selection context。",
        "可执行命令、最近项目、smart lists、文件候选。",
        "读取 metadata；可记录 recent command。",
        "- `Db`",
        "命令面板只列出当前上下文允许的动作。",
        "危险动作仍必须跳转确认页。",
        "不绕过权限或高风险确认。",
        "插件命令市场属于后续阶段。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-15 | command-palette | C2-04, C2-11 | command index | 只读 / recent command",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "CommandIndex list_command_targets(string repo_path, CommandIndexContext context);",
        "dictionary CommandIndexContext",
        "sequence<i64> selected_file_ids;",
        "boolean include_file_candidates;",
        "dictionary CommandTarget",
        "CommandTargetGroup group;",
        "CommandTargetKind kind;",
        "CommandTargetAction action;",
        "boolean requires_confirmation;",
        "i64? file_id;",
        "i64? saved_search_id;",
        "dictionary CommandIndex",
        "sequence<CommandTarget> commands;",
        "sequence<CommandTarget> navigation_targets;",
        "sequence<CommandTarget> current_selection_targets;",
        "sequence<CommandTarget> recent_targets;",
        "sequence<CommandTarget> smart_lists;",
        "sequence<CommandTarget> file_candidates;",
        "enum CommandTargetGroup",
        "\"CurrentSelection\"",
        "\"SmartLists\"",
        "\"FileCandidates\"",
        "enum CommandTargetAction",
        "\"OpenConfirmation\"",
        "\"RunSmartList\"",
        "\"FocusFile\"",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "CommandIndex list_command_targets(string repo_path, CommandIndexContext context);",
        "| `list_command_targets(repo, context)` | command | √ | Db |",
        "### `list_command_targets(repoPath, context) throws -> CommandIndex`",
        "C2-11 的命令索引入口",
        "`S2-15 command-palette`",
        "selection context",
        "可执行命令、导航目标、当前选择命令、最近命令",
        "Smart List 和文件候选",
        "`requires_confirmation`",
        "危险命令只返回跳转确认或预览页的目标",
        "不得在命令",
        "面板中直接执行。",
        "不执行 Smart List；打开 Smart List 结果仍调用 C2-04",
        "`run_smart_list`。",
        "不实现插件命令市场",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn command_index_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "搜索命令。",
        "搜索导航目标：Settings、Smart Lists、Needs Review。",
        "根据当前选择显示上下文命令：Rename、Add tags、Change category。",
        "支持最近使用命令。",
        "对危险命令显示确认流程入口，不直接执行。",
        "无 repo 或无选择时，相关命令禁用或隐藏，并在副标题说明原因。",
        "命令面板只能导航、聚焦、打开 sheet 或触发低风险即时动作",
        "不得绕过 S2-12、S2-13、S2-14、S2-18 的确认/预览。",
        "Stage 2 不注册智能化、OCR 或多端命令。",
    ] {
        assert_contains(COMMAND_PALETTE_PAGE, fragment);
    }

    for fragment in [
        "C2-11 command index contract",
        "grouped command rows",
        "Smart",
        "List navigation targets",
        "recent commands",
        "file candidates",
        "confirmation boundaries",
        "must never execute destructive actions",
        "CoreError::Db",
    ] {
        assert_contains(COMMAND_INDEX_RS, fragment);
    }

    assert_contains(ERROR_CODES, "Db");
    assert_contains(CAPABILITY_SPEC, "Db");
    assert_contains(UDL, "Db");
}
