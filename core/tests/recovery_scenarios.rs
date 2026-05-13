const SCENARIOS: &str = include_str!("../../docs/development/recovery-scenarios.md");
const MATRIX: &str = include_str!("../../docs/development/error-recovery-matrix.md");
const TESTING: &str = include_str!("../../docs/development/testing.md");
const TROUBLESHOOTING: &str = include_str!("../../docs/development/troubleshooting.md");
const TRANSACTIONAL_IMPORT: &str = include_str!("../../docs/architecture/transactional-import.md");
const C1_06_COPY: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md");
const C1_07_MOVE: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md");
const C1_08_INDEX: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md");
const C1_16_RECOVERY: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md");
const C1_21_ERROR_MAPPING: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md");
const C1_25_ICLOUD: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md");
const C1_26_REPAIR: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md");
const IMPORT_COPY_FAILURE: &str = include_str!("import_copy_file_failure_recovery.rs");
const IMPORT_MOVE_FAILURE: &str = include_str!("import_move_file_failure_recovery.rs");
const IMPORT_INDEX_FAILURE: &str = include_str!("import_index_file_failure_recovery.rs");
const DUPLICATE_FAILURE: &str = include_str!("detect_duplicate_failure_recovery.rs");
const CONFLICT_FAILURE: &str = include_str!("resolve_name_conflict_failure_recovery.rs");
const STARTUP_RECOVERY_FAILURE: &str = include_str!("recover_on_startup_failure_recovery.rs");
const STARTUP_RECOVERY_VALIDATION: &str = include_str!("recover_on_startup_validation.rs");
const STARTUP_RECOVERY_VERIFY: &str = include_str!("recover_on_startup_integration_verify.rs");
const ICLOUD_FAILURE: &str = include_str!("list_icloud_conflicts_failure_recovery.rs");
const REPAIR_FAILURE: &str = include_str!("repair_reindex_metadata_failure_recovery.rs");
const SWIFT_IMPORT_FOLDER: &str =
    include_str!("../../apps/macos/AreaMatrixTests/ImportFolderPageIntegrationVerifyTests.swift");
const SWIFT_QUEUE_RECOVERY: &str =
    include_str!("../../apps/macos/AreaMatrixTests/ImportProgressCopyQueueRecoveryTests.swift");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected recovery scenario evidence to contain `{needle}`"
    );
}

fn assert_all_contains(haystack: &str, needles: &[&str]) {
    for needle in needles {
        assert_contains(haystack, needle);
    }
}

#[test]
fn recovery_scenarios_cover_stage_one_matrix_and_manual_gates() {
    assert_all_contains(
        SCENARIOS,
        &[
            "RS-01 crash during staging",
            "RS-02 user interruption during batch import",
            "RS-03 startup staging residue cleanup",
            "RS-04 DB repair after corrupted metadata",
            "RS-05 iCloud placeholder import/list failure",
            "RS-06 permission denied during import/recovery/repair",
            "RS-07 copy/move/index DB failure",
            "RS-08 duplicate / overwrite / conflict rollback",
            "RS-09 reindex / repair failure and resume",
            "RS-10 DB locked vs corrupted mapping",
            "M-01 import 中断 / 崩溃恢复",
            "M-02 iCloud placeholder 下载与重试",
            "M-03 macOS 权限 / TCC 失败",
            "M-04 DB repair / diagnostics",
        ],
    );

    for domain in [
        "repo path",
        "permission",
        "DB",
        "IO",
        "iCloud placeholder",
        "duplicate",
        "conflict",
        "staging recovery",
        "internal",
    ] {
        assert_contains(MATRIX, domain);
    }
    assert_contains(SCENARIOS, "P1-ER-001");
    assert_contains(SCENARIOS, "Stage 1 发布不通过");
    assert_contains(SCENARIOS, "Manual evidence pending");
    assert_contains(SCENARIOS, "manual_evidence_status: pass");
    assert_contains(SCENARIOS, "manual_evidence_status: blocked");
}

#[test]
fn recovery_scenarios_link_source_docs_and_capability_specs() {
    assert_all_contains(
        TESTING,
        &[
            "## 崩溃测试",
            "SIGKILL",
            "recover_on_startup",
            "手工冒烟清单",
        ],
    );
    assert_all_contains(
        TROUBLESHOOTING,
        &[
            "R4. iCloud 文件无法导入",
            "R6. 写权限被拒",
            "D1. SQLITE_BUSY: database is locked",
            "D3. PRAGMA integrity_check 报错",
            "Staging / 事务",
        ],
    );
    assert_all_contains(
        TRANSACTIONAL_IMPORT,
        &[
            "INV-1",
            "INV-2",
            "失败的 import 不留下 DB 记录或最终目录中的半文件",
            "各失败场景处理",
            "Indexed 失败只回滚本次 DB staging 行",
        ],
    );

    assert_all_contains(
        C1_06_COPY,
        &["保留原文件不变", "失败不会留下 active 半成品"],
    );
    assert_all_contains(C1_07_MOVE, &["移动失败必须保留源文件或可恢复 staging"]);
    assert_all_contains(C1_08_INDEX, &["不复制、不移动源文件", "ICloudPlaceholder"]);
    assert_all_contains(C1_16_RECOVERY, &["不删除任何最终目录用户文件"]);
    assert_all_contains(
        C1_21_ERROR_MAPPING,
        &["错误映射不依赖字符串 contains 做主分支判断"],
    );
    assert_all_contains(C1_25_ICLOUD, &["只读扫描 iCloud conflicted copy"]);
    assert_all_contains(C1_26_REPAIR, &["不移动、不重命名、不删除用户文件"]);
}

#[test]
fn recovery_scenarios_transactional_import_evidence_is_executable() {
    for (source, function_name) in [
        (
            IMPORT_COPY_FAILURE,
            "import_copy_file_failure_recovery_rolls_back_final_file_when_db_promotion_fails",
        ),
        (
            IMPORT_MOVE_FAILURE,
            "import_move_file_failure_recovery_db_staging_insert_restores_source",
        ),
        (
            IMPORT_MOVE_FAILURE,
            "import_move_file_failure_recovery_failed_attempt_can_be_retried",
        ),
        (
            IMPORT_INDEX_FAILURE,
            "import_index_file_failure_recovery_failed_attempt_can_be_retried",
        ),
        (
            DUPLICATE_FAILURE,
            "detect_duplicate_failure_recovery_moved_ask_restores_source_without_final_side_effects",
        ),
        (
            CONFLICT_FAILURE,
            "resolve_name_conflict_failure_recovery_import_db_failure_removes_numbered_final",
        ),
    ] {
        assert_contains(source, function_name);
        assert_contains(SCENARIOS, function_name);
    }
}

#[test]
fn recovery_scenarios_staging_repair_icloud_and_permission_have_release_gates() {
    for (source, function_name) in [
        (
            STARTUP_RECOVERY_FAILURE,
            "recover_on_startup_failure_recovery_permission_denied_keeps_retryable_state",
        ),
        (
            STARTUP_RECOVERY_VALIDATION,
            "recover_on_startup_validation_proves_report_db_and_filesystem_cleanup",
        ),
        (
            STARTUP_RECOVERY_VERIFY,
            "recover_on_startup_integration_verify_real_report_drives_consumers_without_user_file_loss",
        ),
        (
            ICLOUD_FAILURE,
            "list_icloud_conflicts_failure_recovery_placeholder_error_keeps_files_and_retries",
        ),
        (
            REPAIR_FAILURE,
            "repair_reindex_metadata_failure_recovery_rebuilds_corrupted_db_after_snapshot",
        ),
        (
            REPAIR_FAILURE,
            "repair_reindex_metadata_failure_recovery_permission_denied_records_resumable_session",
        ),
    ] {
        assert_contains(source, function_name);
        assert_contains(SCENARIOS, function_name);
    }

    assert_contains(
        IMPORT_INDEX_FAILURE,
        "import_index_file_failure_recovery_rejects_icloud_marker_without_db_write",
    );
    assert_contains(SWIFT_IMPORT_FOLDER, "downloadICloudPlaceholdersAndRetry");
    assert_contains(
        SWIFT_QUEUE_RECOVERY,
        "testS120FatalCopyRetryContinuesRemainingQueue",
    );
    assert_contains(SCENARIOS, "M-02 缺失时阻断发布");
    assert_contains(SCENARIOS, "M-03 缺失时阻断发布");
    assert_contains(SCENARIOS, "M-04");
}

#[test]
fn recovery_scenarios_db_mapping_blocker_is_closed_by_real_core_evidence() {
    assert_contains(SCENARIOS, "P1-ER-001 已关闭");
    assert_contains(
        SCENARIOS,
        "error_recovery_matrix_error_mapping_records_db_subsemantic_closure",
    );
    assert_contains(
        SCENARIOS,
        "error_mapping_validation_db_locked_and_corrupted_have_distinct_recovery_paths",
    );
    assert_contains(SCENARIOS, "数据库暂时被占用");
    assert_contains(SCENARIOS, "资料库索引损坏");
    assert_contains(MATRIX, "P1-ER-001 已关闭");
}

#[test]
fn recovery_scenarios_manual_evidence_schema_blocks_release_without_claiming_pass() {
    for required_field in [
        "manual_evidence_id",
        "environment",
        "operator",
        "executed_at",
        "result",
        "evidence_paths",
        "user_file_invariants",
    ] {
        assert_contains(SCENARIOS, required_field);
    }

    assert_contains(
        SCENARIOS,
        "manual_evidence_status: \"pending | pass | blocked\"",
    );
    assert_contains(SCENARIOS, "manual_evidence_status: pass");
    assert_contains(SCENARIOS, "manual_evidence_status: blocked");
    assert_contains(SCENARIOS, "成功 10 · 停止 0 · 失败 0 · 待处理 234");
    assert_contains(SCENARIOS, "Import not completed before AreaMatrix quit");
    assert_contains(SCENARIOS, "current.json` 已清除");
    assert_contains(SCENARIOS, "当前没有");
    assert_contains(
        SCENARIOS,
        "blocked_reason: no iCloud placeholder environment available",
    );
    assert_contains(SCENARIOS, "后续补证模板");
    assert_contains(SCENARIOS, "environment.icloud_drive: enabled");
    assert_contains(SCENARIOS, "source_placeholder_status.before");
    assert_contains(
        SCENARIOS,
        "result: pass` 只有在真实 iCloud Drive placeholder 环境完成下载与 retry 后才能填写",
    );
    assert_contains(SCENARIOS, "M-03 权限恢复");
    assert_contains(SCENARIOS, "m03-evidence-20260510_221849");
    assert_contains(SCENARIOS, "d---r-xr-x");
    assert_contains(SCENARIOS, "Repository needs permission");
    assert_contains(SCENARIOS, "PermissionDenied");
    assert_contains(SCENARIOS, "Reconnect folder");
    assert_contains(SCENARIOS, "未修改系统 TCC 数据库");
    assert_contains(
        SCENARIOS,
        "M-04 DB repair / diagnostics 手工日志已采集并通过",
    );
    assert_contains(SCENARIOS, "m04-evidence-20260510_213637");
    assert_contains(SCENARIOS, "Run Full Rescan");
    assert_contains(SCENARIOS, "未分类 11 files");
    assert_contains(
        SCENARIOS,
        "index-1778421523-2695bbce-82b9-4ea6-9b33-ad02eb06f1d8.db",
    );
    assert_contains(SCENARIOS, "checksum diff 行数为 `0`");
    assert_contains(SCENARIOS, "repo 根目录未生成 `AREAMATRIX.md`");
}

#[test]
fn recovery_scenarios_rollback_scope_stays_inside_task_expected_paths() {
    assert_contains(SCENARIOS, "`docs/development/recovery-scenarios.md`");
    assert_contains(SCENARIOS, "`core/tests/recovery_scenarios.rs`");
    assert_contains(SCENARIOS, "不属于本任务回滚范围");

    for out_of_scope_path in [
        "`core/src/error.rs` 中 DB 子语义映射修复",
        "`apps/macos/AreaMatrixTests/MainRepoErrorMappingTests.swift` 中真实 CoreBridge DB 映射测试",
    ] {
        assert!(
            !SCENARIOS.contains(out_of_scope_path),
            "rollback scope must not claim current task ownership of {out_of_scope_path}"
        );
    }
}
