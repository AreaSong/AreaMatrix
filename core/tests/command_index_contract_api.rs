use area_matrix_core::{
    list_command_targets, CommandIndex, CommandIndexContext, CommandTarget, CommandTargetAction,
    CommandTargetGroup, CommandTargetKind, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

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
        route: Some("rename".to_owned()),
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
    let repo = tempfile::tempdir().expect("create isolated command-index repository");
    let repo_path = repo.path().to_string_lossy().into_owned();
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
        list_command_targets(repo_path.clone(), invalid_selection),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_path = valid;
    invalid_path.current_path = Some("../outside".to_owned());
    assert!(matches!(
        list_command_targets(repo_path.clone(), invalid_path),
        Err(CoreError::Db { .. })
    ));

    let db_result = list_command_targets(
        repo_path,
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
        "command index 的命令索引入口",
        "command palette",
        "selection context",
        "可执行命令、导航目标、当前选择命令、最近命令",
        "Smart List 和文件候选",
        "`requires_confirmation`",
        "危险命令只返回跳转确认或预览页的目标",
        "不得在命令",
        "面板中直接执行。",
        "不执行 Smart List；打开 Smart List 结果仍调用 Smart List execution",
        "`run_smart_list`。",
        "不实现插件命令市场",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn command_index_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "command index contract",
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
    assert_contains(UDL, "Db");
}
