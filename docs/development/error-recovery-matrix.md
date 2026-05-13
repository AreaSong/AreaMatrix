# Stage 1 错误恢复矩阵

> Stage 1 MVP 的错误恢复发布证据：从 Core 错误码追到 UX 文案、恢复动作、诊断入口、阻断级别和测试证据。
>
> 阅读时长：约 10 分钟。

---

## 1. 范围

本矩阵只定义稳定性验收证据，不新增产品功能。它覆盖：

- `docs/api/error-codes.md` 中的全部 `CoreError` variant。
- `docs/ux/error-messages.md` 中的用户可见文案、动作和诊断入口。
- `docs/architecture/transactional-import.md` 中的事务式导入失败路径。
- `docs/development/troubleshooting.md` 中的排查入口。

本矩阵的阻断级别：

| 等级 | 含义 | 发布处理 |
|---|---|---|
| P0 | 可能丢失、覆盖、移动用户文件，或失败后留下最终目录半成品 | 阻断 Stage 1 发布，必须先修复 |
| P1 | 用户无法完成明确恢复动作，或 Core/UX 语义冲突会误导恢复路径 | 阻断 Stage 1 发布，需要回退到 Phase 1/2 补 task |
| P2 | 文案、诊断或测试证据不完整，但不改变恢复安全性 | 可以排期，但不得冒充已验证闭环 |

## 2. 错误恢复总表

| 错误域 | Core 来源 | 用户可见文案 / UI | 恢复动作 | 诊断入口 | 阻断级别与证据 |
|---|---|---|---|---|---|
| repo path | `InvalidPath`、`RepoNotInitialized`、`FileNotFound` | `路径不合法`、`资料库未初始化`、`Folder is missing`、首次启动向导或 main repo error | 重新选择资料库、重新初始化、Reconnect folder、刷新列表 | `ValidatePathErrorMappingSmokeTests.swift`、`MainRepoErrorMappingTests.swift`、troubleshooting 运行时章节 | P1 watch：`RepoNotInitialized` 在 Core mapping 是 High，但 UX blocking 语义是 critical；消费页必须继续覆盖。 |
| permission | `PermissionDenied` | `无访问权限`、repo blocking 或单文件 toast | 选择其他文件夹、打开系统设置、重试前先修复权限 | R6：`docs/development/troubleshooting.md#r6-写权限被拒`、diagnostics export | 已有 Core/Swift 证据：`error_mapping_failure_recovery_permission_denied_never_becomes_retryable`、`testConfiguredRepoOpenFailureRoutesMappedC121ErrorToMainRepoError`。 |
| DB | `Db` | DB locked：inline/banner + Retry；DB corrupted：blocking repair | locked 只能 Retry；corrupt 进入 Repair index / Open repo in Finder / Collect diagnostics | D1：`docs/development/troubleshooting.md#d1-sqlite_busy-database-is-locked`、D2/D3、diagnostics export | **P1-ER-001 已关闭**：真实 Core mapping 通过 `Db.message` 区分 locked retryable 与 corrupt fatal；证据见 `error_mapping_validation_db_locked_and_corrupted_have_distinct_recovery_paths`、`error_recovery_matrix_error_mapping_records_db_subsemantic_closure`、`testDefaultCoreBridgeMapsDbLockedAndCorruptedToDistinctRecoveryActions`。 |
| IO | `Io`、`FileNotFound` | `文件操作失败`、`文件不存在` | Retry、刷新列表、Remove from index、Locate | Console log、Collect diagnostics、troubleshooting R3/T3 | 已有证据：`error_mapping_contract_api_maps_each_error_to_stable_ui_metadata`、`MainFileListDetailSupport` 映射路径。 |
| iCloud placeholder | `ICloudPlaceholder` | `iCloud 文件未下载`、`iCloud file is not downloaded` | Download & retry、Switch to local repo、Cancel | R4：`docs/development/troubleshooting.md#r4-icloud-文件无法导入`、`mdls`、`brctl download` | P1 watch：Core suggested action 文案偏自动等待，UX 要用户可控 Download & retry；Swift main repo 和 import flow 已有页面证据，后续不得退化为静默下载。 |
| duplicate | `DuplicateFile` | `文件已存在` | Skip、Overwrite、Keep both、Cancel | import result / change_log / diagnostics | 已有证据：`detect_duplicate_failure_recovery_moved_ask_restores_source_without_final_side_effects`、`detect_duplicate_failure_recovery_overwrite_db_failure_can_be_retried`。 |
| conflict | `Conflict` | `路径冲突` | Auto-rename、Rename...、Retry | import conflict sheet、change_log、diagnostics | 已有证据：`resolve_name_conflict_failure_recovery_import_db_failure_removes_numbered_final`、`resolve_name_conflict_failure_recovery_moved_exhaustion_restores_source_and_retries`。 |
| staging recovery | `recover_on_startup` 返回 `RecoveryReport`；失败时走 `Db`、`Io`、`PermissionDenied` | `Startup recovery complete` / `Startup recovery failed` | Retry startup recovery；fatal DB 路由到 repair；不得自动执行高风险修复 | recovery report、`.areamatrix/staging`、DB staging rows、diagnostics export | 当前无 P0 缺口：`recover_on_startup_integration_verify_real_report_drives_consumers_without_user_file_loss` 和 moved residue 测试证明不删除用户文件。 |
| internal | `Internal` | `应用内部错误` | Restart、Collect diagnostics、Open Issue | trace id、OSLog、diagnostics export | Critical；不得自动重试。已有证据：`error_mapping_failure_recovery_retry_policy_stays_structured_by_kind`、S1-32 mapped error view tests。 |

## 3. Core / UX 覆盖检查

Core `CoreError` variant 覆盖状态：

| Variant | UX 文案 | 恢复动作 | 诊断入口 | 状态 |
|---|---|---|---|---|
| `Io` | `文件操作失败` | Retry | Collect diagnostics | 已覆盖 |
| `Db` | DB locked：`数据库暂时被占用`；DB corrupted：`资料库索引损坏` | Retry / Repair | integrity check、diagnostics | 已覆盖：locked 为 `Retryable` + medium；corrupt 为 `Fatal` + critical。 |
| `Config` | `配置错误` | Open rules / Revert | settings diagnostics | 已覆盖 |
| `Classify` | `分类失败` | Use inbox / Report | logs | 已覆盖 |
| `Conflict` | `路径冲突` | Auto-rename / Rename | import details | 已覆盖 |
| `DuplicateFile` | `文件已存在` | Skip / Overwrite / Keep both | import details | 已覆盖 |
| `FileNotFound` | `文件不存在` | Refresh / Remove from index | list/detail logs | 已覆盖 |
| `RepoNotInitialized` | `资料库未初始化` | First launch / Repair | repo open diagnostics | P1 watch |
| `InvalidPath` | `路径不合法` | Change path | validate-path diagnostics | 已覆盖 |
| `ICloudPlaceholder` | `iCloud 文件未下载` | Download & retry / Switch local | mdls / brctl / diagnostics | P1 watch |
| `PermissionDenied` | `无访问权限` | Choose folder / Help | R6 checks / diagnostics | 已覆盖 |
| `Internal` | `应用内部错误` | Restart / Collect diagnostics | trace id / OSLog | 已覆盖 |

无主项检查：

- 未发现没有 Core 来源的 Stage 1 用户错误页面；DB locked/corrupted、磁盘满、EBUSY 属于 `Db`/`Io` 的子语义。
- 未发现没有 UX 文案的 Core variant；全部 variant 在 `docs/api/error-codes.md` 和 `docs/ux/error-messages.md` 有文案。
- `Db` 子语义已在真实 Core mapping 中区分：locked 可重试、corrupt 阻断并进入 repair。

## 4. 事务式导入失败路径

| 失败点 | 不允许状态 | 恢复 / 清理策略 | 证据 |
|---|---|---|---|
| 源路径校验失败 | 创建 staging、DB row 或最终文件 | 直接返回 `InvalidPath` / `FileNotFound` / `PermissionDenied` | `PreparedImport::new`、`import_copy_file_failure_recovery_permission_denied_leaves_no_side_effects` |
| copy 到 staging、hash 或 DB promotion 失败 | 最终目录半文件、active row | `StagingFileGuard` 删除 internal staging；copy mode 保持源文件；DB promotion 失败删除本次 final | `stage_source`、`StagingFileGuard::create_for_copy`、`import_copy_file_failure_recovery_rolls_back_final_file_when_db_promotion_fails` |
| move 到 staging 后 DB insert 失败 | 源文件丢失、staging row 残留 | guard 把 staged source 恢复到原 source；无 active row | `import_move_file_failure_recovery_db_staging_insert_restores_source` |
| duplicate Skip / Ask | 修改现有 active row、留下新 final 文件 | 返回 `DuplicateFile`；source 和现有 final 保持不变 | `detect_duplicate_failure_recovery_moved_ask_restores_source_without_final_side_effects` |
| same-name conflict 自动编号后 DB promotion 失败 | `name_1.ext` 半成品留在最终目录 | `FinalFileGuard` 删除本次 final；`DbStagingRowGuard` 回滚本次 staging row | `resolve_name_conflict_failure_recovery_import_db_failure_removes_numbered_final` |
| moved import promotion 失败 | moved source 丢失且 final 半成品不可恢复 | `FinalFileGuard::RestoreSource` 尝试把 final 恢复为 source；否则保留 recoverable staging | `import_move_file_failure_recovery_failed_attempt_can_be_retried` |
| overwrite replace 后 DB/overview 失败 | 旧文件丢失、新 row 半提交 | replacement guard、`ReplacementDbRollback` 与 `finish_overview_regeneration` 保持可恢复；retry 可完成 | `detect_duplicate_failure_recovery_overwrite_db_failure_can_be_retried` |
| indexed import DB 写入失败 | 外部源文件被移动/删除、资料库出现 final copy | Indexed 不进入 staging/final 落位；DB rollback 后外部源保留 | `import_index_file_failure_recovery_failed_attempt_can_be_retried` |
| startup recovery | 删除 active 文件、README、AREAMATRIX.md 或非 AreaMatrix 用户文件 | 只清理可判定安全的 `.areamatrix/staging` 文件和 staging rows；不做 reindex | Staging / 事务：`recover_on_startup_integration_verify_real_report_drives_consumers_without_user_file_loss`；收集诊断信息 |

当前 P0 结论：未发现已知事务式导入 P0 缺口。若上述任一测试失败，Stage 1 发布必须直接阻断。

## 5. 发布阻断清单

### P1-ER-001 已关闭: DB 子语义缺失

- 证据：`docs/ux/error-messages.md` 要求 DB locked 使用 Retry，DB corrupted 使用 blocking repair。
- 修复：`core/src/error.rs` 保留 `ErrorKind::Db` 和现有 UDL shape，通过 `Db.message`
  的稳定 SQLite / integrity marker 选择 `DB_LOCKED_MAPPING` 或
  `DB_CORRUPTED_MAPPING`。
- 真实 Core 结果：`database is locked` -> medium + `Retryable`；`database disk image is
  malformed` -> critical + `Fatal`。locked retryable 与 corrupt fatal 已可区分。
- 验证：`error_mapping_validation_db_locked_and_corrupted_have_distinct_recovery_paths`、
  `error_recovery_matrix_error_mapping_records_db_subsemantic_closure` 和
  `testDefaultCoreBridgeMapsDbLockedAndCorruptedToDistinctRecoveryActions`。
- 残余约束：不得把任意 `Db` 默认当成可重试；未知 DB 错误仍走 high +
  `UserActionRequired`，避免误导用户执行自动修复。

### P1 watch: Repo / iCloud 上下文语义

- `RepoNotInitialized` 在 Core mapping 为 High，但 UX 页面语义是 first-launch 或 blocking repair。当前消费页面已有路由测试，后续不能只看 Core severity。
- `ICloudPlaceholder` 的 Core suggested action 倾向“等待自动重试”，UX 要用户可控 `Download & retry` / `Switch to local repo`。当前 main repo / import flow 已有页面动作测试，后续不能退化为静默下载。

## 6. 回滚与验证

本任务只新增稳定性证据和测试，不改产品路径。回滚时撤销：

- `docs/development/error-recovery-matrix.md`
- `core/tests/error_recovery_matrix.rs`

必须运行：

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
cargo test --workspace recovery
cargo test --workspace error_mapping
```

若在仓库根目录没有 Cargo workspace，使用 `cd core && cargo test --workspace recovery`
和 `cd core && cargo test --workspace error_mapping` 作为等价 Rust 证据，并在报告中说明。

## Related

- [error-codes.md](../api/error-codes.md)
- [error-messages.md](../ux/error-messages.md)
- [transactional-import.md](../architecture/transactional-import.md)
- [troubleshooting.md](troubleshooting.md)
