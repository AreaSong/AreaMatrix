# AreaMatrix 全仓错误、并发、取消、重试与生命周期审计

## 结论

**结果：`BLOCKED / NOT-READY`。** 冻结范围的 5092 个文件已全部完成状态归类且统计守恒，但只有 73 个文本文件完成全文人工逐行审阅，另有 51 个文本文件只完成部分区间；其余未获豁免的文件保持 `BLOCKED`。因此本报告不是“全仓逐行审计通过”，也不是 merge/release approval。

静态审阅确认 10 条 finding：P0=4、P1=2、P2=3、P3=1。最高风险集中在初始化 cleanup/rollback、overview 原子写/CAS 和用户文件 ownership。

## Findings

### [P0] RUST-INIT-CLEANUP-001 - 初始化预检会删除仅凭名称和目录形状推断为残留的用户目录

- 置信度/状态：`high` / `FINDING`
- 证据：`core/src/repo_init.rs:198-218` `preflight_create_empty`; `core/src/repo_init.rs:230-250` `preflight_adopt_existing`; `core/src/repo_init.rs:253-330` `cleanup_recoverable_init_dirs`
- 入口与链路：`init_repo(CreateEmpty|AdoptExisting)` -> `init_repo` -> `preflight_create_empty/preflight_adopt_existing` -> `cleanup_recoverable_init_dirs` -> `is_recoverable_init_dir` -> `fs::remove_dir_all`
- 失败或交错：资料库根中只要存在以 .areamatrix.init- 开头且内容满足宽松形状检查的目录（空目录也满足），预检就递归删除；没有 operation UUID、creator marker、journal identity 或内容 hash 证明该目录属于 AreaMatrix。
- 实际影响：可递归删除用户创建或同步进来的目录及其内容，直接违反接管已有目录不得删除用户文件的不变量。
- 最小修复：创建 init staging 时写入不可伪造/可核验的 operation marker 与 manifest；恢复仅接受已知 UUID/journal 且逐项校验的路径，未知或无 marker 的目录 fail closed 并报告。
- 回滚原则：修复只收紧清理条件；若新条件产生兼容性问题，可保留目录并提示人工恢复，不能回退到形状推断删除。
- 建议验证：临时目录中放置同名前缀空目录/内部形状用户目录，断言预检保留；已签名真实 residue 可幂等清理；symlink/未知条目 fail closed
- 确认边界：静态代码已确认；无需真实用户资料库。

### [P0] RUST-INIT-ROLLBACK-001 - CreateEmpty 在 metadata commit 后失败会无条件删除并发写入的 metadata 和根文件

- 置信度/状态：`medium-high` / `FINDING`
- 证据：`core/src/repo_init.rs:97-149` `init_create_empty_repo/init_create_empty_inner`; `core/src/repo_init.rs:188-195` `commit_metadata_staging`; `core/src/repo_init.rs:407-462` `InitRollback::rollback`
- 入口与链路：`init_repo(CreateEmpty)` -> `commit_metadata_staging` -> `create_default_category_dirs/write_root_areamatrix_file/record_initialized_overview_provenance` -> `InitRollback::rollback` -> `remove_file/remove_dir_all`
- 失败或交错：线程 A rename 安装 .areamatrix 后继续执行分类/概览/provenance；线程 B 或同步进程写入 .areamatrix 或编辑刚创建的 AREAMATRIX.md；A 后续失败后不校验 inode、hash、目录新增项或 operation id 就删除。
- 实际影响：并发写入的 metadata、用户对根 AREAMATRIX.md 的编辑或其他新内容可能被删除。清理错误还被忽略，调用方无法区分安全回滚和残留。
- 最小修复：commit 后使用持久 operation manifest/identity；rollback 逐项校验 inode/hash/内容清单，发现未知变化立即停止并返回 recoverable state；记录清理失败。
- 回滚原则：保留 metadata 并转入 startup recovery 比递归删除更安全；回退时不得恢复无条件删除。
- 建议验证：commit 后注入 provenance 失败并并发新增 metadata 文件；commit 后编辑根文件再触发失败；断言未知变化被保留并报告
- 确认边界：静态删除路径已确认；交错复现需要故障注入。

### [P0] RUST-OVERVIEW-ATOMIC-001 - 概览原子写使用固定临时名并跟随 symlink，回滚也存在 symlink TOCTOU

- 置信度/状态：`high` / `FINDING`
- 证据：`core/src/overview/mod.rs:494-506` `write_atomic_replace`; `core/src/overview/atomic_write.rs:19-31` `write_plans_with_rollback`; `core/src/overview/atomic_write.rs:45-69` `FileSnapshot::capture/restore`
- 入口与链路：`任一 incremental/full overview 写入` -> `write_plans_with_rollback` -> `write_atomic_replace` -> `fs::write(<target>.md.tmp)` -> `fs::rename`
- 失败或交错：攻击者或同步进程预先把固定 <target>.md.tmp 建成 symlink，fs::write 会跟随并截断链接目标；并发 writer 也共享同一 tmp。后续 plan 失败时，snapshot 与 restore 之间若目标被换成 symlink，fs::write(path, bytes) 再次跟随链接。
- 实际影响：可覆盖资料库外当前用户有权限写入的文件；并发 writer 可互删 tmp、产生失败或让最终内容/provenance 与 operation 不一致。
- 最小修复：在受控目录使用 UUID 临时文件 + OpenOptions::create_new + O_NOFOLLOW/等价安全打开；sync 后原子替换；restore 前复核 regular-file identity 与预期 hash，拒绝 symlink/特殊文件。
- 回滚原则：若平台不支持安全替换，fail closed 并保留 journal，不使用 fs::write 回滚。
- 建议验证：预置 tmp symlink 指向外部 sentinel，断言 sentinel 不变；snapshot 后换 symlink 的故障注入；两 writer barrier 交错测试
- 确认边界：symlink sink 静态确认；跨平台行为需 macOS/Linux/Windows fixture 验证。

### [P0] RUST-OVERVIEW-CAS-001 - 增量概览的 provenance 检查与最终替换之间无 CAS，可覆盖根文件并发用户编辑

- 置信度/状态：`high` / `FINDING`
- 证据：`core/src/overview/mod.rs:70-135` `regenerate_external_sync_overviews`; `core/src/overview/mod.rs:158-179` `ensure_incremental_targets_trusted`; `core/src/overview/mod.rs:494-506` `write_atomic_replace`
- 入口与链路：`regenerate_for_node / external sync overview refresh` -> `读取 DB/目标并构建完整 WritePlan` -> `ensure_incremental_targets_trusted` -> `write_plans_with_rollback` -> `rename 覆盖目标` -> `record_provenance`
- 失败或交错：A 验证旧 hash 与 managed block 后暂停；B 修改 AREAMATRIX.md managed block 外用户正文；A 用基于旧内容生成的整文件临时副本 rename 覆盖 B。两个 Core writer 也可同时通过旧 provenance。
- 实际影响：根 AREAMATRIX.md managed block 外用户内容丢失；生成文件与 provenance 也可能漂移。
- 最小修复：最终替换前重新读取并比较目标 identity/hash；对根文件基于最新内容重新合并 managed block；按 repo/target 串行化并持久化 operation identity。
- 回滚原则：CAS 冲突时保留用户当前文件并返回 Conflict，不回写旧 snapshot。
- 建议验证：在 provenance check 后编辑根文件并 barrier 继续；并发两次不同 locale/node 更新；断言冲突且用户文本不变
- 确认边界：静态 TOCTOU 已确认；确定性交错测试尚未运行。

### [P1] RUST-BATCH-FSDB-001 - 批量 rename/category 在 SQLite transaction 内先移动文件，硬崩溃后无持久恢复

- 置信度/状态：`high` / `FINDING`
- 证据：`core/src/batch_rename/apply.rs:12-33` `apply_batch_rename_plan`; `core/src/batch_rename/apply.rs:168-215` `try_apply_change`; `core/src/batch_rename/apply.rs:293-350` `AppliedFsRename/RenameRollbackGuard`; `core/src/batch_category/apply.rs:18-39` `apply_batch_category_plan`; `core/src/batch_category/apply.rs:239-289` `try_apply_change`; `core/src/batch_category/fs_move.rs:52-111` `AppliedFsMove/MoveRollbackGuard`; `core/src/db/rename.rs:130-141` `with_batch_rename_transaction`; `core/src/db/move_to_category.rs:85-96` `with_batch_category_transaction`
- 入口与链路：`batch_rename / batch_move_to_category` -> `打开 SQLite transaction` -> `closure 内移动文件/sidecar` -> `更新 row/change log/undo` -> `commit transaction` -> `disarm RAII guards`
- 失败或交错：文件移动后、DB commit 前进程崩溃/SIGKILL/断电；Drop 不执行。正常 commit/closure 错误时 Drop 的 rollback 错误也被忽略。startup recovery 没有对应 batch journal。
- 实际影响：DB 仍指向旧路径而文件已移动，可能长期列表缺失、后续 sync/retry 误处理或重复操作；transaction 生命周期跨越了无法与 SQLite 原子提交的 FS mutation。
- 最小修复：FS 变更前持久化 operation journal；使用短事务 reservation/CAS，执行 FS，再用短事务 promote；startup recovery roll-forward/rollback；持久记录 rollback failure。
- 回滚原则：新流程失败时保留 journal 和文件，不尝试无证据删除；可用 feature flag 回退到只读预览但不能回退到无 journal 写。
- 建议验证：在每个 FS move 后强制终止子进程；重启执行 startup recovery；注入 rollback IO failure；检查 DB integrity/path/change log/sidecar
- 确认边界：事务/FS 顺序静态确认；硬崩溃恢复需子进程故障注入。

### [P1] IOS-ERROR-MAPPING-001 - iOS 多条链路绕过结构化 ErrorMapping，直接显示 Core/SQLite 技术文本

- 置信度/状态：`high` / `FINDING`
- 证据：`apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreFFI.swift:90-106` `MobileFileDetailCoreSDKMapping.error`; `apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreBridge.swift:111-137` `MobileFileDetailError.message/map`; `apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreFFI.swift:82-96` `MobileLibraryCoreSDKMapping.error`; `apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreBridge.swift:135-173` `MobileLibraryQueryError`; `apps/ios/AreaMatrix/Features/Onboarding/MobileRepositoryCoreFFI.swift:270-287` `mapError`; `apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift:396-400` `connectionError`; `apps/ios/AreaMatrix/Features/Library/MobileLibraryView.swift:82-93,433-438` `LibraryListViewModel.reload/errorSection`
- 入口与链路：`iOS connect/list/detail Core calls` -> `AreaMatrixCoreSDK.CoreError` -> `feature-local switch or default String(describing:)` -> `feature error String` -> `SwiftUI Label/Text`
- 失败或交错：Db/DbLocked/DbCorrupted 被合并为带原始 message 的 .database；其他未列举 variants 变成 String(describing: coreError) 或 localizedDescription。UI 直接显示该字符串，未调用 map_core_error，也没有 code/severity/recoverability/recovery_action_ids。
- 实际影响：损坏 DB 可能无法进入阻断 repair，locked/corrupt 恢复动作混淆；绝对路径、SQLite 文本或内部错误可能直接暴露给用户。
- 最小修复：统一复用 CoreErrorMappingSnapshot/AppSemanticError；feature state 保存稳定 descriptor，View 通过 AppLocalizer 解析；技术详情单独受控展示，按 recovery_action_ids 提供真实动作。
- 回滚原则：保留旧 feature enum 作为适配层时也必须承载 mapping snapshot，不能回退到 raw String。
- 建议验证：18 个 CoreError variant 的 iOS mapping table test；DbLocked 显示 Retry，DbCorrupted 路由 Repair；路径/用户名不出现在普通 UI；en/zh-Hans 同一 retained state
- 确认边界：所列三条 UI 链静态确认；其余 iOS consumer 尚未逐文件审完。

### [P2] IOS-DETAIL-STALE-001 - iOS 详情重复刷新无 generation，旧请求可覆盖新状态

- 置信度/状态：`high` / `FINDING`
- 证据：`apps/ios/AreaMatrix/Features/Detail/MobileFileDetailModel.swift:95-147` `reloadMetadata/reloadChangeLog/reloadNote`; `apps/ios/AreaMatrix/Features/Detail/MobileFileDetailView.swift:37-50,75-82,110-123` `toolbar/.task/retry callbacks`; `apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreBridge.swift:141-161` `LiveMobileRepositoryCoreBridge`
- 入口与链路：`刷新按钮、Retry、segment 切换和 view .task` -> `独立 Task` -> `@MainActor model reload` -> `await Task.detached FFI` -> `无 identity 检查写 Published state`
- 失败或交错：A 先发起但慢，B 后发起且先完成写入新结果，A 随后完成并覆盖。刷新按钮在 loading 时未禁用。
- 实际影响：详情、日志或笔记显示旧数据/旧错误；页面销毁或快速交互后的晚到结果可污染仍被持有的 model。
- 最小修复：三类请求分别保存 Task 或递增 generation；新请求替换旧请求，completion 前同时检查 generation、fileID/segment 与 cancellation。
- 回滚原则：generation 仅影响呈现提交；底层不可取消调用仍可安全完成，不需要强杀 Rust。
- 建议验证：可控 continuation 让第二次请求先完成；取消 view task 后释放结果；断言旧 completion 不写 state
- 确认边界：静态交错已确认；iOS XCTest 未运行。

### [P2] IOS-CONNECT-STALE-001 - iOS 资料库连接与外部 URL 入口共享状态但没有请求身份校验

- 置信度/状态：`medium-high` / `FINDING`
- 证据：`apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift:47-99,105-179,137-232` `connect/reconnect/handleOpenURL`; `apps/ios/AreaMatrix/App/AreaMatrixIOSApp.swift:48-50` `onOpenURL`; `apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift:145-160,263-307` `recent/picker/retry callbacks`
- 入口与链路：`folder picker/reconnect/retry 与 app onOpenURL share-import` -> `独立 Task` -> `beginChecking` -> `security-scoped access` -> `validate/cloud/config/bookmark awaits` -> `写 route/error/latestValidation/latestCloudState`
- 失败或交错：正常按钮在 isChecking 时禁用，但系统 onOpenURL 可在现有连接流程等待期间启动另一条任务；两条任务没有 UUID、URL 匹配或 Task identity，旧 completion 可覆盖新 route。
- 实际影响：打开错误资料库/确认页、把旧错误覆盖新连接、或让 share-import takeover 与手工选择互相覆盖。
- 最小修复：连接 operation 使用 generation/UUID 和规范化 URL；每个 await 后 guard 当前 identity；新操作取消旧 Swift task并在 completion 丢弃旧结果。
- 回滚原则：取消只阻止呈现提交，defer 继续释放 security scope；不强制中断同步 Core。
- 建议验证：onOpenURL 与 picker 两条受控 continuation 反序完成；dismiss 后晚到 completion；断言 scope stop 各执行一次且 route 属于最新请求
- 确认边界：可达入口和无 identity 静态确认；真实 iOS lifecycle 仍需验证。

### [P2] MACOS-OVERVIEW-STALE-001 - macOS overview language status load 无 generation，快速语言变化会旧结果回写

- 置信度/状态：`high` / `FINDING`
- 证据：`apps/macos/AreaMatrix/Features/Settings/RepositoryOverviewRegenerationModel.swift:101-113` `load(contentLocale:)`; `apps/macos/AreaMatrix/Features/Settings/LanguageSettingsPane.swift:81-87,334-340` `task/onChange/refreshOverviewStatus`
- 入口与链路：`LanguageSettingsPane .task 与 interface-language onChange` -> `独立 Task` -> `model.load(locale)` -> `await overviewLanguageStatus` -> `无 locale/generation guard 写 languageStatus/phase`
- 失败或交错：locale A 请求先开始后变慢；locale B 请求完成并写新状态；A 返回后覆盖 B。load 也没有检查当前 phase，可能干扰另一 operation 的呈现。
- 实际影响：设置页显示错误目标语言/同步状态，可能诱导用户对错误 locale 进入 regeneration preflight。
- 最小修复：load 使用 generation/Task identity，completion 校验 locale 和 phase；新 load 取消旧 Swift task。
- 回滚原则：只丢弃旧 completion，不取消已经开始的 Core 读取。
- 建议验证：A/B locale 受控反序 completion；页面消失/语言切换取消；断言 prepare 使用当前 concrete locale
- 确认边界：静态交错已确认；macOS XCTest/UI 未运行。

### [P3] DOTNET-CANCELLATION-001 - Windows/Linux PlatformDifferences 把 OperationCanceledException 映射为普通失败

- 置信度/状态：`high` / `FINDING`
- 证据：`apps/windows/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs:179-226` `LoadCapabilitiesAsync/InspectContractAsync`; `apps/linux/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs:182-231` `LoadCapabilitiesAsync/InspectContractAsync`
- 入口与链路：`PlatformDifferences load/check APIs` -> `caller token` -> `bridge async call` -> `OperationCanceledException` -> `catch(Exception)` -> `Failed/error UI state`
- 失败或交错：两个平台的 catch(Exception) 未排除 OperationCanceledException；finally 清 busy 后，上层无法再识别取消。
- 实际影响：页面关闭、目标切换或上层取消可显示虚假失败并覆盖后续有效状态。
- 最小修复：catch OperationCanceledException 后重新抛出或恢复中性状态；普通 catch 使用 when filter。
- 回滚原则：无持久副作用；恢复旧行为仅影响呈现，不应自动重试。
- 建议验证：预取消 token；等待中取消 token；断言 OCE 传播且无失败文案
- 确认边界：静态 catch 路径已确认；平台 UI runtime 未运行。

## 覆盖与守恒

| 指标 | 数量/结果 |
| --- | --- |
| 冻结文件总数 | 5092 |
| 文本文件 / 文本行 | 4930 / 1533156 |
| PASS | 65 |
| FINDING（全文已读文件） | 8 |
| NOT_APPLICABLE | 1509 |
| BLOCKED | 3510 |
| PENDING / IN_PROGRESS | 0 / 0 |
| 人工已读行（含部分文件区间） | 20922 |
| 有证据豁免的文本行 | 778494 |
| BLOCKED 未读文本行 | 733740 |
| 守恒 | 5092 = 65 + 8 + 1509 + 3510 = 5092 |

逐文件路径、类型、行数、是否生产路径、精确已读区间、审阅者/复核者、时间、入口/调用方/被调用方/状态对象、证据和阻断原因见 `inventory.jsonl` 与 `coverage.jsonl`。`NOT_APPLICABLE` 逐项记录 symlink target、生成链或二进制来源/消费边界；没有按目录静默跳过。

### 冻结范围漂移

审计启动后的路径/类型/内容复核发现 91 个冻结文件发生漂移；任何漂移文件都保持 `BLOCKED`，当前版本不与冻结审阅证据混用。

生产路径漂移：67 个

- `apps/ios/AreaMatrix/Features/Import/ShareImportExtensionScene.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportModel.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportQueue.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportView.swift`
- `apps/ios/AreaMatrix/Features/Settings/RepositorySettingsView.swift`
- `apps/ios/AreaMatrixShareExtension/ShareImportViewController.swift`
- `apps/ios/AreaMatrixTests/ShareImportModelTests.swift`
- `apps/linux/AreaMatrix/Features/Settings/RepositorySettingsViewModel.cs`
- `apps/linux/AreaMatrix/Features/System/LinuxWatcherDiagnostics.cs`
- `apps/linux/AreaMatrixTests/Settings/RepositorySettingsViewModelTests.cs`
- `apps/macos/AreaMatrix/App/RepositoryIgnoreRulesManager.swift`
- `apps/macos/AreaMatrix/Features/Import/ImportBatchConflictSection.swift`
- `apps/macos/AreaMatrix/Features/Onboarding/ValidatePathChecklistSection.swift`
- `apps/macos/AreaMatrix/Features/Onboarding/WelcomeStepView.swift`
- `apps/macos/AreaMatrix/PlatformServices/ImportBatchSessionPlatformServices.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixAmbientBackground.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixClassificationDiorama.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixOverlays.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixProtectionDiorama.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixSceneComponents.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixTimelineDiorama.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixWorkflowDiorama.swift`
- `apps/macos/AreaMatrixTests/ImportBatchDuplicateResolutionTests.swift`
- `apps/macos/AreaMatrixTests/ImportProgressInterruptedSessionTests.swift`
- `apps/macos/AreaMatrixTests/LocalFileURLOpenerTests.swift`
- `apps/macos/AreaMatrixTests/Observability/ObservabilityRuntimeSchedulingTests.swift`
- `apps/macos/AreaMatrixTests/Observability/ObservabilityRuntimeTestSupport.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SceneMotionComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedActionComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedFeatureCardComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedMotionComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedTextEffects.swift`
- `apps/macos/Packages/AreaMatrixModules/Tests/AreaMatrixUIFoundationTests/SharedButtonComponentsTests.swift`
- `apps/windows/AreaMatrix/Features/Library/WatcherStatusView.xaml.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.Snapshot.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsWatcherDiagnostics.cs`
- `apps/windows/AreaMatrix/Features/Onboarding/ChooseRepositoryView.xaml`
- `apps/windows/AreaMatrix/Features/Onboarding/OneDriveNoticeDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Onboarding/RepositoryAdoptConfirmDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Onboarding/RepositoryInitConfirmDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Recovery/MissingFileRecoveryDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Settings/RepositorySettingsViewModel.cs`
- `apps/windows/AreaMatrix/MainWindow.xaml.cs`
- `apps/windows/AreaMatrixTests/Architecture/ViewModelSynchronizationContextTests.cs`
- `apps/windows/AreaMatrixTests/AreaMatrix.Windows.Tests.csproj`
- `apps/windows/AreaMatrixTests/ChooseRepository/ChooseRepositoryViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/ChooseRepository/OneDriveNoticeViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/ChooseRepository/RepositoryAdoptConfirmViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/ChooseRepository/RepositoryInitConfirmViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/DesktopMainQuery/DesktopMainQuerySmokeTests.cs`
- `apps/windows/AreaMatrixTests/DesktopMainQuery/DesktopMainQueryViewModelTests.cs`
- `core/src/domain/icloud.rs`
- `core/src/icloud_conflicts.rs`
- `core/src/icloud_conflicts/paths.rs`
- `core/src/icloud_conflicts/preview.rs`
- `core/src/icloud_conflicts/resolve.rs`
- `core/src/icloud_conflicts/types.rs`
- `core/src/storage/replacement_trash.rs`
- `core/src/storage/safe_move.rs`
- `scripts/dev_tools/codex_os_automation.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/release.py`
- `scripts/dev_tools/test_release_tools.py`
- `scripts/dev_tools/test_workflow_hardening.py`
- `scripts/task_loop/runner.py`

非生产/审计材料漂移：24 个

- `.codex/runtime/ci-governance-release-recovery-audit-20260820/blocked-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/coverage.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/final-report.md`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/findings.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/governance-controls.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/inventory.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/recovery-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/release-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/remote-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/residual-reconciliation.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/review-notes.md`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/scope.json`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/task-loop-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/workflow-matrix.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/coverage.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/dependency-ledger.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/final-report.md`
- `.codex/runtime/dependency-supply-chain-audit-20260820/findings.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/license-ledger.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/review-notes.md`
- `.codex/runtime/dependency-supply-chain-audit-20260820/scope.json`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/inventory.jsonl`
- `.codex/runtime/performance-reliability-audit-20260820/coverage.jsonl`
- `.codex/runtime/performance-reliability-audit-20260820/findings.jsonl`

冻结路径缺失：0

- 无

冻结后移除（路径集合差异）：0

- 无

- `.codex/runtime/ci-governance-release-recovery-audit-20260820/blocked-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/coverage.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/final-report.md`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/findings.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/governance-controls.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/inventory.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/recovery-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/release-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/remote-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/residual-reconciliation.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/review-notes.md`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/scope.json`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/task-loop-evidence.jsonl`
- `.codex/runtime/ci-governance-release-recovery-audit-20260820/workflow-matrix.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/coverage.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/dependency-ledger.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/final-report.md`
- `.codex/runtime/dependency-supply-chain-audit-20260820/findings.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/license-ledger.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/review-notes.md`
- `.codex/runtime/dependency-supply-chain-audit-20260820/scope.json`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/inventory.jsonl`
- `.codex/runtime/performance-reliability-audit-20260820/coverage.jsonl`
- `.codex/runtime/performance-reliability-audit-20260820/findings.jsonl`
- `apps/ios/AreaMatrix/Features/Import/ShareImportExtensionScene.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportModel.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportQueue.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportView.swift`
- `apps/ios/AreaMatrix/Features/Settings/RepositorySettingsView.swift`
- `apps/ios/AreaMatrixShareExtension/ShareImportViewController.swift`
- `apps/ios/AreaMatrixTests/ShareImportModelTests.swift`
- `apps/linux/AreaMatrix/Features/Settings/RepositorySettingsViewModel.cs`
- `apps/linux/AreaMatrix/Features/System/LinuxWatcherDiagnostics.cs`
- `apps/linux/AreaMatrixTests/Settings/RepositorySettingsViewModelTests.cs`
- `apps/macos/AreaMatrix/App/RepositoryIgnoreRulesManager.swift`
- `apps/macos/AreaMatrix/Features/Import/ImportBatchConflictSection.swift`
- `apps/macos/AreaMatrix/Features/Onboarding/ValidatePathChecklistSection.swift`
- `apps/macos/AreaMatrix/Features/Onboarding/WelcomeStepView.swift`
- `apps/macos/AreaMatrix/PlatformServices/ImportBatchSessionPlatformServices.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixAmbientBackground.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixClassificationDiorama.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixOverlays.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixProtectionDiorama.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixSceneComponents.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixTimelineDiorama.swift`
- `apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixWorkflowDiorama.swift`
- `apps/macos/AreaMatrixTests/ImportBatchDuplicateResolutionTests.swift`
- `apps/macos/AreaMatrixTests/ImportProgressInterruptedSessionTests.swift`
- `apps/macos/AreaMatrixTests/LocalFileURLOpenerTests.swift`
- `apps/macos/AreaMatrixTests/Observability/ObservabilityRuntimeSchedulingTests.swift`
- `apps/macos/AreaMatrixTests/Observability/ObservabilityRuntimeTestSupport.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SceneMotionComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedActionComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedFeatureCardComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedMotionComponents.swift`
- `apps/macos/Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/SharedTextEffects.swift`
- `apps/macos/Packages/AreaMatrixModules/Tests/AreaMatrixUIFoundationTests/SharedButtonComponentsTests.swift`
- `apps/windows/AreaMatrix/Features/Library/WatcherStatusView.xaml.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.Snapshot.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.cs`
- `apps/windows/AreaMatrix/Features/Library/WindowsWatcherDiagnostics.cs`
- `apps/windows/AreaMatrix/Features/Onboarding/ChooseRepositoryView.xaml`
- `apps/windows/AreaMatrix/Features/Onboarding/OneDriveNoticeDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Onboarding/RepositoryAdoptConfirmDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Onboarding/RepositoryInitConfirmDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Recovery/MissingFileRecoveryDialog.xaml.cs`
- `apps/windows/AreaMatrix/Features/Settings/RepositorySettingsViewModel.cs`
- `apps/windows/AreaMatrix/MainWindow.xaml.cs`
- `apps/windows/AreaMatrixTests/Architecture/ViewModelSynchronizationContextTests.cs`
- `apps/windows/AreaMatrixTests/AreaMatrix.Windows.Tests.csproj`
- `apps/windows/AreaMatrixTests/ChooseRepository/ChooseRepositoryViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/ChooseRepository/OneDriveNoticeViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/ChooseRepository/RepositoryAdoptConfirmViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/ChooseRepository/RepositoryInitConfirmViewSmokeTests.cs`
- `apps/windows/AreaMatrixTests/DesktopMainQuery/DesktopMainQuerySmokeTests.cs`
- `apps/windows/AreaMatrixTests/DesktopMainQuery/DesktopMainQueryViewModelTests.cs`
- `core/src/domain/icloud.rs`
- `core/src/icloud_conflicts.rs`
- `core/src/icloud_conflicts/paths.rs`
- `core/src/icloud_conflicts/preview.rs`
- `core/src/icloud_conflicts/resolve.rs`
- `core/src/icloud_conflicts/types.rs`
- `core/src/storage/replacement_trash.rs`
- `core/src/storage/safe_move.rs`
- `scripts/dev_tools/codex_os_automation.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/release.py`
- `scripts/dev_tools/test_release_tools.py`
- `scripts/dev_tools/test_workflow_hardening.py`
- `scripts/task_loop/runner.py`

另有 40 个文件在冻结后新增；只有 `.codex/runtime/**` 新增材料不纳入本次 5092 文件分母，其他新增会使收口保持 `BLOCKED`：

- `.codex/runtime/ci-governance-release-recovery-audit-20260820/build_coverage.rb`
- `.codex/runtime/cross-platform-e2e-audit-20260820/blocked-evidence.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/bridge-contracts.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/build_ledger.py`
- `.codex/runtime/cross-platform-e2e-audit-20260820/coverage.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/final-report.md`
- `.codex/runtime/cross-platform-e2e-audit-20260820/findings.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/inventory.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/platform-matrix.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/review-notes.md`
- `.codex/runtime/cross-platform-e2e-audit-20260820/runtime-evidence.jsonl`
- `.codex/runtime/cross-platform-e2e-audit-20260820/scope.json`
- `.codex/runtime/cross-platform-e2e-audit-20260820/workflow-matrix.jsonl`
- `.codex/runtime/dependency-supply-chain-audit-20260820/_synthesize.py`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/api-contracts.jsonl`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/bridge-symbols.jsonl`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/close_ledger.py`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/enrich-inventory.py`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/final-report.md`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/findings.jsonl`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/generated-artifacts.jsonl`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/record_asset_provenance.py`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/record_review.py`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/review-decisions.jsonl`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/review-notes.md`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/source-map.jsonl`
- `.codex/runtime/docs-api-bridge-drift-audit-20260820/wording-audit.jsonl`
- `.codex/runtime/performance-reliability-audit-20260820/finding-014.json`
- `.codex/runtime/performance-reliability-audit-20260820/finding-015.json`
- `.codex/runtime/performance-reliability-audit-20260820/finding-016.json`
- `.codex/runtime/performance-reliability-audit-20260820/finding-017.json`
- `.codex/runtime/performance-reliability-audit-20260820/finding-018.json`
- `.codex/runtime/performance-reliability-audit-20260820/main-root-semantic.tsv`
- `.codex/runtime/performance-reliability-audit-20260820/swift-agent-semantic-next5-reviewed.tsv`
- `apps/ios/AreaMatrix/Features/Import/ShareImportExtensionLifecycle.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportRepositoryAccess.swift`
- `apps/ios/AreaMatrixTests/ShareImportModelTestSupport.swift`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.RepositoryLoad.cs`
- `apps/windows/AreaMatrix/MainWindow.RouteTransitions.cs`
- `core/src/icloud_conflicts/token.rs`

冻结后非审计 runtime 新增：

- `apps/ios/AreaMatrix/Features/Import/ShareImportExtensionLifecycle.swift`
- `apps/ios/AreaMatrix/Features/Import/ShareImportRepositoryAccess.swift`
- `apps/ios/AreaMatrixTests/ShareImportModelTestSupport.swift`
- `apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.RepositoryLoad.cs`
- `apps/windows/AreaMatrix/MainWindow.RouteTransitions.cs`
- `core/src/icloud_conflicts/token.rs`

## CoreError 端到端覆盖

Core 的 18 个 variant、稳定 code、severity、recoverability 与 recovery action 已在 `core/src/error/**` 全文核对；但 UDL、所有 producer 和所有 macOS/iOS/Windows/Linux 消费路径没有全部逐行闭环，所以每一行端到端状态均为 `BLOCKED`，不能把 Core mapping PASS 外推为 UI PASS。详细证据见 `error-contracts.jsonl`。

| Variant | Code | Severity | Recoverability | Actions | E2E |
| --- | --- | --- | --- | --- | --- |
| Io | io_error | medium | Retryable | retry, collect_diagnostics | BLOCKED |
| Db | database_error | high | UserActionRequired | collect_diagnostics, open_recovery | BLOCKED |
| DbLocked | database_locked | medium | Retryable | retry, collect_diagnostics | BLOCKED |
| DbCorrupted | database_corrupted | critical | Fatal | open_recovery, collect_diagnostics | BLOCKED |
| Config | config_error | medium | UserActionRequired | open_settings, review_configuration | BLOCKED |
| Validation | validation_error | low | UserActionRequired | fix_input | BLOCKED |
| Classify | classification_error | low | RefreshRequired | open_classifier, refresh | BLOCKED |
| Conflict | conflict | medium | UserActionRequired | review_conflict, reload_latest | BLOCKED |
| RevisionConflict | revision_conflict | medium | UserActionRequired | review_changes, reload_latest | BLOCKED |
| DuplicateFile | duplicate_file | low | UserActionRequired | skip, keep_both, review_replace | BLOCKED |
| FileNotFound | file_not_found | low | RefreshRequired | refresh, locate_file | BLOCKED |
| ExpiredAction | expired_action | low | RefreshRequired | refresh_history | BLOCKED |
| RepoNotInitialized | repository_not_initialized | high | UserActionRequired | initialize_repository, choose_repository | BLOCKED |
| InvalidPath | invalid_path | low | UserActionRequired | change_path | BLOCKED |
| ICloudPlaceholder | icloud_placeholder_not_downloaded | medium | Retryable | download_and_retry, choose_local_repository | BLOCKED |
| StagingRecoveryRequired | staging_recovery_required | high | UserActionRequired | open_recovery | BLOCKED |
| PermissionDenied | permission_denied | high | UserActionRequired | choose_folder, open_system_settings | BLOCKED |
| Internal | internal_error | critical | Fatal | collect_diagnostics, leave_flow, open_issue | BLOCKED |

iOS 已读链路另有 `IOS-ERROR-MAPPING-001`：至少 connect/list/detail 绕过该表，合并 typed DB variant 并显示技术文本。

## 并发图

```text
SwiftUI/MainActor
  -> feature Task / generation / state guard
  -> CoreBridge actor instance
  -> Task.detached (同步 FFI 不可被 Swift 强制中断)
  -> Rust Core transaction / guard / operation token
  -> filesystem + SQLite WAL(single writer, busy_timeout=5s)

并行平台事件:
  FSEvents callback -> debounce/generation -> ordered window queue
                    -> RepositoryWriteCoordinator(per repo)
                    -> Core batch -> overview -> cursor ack

高风险缺口:
  init cleanup/rollback ----无可信 ownership----> remove_dir_all/remove_file
  overview writer ----------无安全 tmp/final CAS--> markdown/provenance
  batch FS move ------------仅 RAII、无 journal----> SQLite commit
```

| ID | 状态 | 参与者/共享状态 | 协调与结论 |
| --- | --- | --- | --- |
| CONCURRENCY-SWIFT-FFI | BLOCKED | SwiftUI/MainActor, CoreBridge actor instance, Task.detached, sync UniFFI, Rust Core, repository files, SQLite, UI state | actor instance isolation, Core transaction/guard/token；架构合同已读；全部 Bridge 调用方未逐文件闭环。Task.detached 本身是规定模式，不单独构成 finding。 |
| CONCURRENCY-REPO-WRITE-COORDINATOR | PASS | feature tasks per repository, per-repo write access | RepositoryWriteCoordinator actor, normalized repo key, cancelable waiter queue；所读实现未见 double-resume、漏 release 或 waiter cancellation 缺陷；全调用面仍由 coverage 的 BLOCKED 文件限制。 |
| CONCURRENCY-SQLITE | PASS | Core DB readers, single SQLite writer, index.db, WAL/SHM | WAL, foreign_keys, busy_timeout=5000, transactions；连接配置范围 PASS；不能外推为所有 FS/DB 跨资源操作安全。 |
| CONCURRENCY-INIT | FINDING | repo init, user/sync/second process, .areamatrix.init-*, .areamatrix/, AREAMATRIX.md | none after metadata rename；cleanup/rollback ownership 与并发写入存在 P0 缺口。 |
| CONCURRENCY-OVERVIEW-INCREMENTAL | FINDING | overview writer A, overview writer/user edit B, generated markdown, AREAMATRIX.md, fixed .md.tmp, provenance rows | preflight provenance only; no final CAS/target lock；固定 tmp、symlink 与最终 CAS 均缺失。 |
| CONCURRENCY-BATCH-FSDB | FINDING | batch rename/category, SQLite writer, filesystem, user files/sidecars, files rows, change log, undo | SQLite transaction, in-process RAII only；缺 crash-durable journal。 |
| CONCURRENCY-FSEVENTS | PASS | FSEvents callback, flush task, ordered window drain, Core sync, cursor ack, pending events, cursor watermark, in-flight refs | generation, cancelable flush, queue head, RepositoryWriteCoordinator；已读范围未见 cursor 越过失败队首；文件整体仍可能因未读尾段在 coverage 中 BLOCKED。 |
| CONCURRENCY-IOS-DETAIL | FINDING | toolbar/retry/segment tasks, MainActor model, detached FFI, metadataState, changeLogState, noteState | none per request；旧 completion 可覆盖新状态。 |
| CONCURRENCY-IOS-CONNECT | FINDING | picker/reconnect task, onOpenURL task, MainActor model, route, checkState, validation, cloud state | UI busy disable only; no operation identity；系统 URL 入口可绕过普通按钮 busy 串行。 |
| CONCURRENCY-MACOS-OVERVIEW-UI | FINDING | language change tasks, MainActor overview model, Core read, languageStatus, phase, concreteContentLocale | shared operation coordinator for staged writes; no load generation；prepare 在 await 前置 busy，重复 prepare 候选已排除；load 仍存在竞态。 |
| CONCURRENCY-LINUX-UI | BLOCKED | .NET async continuations, future/current Linux UI host, INotifyPropertyChanged models | ConfigureAwait(false); no reviewed dispatcher；当前 csproj/view wrapper 未建立 GTK binding/PropertyChanged subscriber，不能证明 cross-thread UI sink；需真实 Linux UI runtime。 |
| CONCURRENCY-OBSERVABILITY | PASS | Core delivery worker, callback worker, Swift ingress, ObservabilityHub, events, drop counters, health, rolling store | bounded queues, timeout, catch_unwind, ordered stop；所读文件 PASS；Hub/adapter 尚有未读范围，端到端结论仍受 coverage BLOCKED 限制。 |

## 取消、超时、重试与恢复

| ID | 状态 | 取消点 | 底层/晚到 | 重试 |
| --- | --- | --- | --- | --- |
| CANCEL-SYNC-FFI | BLOCKED | 调用前后或相邻小调用之间 | 已开始的同步 Rust 调用继续到返回；调用方必须用 generation/state token 拒绝旧 UI completion | 按 report/session/token；不得假定 Task.cancel 已撤销副作用 |
| CANCEL-IOS-DETAIL | FINDING | View task cancellation / newer reload | detached read continues；会写旧 metadata/log/note state | 按钮可重复启动；无 request identity |
| CANCEL-IOS-CONNECT | FINDING | picker dismiss/route dismiss/new URL | access/validation/config awaits continue；旧 route/error 覆盖新请求 | retry/picker/onOpenURL 无统一 operation id |
| CANCEL-MACOS-OVERVIEW-LOAD | FINDING | language change/view task cancellation | Core read may continue；旧 locale 状态覆盖当前 locale | 每次 onChange 新 Task；无 generation |
| CANCEL-DOTNET-PLATFORM-DIFF | FINDING | CancellationToken | bridge 决定；OCE 返回后被 catch；写 Failed/UnknownSnapshot | 错误文案建议 Retry，但取消不应归类为错误 |
| CANCEL-OVERVIEW-REGENERATION | PASS | commit 前；committing 后不可取消 | journal/state machine 收敛；operation id/session status 校验 | resume/rollback by operation id |
| CANCEL-FSEVENTS-FLUSH | PASS | 新 generation/stop/restart | generation guard 拒绝旧 flush；队首窗口与 cursor 由 model 串行 | 失败保留队首，从同窗口重放 |
| RETRY-ERROR-CONTRACT | FINDING | not applicable | not applicable；iOS feature-local raw String 丢失状态 | DbLocked retry / DbCorrupted repair / Internal no-auto-retry；iOS reviewed surfaces 未保持 |
| CANCEL-BATCH-IMPORT | BLOCKED | 单文件 Core 调用之间 | 当前同步 import 完成；不得启动下一项 | session/report/idempotency required |

未发现通用自动重试循环；已读合同规定 SQLite 等待上限 5 秒、`ICloudPlaceholder` 只能用户触发 Download & retry、`Internal/PermissionDenied/Conflict/StagingRecoveryRequired` 不得自动重试。由于多数 UI consumer 与长流程文件仍 `BLOCKED`，这些规则不能宣称全仓落实。

## 生命周期结论

- 用户文件：`FAIL`。四条 P0 路径可删除/覆盖用户内容或通过 symlink 写出资料库边界。
- DB/文件一致性：`FAIL`。batch rename/category 的硬崩溃窗口没有持久 journal。
- staging/import：已读普通 guard/恢复范围未见新 finding，但大量实现与测试未全文审阅，结论 `BLOCKED`。
- FSEvents/cursor：已读 watcher、ordered window 和 cursor 合同范围 PASS；文件整体/平台实测仍 `BLOCKED`，未发现 cursor 越过已确认失败窗口。
- iCloud：合同明确 watcher/Core 不隐式下载；所有平台消费链未全审且未使用真实 iCloud，`BLOCKED / 需外部验证`。
- UI/FFI：`FAIL`。iOS error mapping 丢 typed recovery；iOS/macOS 三条旧结果回写；通用 detached 语义本身符合文档。
- 线程/Task：已读 RepositoryWriteCoordinator、observability 和 watcher 关键范围较完整；其余 Task/线程/dispatcher `BLOCKED`。
- Timer/observer/Combine/AsyncStream：部分 observability/Combine owner 已核对，未覆盖全仓，`BLOCKED`。
- SQLite connection/statement/transaction：连接 WAL/foreign key/busy timeout 配置 PASS；跨 FS transaction 的 batch 路径 FAIL；其余 statement 生命周期 `BLOCKED`。
- 文件句柄/临时文件：safe_move 已读范围 PASS；overview tmp/snapshot FAIL；全仓 FD/临时文件结论 `BLOCKED`。

完整 owner/create/release/exception-path 表见 `lifecycle-ledger.jsonl`。

## P0 边界威胁模型

- 资产：资料库内用户文件、根 `AREAMATRIX.md` managed block 外正文、资料库外同一用户可写文件、`.areamatrix/` metadata。
- 信任边界：用户/同步进程可写资料库目录；AreaMatrix cleanup/rollback/overview writer 以应用权限写文件；SQLite 与文件系统不能共享事务。
- 入口：`.areamatrix.init-*` 命名目录、固定 `.md.tmp`、symlink、并发文件编辑、初始化/概览失败注入、进程崩溃。
- 能力：本地用户、同步提供商或同账户进程可以控制文件名、symlink 和时序；没有假设远程未认证攻击者。
- Abuse path：形状伪装目录 -> cleanup 删除；preflight 后并发写 -> rollback 删除；tmp symlink -> 外部文件截断；provenance 后编辑 -> rename 覆盖。
- 已有控制：最终 target provenance、部分 symlink_metadata、RAII guard、full regeneration journal；这些控制未覆盖固定 tmp、最终 CAS、init ownership 和硬崩溃。
- 建议缓解：durable operation identity/journal、create_new + no-follow、最终 CAS、fail-closed recovery、故障注入。
- 残余风险：真实 iCloud/FSEvents、多进程、Windows symlink 权限和断电语义需要外部平台验证。

## 已排除候选

| 候选 | 处置 | 理由 |
| --- | --- | --- |
| Task.detached 普遍不可取消 | 排除为独立 finding | docs/architecture/concurrency.md:59-76 明确规定同步 FFI 通过 detached 执行且只能在调用之间取消；只登记有具体过期回写/协调缺口的链路。 |
| RepositoryOverviewRegenerationModel.prepare 可重复通过 guard | 排除 | prepare 在首个 await 前同步将 phase=.loading；第二个 MainActor 调用看到 phase.isBusy=true。仅 load 缺 generation。 |
| resumeInterruptedInitialization 绕过写协调器 | 不登记（可达性 BLOCKED） | resume_scan_session 确实写 DB；已检查引用未发现 production 调用方，只有测试直接调用。但全仓调用图未逐行闭环，因此不把该检索结果升级为确定性排除。 |
| Linux ConfigureAwait(false) 后更新绑定属性 | 需外部验证/BLOCKED | 当前 Linux csproj/view wrapper 未建立 GTK dispatcher 或 PropertyChanged UI subscriber；可见风险但尚无具体 UI sink，不能作为静态确认缺陷。 |
| remote-governance expression 注入 | 排除为安全 finding | workflow_dispatch 未声明 branch input，实际值来自管理员控制的 default_branch；虽然 Git ref 可含 shell metacharacters，未建立低权限输入到高权限 shell 的边界。仍建议用 env/printf 硬化。 |
| CI 未设置 timeout-minutes | 排除为明确缺陷 | GitHub 有平台默认上限且主要 workflow 有 concurrency cancellation；属于可靠性硬化，当前无项目合同或已证实 hung path。 |
| Windows watcher 关闭泄漏 | 排除 | MainWindow_Closed 反订阅并 Dispose；WindowsWatcherDiagnostics.StopWatcher 解绑事件并释放 watcher。 |
| task-loop timeout 留下子进程 | 排除（已读范围） | Popen 使用新 session，idle/total timeout 进入 terminate_child，TERM 后升级 KILL 并清 current child/log state。 |

## 验证证据

已运行：

- `python3 .codex/runtime/error-concurrency-lifecycle-audit-20260820/finalize_audit.py`：PASS（退出 0）；内部重新解析所有 JSONL，检查 5092 条 inventory/coverage 一一对应、路径唯一、状态枚举、`PENDING=IN_PROGRESS=0`、守恒、finding/schema 引用和 18 条 error contract。
- 冻结清单/路径/类型/SHA-256 复核：PASS（缺失 0，漂移 91）；漂移项逐项记录并全部保持 `BLOCKED`。
- 当前 scope 差异复核：BLOCKED；冻结后新增 40 个，非审计 runtime 新增 6 个，移除 0 个。
- `git diff --check -- .codex/runtime/error-concurrency-lifecycle-audit-20260820`：`PASS`（exit 0）。限制：git diff --check does not inspect untracked files; JSONL/report schema checks cover those artifacts.

未运行：

- `cargo test --workspace`、Rust 专项测试、`./dev test macos`、xcodebuild、.NET/Linux tests、lint、build、压力/故障注入：按用户门禁，只有全仓逐文件逐行人工审阅完成后才能启动；当前仍有 3510 个 `BLOCKED` 文件，因此本轮不得运行并伪装为完成证据。
- 真实 iCloud、真实 FSEvents、真实 WinUI/Linux runtime、真实用户资料库、长稳/极端并发：安全边界或环境外部验证，未运行。

## 最终门禁

- 人工逐行审计：`BLOCKED`
- 辅助测试：`NOT RUN`（受用户前置门禁约束）
- 真实平台/压力/长稳：`BLOCKED-EXTERNAL`
- Review：`blocked`（存在 P0/P1 findings 和未审文件）
- Security/file safety：`blocked`
- Dependency：`not-applicable`（本轮无依赖变更）
- CI：`blocked`（未运行，且本轮不是 merge approval）
- Git evidence：`not-applicable`（未提交、未推送）
- 总结论：`BLOCKED / NOT-READY`
