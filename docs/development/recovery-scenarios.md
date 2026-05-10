# Stage 1 恢复场景清单

> 将 `3-1/task-01` 的错误恢复矩阵转成可执行恢复场景，区分自动化测试、手工冒烟和发布阻断证据。
>
> 阅读时长：约 12 分钟。

---

## 1. 范围

本清单只补 Stage 1 MVP 的恢复验收证据，不补产品实现。恢复场景来自
[error-recovery-matrix.md](error-recovery-matrix.md)，并交叉读取：

- [error-codes.md](../api/error-codes.md)
- [testing.md](testing.md)
- [troubleshooting.md](troubleshooting.md)
- [transactional-import.md](../architecture/transactional-import.md)
- `docs/core/capability-specs/stage-1-mvp/C1-06..C1-08`
- `docs/core/capability-specs/stage-1-mvp/C1-16`
- `docs/core/capability-specs/stage-1-mvp/C1-21`
- `docs/core/capability-specs/stage-1-mvp/C1-25`
- `docs/core/capability-specs/stage-1-mvp/C1-26`

证据类型：

| 类型 | 含义 | 发布处理 |
|---|---|---|
| `Automated` | 已有 Rust 或 Swift 测试能在 CI / 本地验证 | 对应测试失败即阻断 |
| `Manual smoke` | 必须在真实 macOS / iCloud / TCC 环境手工执行 | 发布前缺日志即阻断 |
| `Manual evidence pending` | 手工步骤、证据字段和阻断条件已定义，但尚未在发布机执行 | 阻断 Stage 1 发布；不得写成 PASS |

高风险不变量：

- 不删除、移动、重命名、覆盖任何用户原文件，除非用户明确选择 Move/Overwrite。
- 失败导入不得留下最终目录半成品，不得把失败操作标为成功。
- `.areamatrix/staging/` 中间产物不得进入用户可见列表。
- DB 修复、reindex、iCloud 占位符和权限失败不得静默改写用户文件。
- P0/P1 缺少证据时必须阻断发布，不能降级成“后续优化”。

## 2. 场景总表

| ID | 来源 | 类型 | 初始状态 | 触发方式 | 预期恢复结果 | 用户文件不变量 | 验证方式 | 发布结论 |
|---|---|---|---|---|---|---|---|---|
| RS-01 crash during staging | transactional import A/B/C/H、C1-16 | Automated + Manual smoke | repo 已初始化，Copy/Move import 正在 staging、hash 或 DB staging row 阶段 | 单测构造 staging 文件/row；发布冒烟用强退或 SIGKILL | `recover_on_startup` 清理安全 staging 文件和 staging row，或保留可恢复 moved staging | 源文件仍在原路径或可恢复 staging；无 active 半成品 | `recover_on_startup_validation_proves_report_db_and_filesystem_cleanup`、`recover_on_startup_integration_verify_real_report_drives_consumers_without_user_file_loss`；手工 M-01 | 自动化 PASS gate；M-01 缺失时阻断发布 |
| RS-02 user interruption during batch import | testing 崩溃测试、S1-20 import-progress | Manual smoke | 拖入 100 个文件，进度页显示导入中 | 导入中 `⌘Q` 或 Force Quit，重启 App | 未完成项显示可恢复/可重试状态，不把失败队列标为成功 | 已导入项 FS+DB 一致；未导入项源文件仍可读；无最终目录半成品 | 手工 M-01；Swift `ImportProgressCopyQueueRecoveryTests.swift` 覆盖队列恢复 UI 状态 | P1 manual gate；发布前缺真实冒烟日志即阻断 |
| RS-03 startup staging residue cleanup | error matrix staging recovery、C1-16 | Automated | `.areamatrix/staging/` 有安全 orphan，DB 有 `status='staging'` row | 调用 `recover_on_startup(repo)` | 返回 `RecoveryReport`，清理 safe orphan，回滚 staging row | 不删除 active 文件、README、AREAMATRIX.md 或非 staging 用户文件 | `recover_on_startup_failure_recovery_*`、`recover_on_startup_validation_*` | PASS gate：`cargo test --workspace recovery` |
| RS-04 DB repair after corrupted metadata | error matrix DB、C1-26 | Automated + Manual smoke | `.areamatrix/index.db` 损坏，repo 内有用户文件 | 调用 `repair_metadata(full_rescan=true, preserve_diagnostics_snapshot=true)`；UI 需用户确认 | 先保存 diagnostics snapshot，再重建 metadata 并 reindex | 用户文件内容和 `README.md` 不变；只写 `.areamatrix/` 元数据 | `repair_reindex_metadata_failure_recovery_rebuilds_corrupted_db_after_snapshot`；手工 M-04 | Core repair PASS gate；UI release 需 M-04 |
| RS-05 iCloud placeholder import/list failure | error matrix iCloud、C1-08、C1-25 | Automated + Manual smoke | 源文件或 conflicted copy 是 `.icloud` 占位符 | import/index/list conflicts 遇到 placeholder；真实 iCloud 触发下载再 retry | Core 返回 `ICloudPlaceholder`；Swift 提供 Download & retry / Switch local，不静默合并 | placeholder marker、原文件和 conflicted copy 不被删除或改写 | `import_index_file_failure_recovery_rejects_icloud_marker_without_db_write`、`list_icloud_conflicts_failure_recovery_placeholder_error_keeps_files_and_retries`、`ImportFolderPageIntegrationVerifyTests.testS119DownloadICloudPlaceholdersAndRetry...`；手工 M-02 | 自动化 PASS gate；真实 iCloud M-02 缺失时阻断发布 |
| RS-06 permission denied during import/recovery/repair | error matrix permission、C1-06..C1-08、C1-16、C1-26 | Automated + Manual smoke | 源文件、目标目录、staging 目录或 reindex 文件不可读/不可写 | chmod/TCC 阻断后执行 import、recovery、reindex | 返回 `PermissionDenied`；恢复权限后可重试 | 现有 final、source、DB row 和 staging residue 保持可恢复，不误删 | `import_copy_file_failure_recovery_permission_denied_leaves_no_side_effects`、`import_move_file_failure_recovery_permission_denied_restores_source`、`recover_on_startup_failure_recovery_permission_denied_keeps_retryable_state`、`repair_reindex_metadata_failure_recovery_permission_denied_records_resumable_session`；手工 M-03 | 自动化 PASS gate；真实 TCC M-03 缺失时阻断发布 |
| RS-07 copy/move/index DB failure | transactional import C/D/I、C1-06..C1-08 | Automated | DB insert/change_log/promotion 被 trigger 强制失败 | 执行 Copy、Move 或 Indexed import | 返回 `Db`，可在修复 DB 后重试 | Copy 保留源文件；Move 恢复源文件或保留 recoverable staging；Indexed 不产生 final copy | `import_copy_file_failure_recovery_rolls_back_final_file_when_db_promotion_fails`、`import_move_file_failure_recovery_db_staging_insert_restores_source`、`import_move_file_failure_recovery_failed_attempt_can_be_retried`、`import_index_file_failure_recovery_failed_attempt_can_be_retried` | PASS gate：`cargo test --workspace transactional_import` |
| RS-08 duplicate / overwrite / conflict rollback | error matrix duplicate/conflict、C1-09、C1-10 | Automated | 已有同 hash 或同名目标文件 | Duplicate Ask/Overwrite、同名自动编号或 rename 遇到 DB/permission/conflict failure | 用户选择失败时可重试，旧文件和新源文件保持一致 | 不留下 `name_1.ext` 半成品；旧 active row 不被错误删除 | `detect_duplicate_failure_recovery_moved_ask_restores_source_without_final_side_effects`、`detect_duplicate_failure_recovery_overwrite_db_failure_can_be_retried`、`resolve_name_conflict_failure_recovery_import_db_failure_removes_numbered_final`、`resolve_name_conflict_failure_recovery_moved_exhaustion_restores_source_and_retries` | PASS gate：`cargo test --workspace recovery` |
| RS-09 reindex / repair failure and resume | C1-26、troubleshooting D3/P1 | Automated + Manual smoke | repo 内有用户文件，reindex 中途遇到不可读文件或 corrupted DB | `reindex_from_filesystem` 失败；恢复权限后 `resume_scan_session` | failed scan session 可追踪，resume 后 completed | 用户文件 snapshot 不变；不覆盖 README；不移动最终目录 | `repair_reindex_metadata_failure_recovery_permission_denied_records_resumable_session`、`repair_reindex_metadata_failure_recovery_repeated_reindex_is_idempotent`；手工 M-04 | PASS gate：`cargo test --workspace recovery` |
| RS-10 DB locked vs corrupted mapping | error matrix P1-ER-001、C1-21 | Automated | `CoreError::Db` 可能代表 locked 或 corrupted | 真实 Core mapping 输入 `database is locked` 与 `database disk image is malformed` | locked 返回 `数据库暂时被占用` + `Retryable`；corrupted 返回 `资料库索引损坏` + `Fatal` | 不应因为错误分类误导用户执行危险恢复 | `error_mapping_validation_db_locked_and_corrupted_have_distinct_recovery_paths`、`error_recovery_matrix_error_mapping_records_db_subsemantic_closure`、`testDefaultCoreBridgeMapsDbLockedAndCorruptedToDistinctRecoveryActions` | **P1-ER-001 已关闭**；任一映射测试失败则阻断发布 |

## 3. 手工验证清单

手工项用于补真实系统边界。任一 P0/P1 手工项在 release evidence 中缺失时，发布不通过。

手工证据必须登记为结构化记录，不能只写“已看过”。发布机或发布前测试机
执行后，在 release checklist 中保存每个 `manual_evidence_id` 对应日志。未执行时必须保留
`manual_evidence_status: pending`，并把 Stage 1 release readiness 判为 blocked。

```yaml
manual_evidence_id: M-01
manual_evidence_status: "pending | pass | blocked"
environment:
  macos_version: "<sw_vers -productVersion>"
  app_build: "<AreaMatrix build or test bundle>"
  repo_path: "<test repo path, redacted if needed>"
operator: "<name or release role>"
executed_at: "<ISO-8601 timestamp>"
result: "pending | pass | fail | blocked"
evidence_paths:
  - "<screenshot, log, sqlite output, checksum output, or diagnostics path>"
user_file_invariants:
  source_files_preserved: "pass | fail | not_applicable"
  no_final_half_files: "pass | fail | not_applicable"
  no_wrong_active_rows: "pass | fail | not_applicable"
  no_readme_or_areamatrix_overwrite: "pass | fail | not_applicable"
release_gate: "block_if_missing_or_fail"
```

### M-01 import 中断 / 崩溃恢复

- 初始状态：新建 repo，准备 100 个源文件，包含 PDF、PNG、重复文件和同名文件。
- 触发方式：开始批量 Copy 导入后，在进度页中 `⌘Q`；重复一次 Force Quit。
- 预期恢复：重启后显示恢复/重试状态；不会把未完成项标为成功。
- 用户文件不变量：源目录文件数和内容不减少；repo 最终目录没有半文件；DB 无 `staging`
  row 或存在可解释 recovery report。
- 验证方式：记录重启后的 UI 状态、`sqlite3 .areamatrix/index.db` 中 `files.status`
  分布、`.areamatrix/staging` 列表和源目录 checksum。
- 证据状态：`manual_evidence_id: M-01`；`manual_evidence_status: pass`；M-01 Copy
  中断摘要已通过本机 Release local QA build 手工冒烟。
- 手工证据：
  - `environment.macos_version: 26.4.1`
  - `app_build: build/Build/Products/Release/AreaMatrix.app`，Release local QA build，
    `CODE_SIGNING_ALLOWED=NO`
  - `repo_path: ~/Desktop/AreaMatrix-QA/slow-repo`
  - `source_path: ~/Desktop/AreaMatrix-QA/slow-source`
  - `executed_at: 2026-05-10 21:27 CST`
  - `result: pass`
  - 重启后 UI 显示导入结果摘要：`成功 10 · 停止 0 · 失败 0 · 待处理 234`
  - pending 行原因：`Import not completed before AreaMatrix quit`
  - 源目录保留 `500` 个 `big-*.bin`
  - `.areamatrix/staging` 文件数为 `0`
  - `sqlite3 ... 'PRAGMA integrity_check;'` 返回 `ok`
  - 点击 `Done` 后 `.areamatrix/import-sessions/current.json` 已清除，命令输出
    `session cleared`
- 范围限制：该证据只关闭 Copy 模式的 M-01 未完成摘要恢复；Move 模式中断恢复和自动续跑不在
  本次证据范围内。
- 清理：删除测试 repo 和源目录。

### M-02 iCloud placeholder 下载与重试

- 初始状态：repo 或源文件位于 iCloud Drive，至少一个文件为未下载占位符。
- 触发方式：执行单文件 import、文件夹 import 或 iCloud conflict list；选择 Download & retry。
- 预期恢复：下载完成后 retry 成功；下载失败时仍停留在可恢复错误。
- 用户文件不变量：`.icloud` marker 或真实文件不被静默删除；conflicted copy 不被自动合并。
- 验证方式：记录 `mdls -name kMDItemUbiquitousItemDownloadingStatus`、UI action、retry
  结果、repo 文件和 DB row。
- 证据状态：`manual_evidence_id: M-02`；`manual_evidence_status: blocked`；当前没有
  iCloud placeholder 环境，无法构造真实 iCloud Drive placeholder，不得写成 PASS。
- 手工证据：
  - `executed_at: 2026-05-10 21:27 CST`
  - `result: blocked`
  - `blocked_reason: no iCloud placeholder environment available`
  - 阻断处理：保留 release gate blocked；自动化 iCloud placeholder 覆盖不能替代真实 iCloud 手工冒烟。
- 后续补证模板：
  - `environment.macos_version: <macOS version>`
  - `environment.icloud_drive: enabled`
  - `app_build: <Developer ID notarized app 或明确 local QA app>`
  - `repo_path: <iCloud Drive 内测试 repo 或源文件路径>`
  - `source_placeholder_status.before: mdls -name kMDItemUbiquitousItemDownloadingStatus <path>`
  - `source_placeholder_marker: <.icloud marker 或 Finder 未下载状态截图>`
  - `ui_action: Download & retry`
  - `retry_result: pass | fail`
  - `db_rows: <sqlite query 记录 file/import row>`
  - `user_file_invariants: placeholder marker、原文件和 conflicted copy 不被删除、不被静默合并、不被覆盖`
  - `evidence_paths: <截图、命令输出、DB query、checksum>`
  - `result: pass` 只有在真实 iCloud Drive placeholder 环境完成下载与 retry 后才能填写。
- 清理：将测试文件移出 iCloud 或删除测试 repo。

### M-03 macOS 权限 / TCC 失败

- 初始状态：repo 位于需要 Full Disk Access 或受 ACL 限制的位置。
- 触发方式：撤销权限后执行 import、startup recovery 或 reindex。
- 预期恢复：UI 显示 permission recovery action；恢复权限后 retry 成功。
- 用户文件不变量：无源文件丢失，无 final 半成品，无错误 active row。
- 验证方式：记录系统权限设置、`ls -lae`、错误页 action、恢复权限后的 retry 结果。
- 证据状态：`manual_evidence_id: M-03`；`manual_evidence_status: pass`；M-03 权限恢复
  已通过本机 Release local QA build 手工冒烟。
- 手工证据：
  - `environment.macos_version: 26.4.1`
  - `app_build: build/Build/Products/Release/AreaMatrix.app`，Release local QA build，
    `CODE_SIGNING_ALLOWED=NO`
  - `repo_path: ~/Desktop/AreaMatrix-QA/permission-repo-20260510_221849`
  - `evidence_dir: ~/Desktop/AreaMatrix-QA/m03-evidence-20260510_221849`
  - `executed_at: 2026-05-10 22:21 CST`
  - `result: pass`
  - 触发方式：对 QA repo 根目录施加可逆 POSIX 权限阻断，`ls -lae` 显示
    `d---r-xr-x`，未修改系统 TCC 数据库。
  - UI 显示 `Repository needs permission`，错误码为 `PermissionDenied`，提示
    `AreaMatrix no longer has permission to read this folder.`，主恢复 action 为
    `Reconnect folder`。
  - 恢复权限并重开同一 repo 后回到主列表，`未分类 11`、`文档 1` 和 `50 files`
    可加载。
  - `sqlite3 ... 'PRAGMA integrity_check;'` 返回 `ok`
  - `README.md` 与 `docs/m03-user-file.txt` 权限阻断前后 checksum diff 行数为 `0`
  - `.areamatrix/staging` 文件数为 `0`
  - repo 根目录未生成 `AREAMATRIX.md`
  - App `UserDefaults` repoPath 已恢复为 `~/Desktop/AreaMatrix-QA/slow-repo`
- 清理：还原权限。

### M-04 DB repair / diagnostics

- 初始状态：复制 repo 后损坏 `.areamatrix/index.db`，保留至少一个用户 `README.md`。
- 触发方式：进入 DB repair confirm 页面，选择保留诊断并 full rescan。
- 预期恢复：诊断快照写入 `.areamatrix/diagnostics/`，repair 完成后列表/Tree 可加载。
- 用户文件不变量：`README.md` 与用户文件 checksum 不变；不写根目录 `AREAMATRIX.md`。
- 验证方式：记录 diagnostics 路径、`PRAGMA integrity_check`、Tree/List 状态和 checksum。
- 证据状态：`manual_evidence_id: M-04`；`manual_evidence_status: pass`；M-04 DB repair
  已通过本机 Release local QA build 手工冒烟。
- 手工证据：
  - `environment.macos_version: 26.4.1`
  - `app_build: build/Build/Products/Release/AreaMatrix.app`，Release local QA build，
    `CODE_SIGNING_ALLOWED=NO`
  - `repo_path: ~/Desktop/AreaMatrix-QA/db-repair-repo`
  - `evidence_dir: ~/Desktop/AreaMatrix-QA/m04-evidence-20260510_213637`
  - `executed_at: 2026-05-10 21:58 CST`
  - `result: pass`
  - UI 先显示 `Repository metadata needs repair`，安全确认后执行 `Run Full Rescan`
  - 修复完成后回到主列表，`未分类 11 files` 可加载
  - diagnostics snapshot 写入 `.areamatrix/diagnostics/index-1778421523-2695bbce-82b9-4ea6-9b33-ad02eb06f1d8.db`
  - `sqlite3 ... 'PRAGMA integrity_check;'` 返回 `ok`
  - `README.md` 与 `docs/m04-user-file.txt` 修复前后 checksum diff 行数为 `0`
  - repo 根目录未生成 `AREAMATRIX.md`
  - App `UserDefaults` repoPath 已恢复为 `~/Desktop/AreaMatrix-QA/slow-repo`
- 清理：删除测试 repo。

## 4. 发布阻断结论

已关闭的阻断项：

- `P1-ER-001 已关闭`：DB locked 与 DB corrupted 已通过真实 Core mapping 区分。
  `database is locked` 映射为 `数据库暂时被占用` + medium + `Retryable`；
  `database disk image is malformed` 映射为 `资料库索引损坏` + critical + `Fatal`。
  Swift `CoreBridge().mapCoreError` 消费该映射后，locked 走 Retry，corrupted 走 Open repair。

条件阻断项：

- M-01 Copy 模式手工日志已采集并通过，但 Move 模式中断恢复和自动续跑不在本次 M-01 证据范围内。
- M-02 当前为环境 `blocked`，真实 iCloud placeholder 手工冒烟未完成。
- M-03 权限恢复手工日志已采集并通过；本次使用 local QA repo 的可逆 POSIX 权限阻断模拟失去访问权限，
  未修改系统 TCC 数据库。
- M-04 DB repair / diagnostics 手工日志已采集并通过。
- 当前 `manual_evidence_status: pending` 或 `manual_evidence_status: blocked` 表示发布证据未采集完成；不得将
  Stage 1 release readiness 写成 PASS。
- 本文列出的自动化测试任一失败时，Stage 1 发布不通过。
- 如果 validation 只能跑 dry-run 或只验证 prompt 体系，不能替代上述恢复证据。

## 5. 回滚与验证

本任务只新增恢复证据文档和测试。回滚时撤销：

- `docs/development/recovery-scenarios.md`
- `core/tests/recovery_scenarios.rs`

`3-1/task-01` 已落地的 error recovery matrix、DB 子语义映射和 Swift
CoreBridge 映射测试是本清单的输入证据，不属于本任务回滚范围。

必须运行：

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
cargo test --workspace recovery
cargo test --workspace transactional_import
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

若从仓库根目录运行 `cargo test --workspace ...` 因缺少根 `Cargo.toml` 失败，使用：

```bash
cd core && cargo test --workspace recovery
cd core && cargo test --workspace transactional_import
```

并在报告中记录原命令失败原因和等价 Rust 证据。

## Related

- [error-recovery-matrix.md](error-recovery-matrix.md)
- [testing.md](testing.md)
- [troubleshooting.md](troubleshooting.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
