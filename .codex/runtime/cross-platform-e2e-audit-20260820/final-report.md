# AreaMatrix 全仓库跨平台运行时与端到端用户流程审计

> 最终状态：**IN_PROGRESS / NOT-READY**。本报告不是“审计完成”声明。产品代码没有被本轮修改；只更新了本目录审计台账。

## Findings（先列问题）

### P1

| ID | 结论 | 证据等级 | 关键影响 |
|---|---|---|---|
| CP-E2E-001 | AI 分类、标签、摘要 producer 用字符串包含判断，未调用统一 privacy evaluator；仍写 `privacy_rules_checked=true` | STATIC_CONFIRMED | 远程 AI 可能发送被规则禁止字段；`docs/api/core-api.md:4665-4691` 与 `core/src/ai_*:47-62,101-135` |
| CP-E2E-002 | `.areamatrix` symlink 被当作 initialized，普通 cursor/DB 写入可跟随到另一资料库 | DYNAMIC_CONFIRMED_ISOLATED_FIXTURE | `set_fs_event_cursor` 入口将 victim cursor 从 None 写成 4242；`core/src/repo_path.rs:206-230,241-270,313-321` |
| CP-E2E-003 | iCloud conflict 中间目录 symlink 可把库外 conflicted copy 移入 Trash | DYNAMIC_CONFIRMED_ISOLATED_FIXTURE | `core/src/icloud_conflicts/paths.rs:34-61` -> `resolve_icloud_conflict:95-124`；用户确认操作越界 |
| CP-E2E-004 | macOS import session metadata symlink 可删除或覆盖库外 `current.json` | DYNAMIC_CONFIRMED_ISOLATED_FIXTURE | `ImportBatchSessionPlatformServices.swift:30-50`；fixture 为 `clear_external_deleted=true`、`external_overwritten=true` |

### P2

| ID | 结论 | 证据等级 | 关键影响 |
|---|---|---|---|
| CP-E2E-005 | iCloud preview 后内容替换仍被 apply，未返回合同要求的 `Conflict` | DYNAMIC_CONFIRMED_ISOLATED_FIXTURE | 新字节被移入 Trash；`core/src/icloud_conflicts.rs:72-105`、`docs/api/core-api.md:7595-7601` |
| CP-E2E-006 | macOS session 保存错误静默吞掉，崩溃恢复入口可能消失 | STATIC_CONFIRMED | `saveSession` 空 catch（`ImportBatchSessionPlatformServices.swift:13-19`）使重启路由看不到 session |
| CP-E2E-007 | Windows/Linux bridge 仍加载不存在的 `load_config/update_config` export | STATIC_CONFIRMED_WITH_HARNESS_FAILURE | UDL 为 `load_repo_config/update_repo_config`（`core/area_matrix.udl:45-49`）；Linux harness 报 EntryPointNotFound |
| CP-E2E-008 | Windows/Linux `CoreError` decoder 与 UDL variant/payload 错位 | STATIC_CONFIRMED | `RevisionConflict` 的 string+i64+i64 被只读一个 string；`core/area_matrix.udl:2792-2814` |
| CP-E2E-009 | Windows/Linux csproj 没有 native Core 制品复制、RID/架构绑定或 publish 装配 | STATIC_CONFIRMED | clean publish 的 `NativeLibrary.Load("area_matrix_core")` 没有对应资产；`AreaMatrix*.csproj:1-23` |
| CP-E2E-010 | Windows onboarding `FolderPicker` 未初始化 HWND | STATIC_CONFIRMED | `ChooseRepositoryView.xaml.cs:94-106` 缺 `InitializeWithWindow.Initialize` |
| CP-E2E-011 | Windows/Linux preview 固定自动分类路径，最终 request 才应用 `TargetDirectory/RelativeDirectory` | STATIC_CONFIRMED | preview/apply 可能针对不同目标；`WindowsImportViewModel.cs:368-394` -> `DesktopImportCoreBridge.cs:74-116` |
| CP-E2E-012 | iOS security scope 在连接完成后立即 stop，后续 Core 调用只持 path | STATIC_CONFIRMED_RUNTIME_BLOCKED | `ConnectRepositoryModel.swift:137-179`；真机外部目录访问未验证 |
| CP-E2E-013 | iOS Share queue staging、Core import、ticket completion 不是事务/幂等提交 | STATIC_CONFIRMED_RUNTIME_BLOCKED | `ShareImportQueue.swift:54-76,138-155`、`ShareImportQueueConsumer.swift:69-89` 可留残留或重放 |
| CP-E2E-014 | Share Extension 来源 URL 与 `NSItemProvider` 临时文件生命周期未闭合 | STATIC_CONFIRMED_RUNTIME_BLOCKED | `ShareImportExtensionScene.swift:147-217,233-256` 保存裸 URL，后续才 copy |
| CP-E2E-015 | iOS/Windows/Linux diagnostics exporter 普通路径 API 可跟随 symlink/reparse ancestor | STATIC_ONLY | `.areamatrix/generated/diagnostics` 直接 CreateDirectory/Write；目标平台 fixture 尚未执行 |

完整前置条件、调用链、实际/预期、修复方向、owner、回滚和验证见 [findings.jsonl](findings.jsonl)。

## 范围与守恒

- 基线 `cf3647378d64885e8e6a44a2a5b60d8926668982`；冻结范围 5,053 文件、1,498,037 行。
- 5,053/5,053 SHA-256 与历史人工审阅匹配：5,019 PASS + 34 NOT_APPLICABLE。
- 冻结快照守恒：`5053 = 5019 inherited manual line-review + 34 evidence-backed NOT_APPLICABLE + 0 unclassified`。
- 本轮语义守恒：`5053 = 0 fresh PASS + 0 fresh FINDING + 0 fresh NOT_APPLICABLE + 0 fresh BLOCKED + 5053 PENDING`。
- 继承哈希不等于本轮重新逐文件逐行阅读；不得宣称审计完成。二进制/资源 34 项均逐项记录 BYTE_RANGE、来源/生成链和用途。

## 平台支持矩阵

| 平台 | 定位 | 状态 | 可证明 | 未证明 |
|---|---|---|---|---|
| macOS | 正式产品运行时 | FINDING | Core/Swift 构建测试、隔离 fixture | 可见 app、Finder/iCloud、崩溃恢复、签名发布 |
| Rust Core | 正式核心 | FINDING | cargo 全套、临时 Core/FS/DB fixture | 真实云、跨 OS filesystem primitive |
| iOS/Share Extension | 实验客户端 | BLOCKED（有 code findings） | SwiftPM/tests/CoreSDK | signed device、security scope、extension lifecycle |
| Windows WinUI | 实验客户端 | BLOCKED（有 code findings） | hostless .NET | WinUI/XAML、HWND picker、native DLL、publish |
| Linux/.NET | headless/UI contract | BLOCKED（有 code findings） | managed build、harness failure | GTK executable、Linux cdylib、安装运行 |
| Cloud/Remote Provider | capability contract | BLOCKED | 静态合同、本地 fixture | 真实 iCloud/OneDrive/Provider |

详见 [platform-matrix.jsonl](platform-matrix.jsonl) 与 [blocked-evidence.jsonl](blocked-evidence.jsonl)。

## 14 条用户流程

| 流程 | 状态 | 关联证据 |
|---|---|---|
| WF-01 首次启动/创建/接管/重连 | FINDING | path symlink、Windows export/package、FolderPicker、iOS scope |
| WF-02 空/非空/权限/无效路径/DB | FINDING | DB 越界、native export、error decoder |
| WF-03 Copy/Move/Indexed 导入 | FINDING | session、目标 preview、Share queue/provider |
| WF-04 Duplicate/冲突/Replace/取消重试 | FINDING | stale preview、decoder、目标 preview |
| WF-05 浏览/列表/详情/标签/日志 | BLOCKED | 目标平台 host 和 iOS scope 未建立 |
| WF-06 搜索/筛选/Saved/Smart/Semantic | BLOCKED | AI/provider 与 native runtime 未建立 |
| WF-07 批量标签/分类/重命名/删除/Undo | BLOCKED | 真实 mutation/平台 UI 未建立 |
| WF-08 外部修改同步 | FINDING | cursor DB symlink、native bridge |
| WF-09 placeholder/冲突/Keep Both/Repair | FINDING | 两个 iCloud fixture 已确认 |
| WF-10 startup/staging/reindex/relink | FINDING | session/queue 恢复和 metadata boundary |
| WF-11 AI 配置/隐私/建议/日志 | FINDING | producer 未接 evaluator |
| WF-12 diagnostics/incident/export/离线读 | FINDING | exporter no-follow 静态 finding |
| WF-13 设置/语言/平台差异 | FINDING | config export/decoder/package |
| WF-14 退出/重启/切库/网络/异常恢复 | FINDING | session、queue、scope、native packaging |

每条流程的入口、前置、用户动作、Bridge、FS/DB、UI、取消/重试和清理字段见 [workflow-matrix.jsonl](workflow-matrix.jsonl)。`BLOCKED` 代表缺真实目标平台证据，不代表安全保证。

## Core / UDL / Bridge

- BC-001 docs -> UDL 源合同对齐，`./dev bindings verify` 通过。
- BC-002 UDL -> Rust producer 有 AI privacy 执行链 finding：公开 evaluator 存在但 producer 未接入。
- BC-003 macOS tracked UniFFI/CoreSDK fingerprint 通过，不等于可见 UI E2E。
- BC-004 iOS 仅编译/测试，真机和 Share Extension blocked。
- BC-005/006 Windows/Linux 手写 loader、decoder、packaging 与当前 UDL/native artifact 不一致。
- BC-008 UI confirmation -> Core -> FS/DB -> reload 被 iCloud、session、preview 和 Share queue findings 打断。

详见 [bridge-contracts.jsonl](bridge-contracts.jsonl)。

## 运行证据与限制

PASS：`cargo fmt --all -- --check`、clippy、`cargo test --workspace --all-features`；iOS build/test（106）；bindings verify；CoreSDK verify（fingerprint `265bee1ffba7`）；macOS tests（1357、9 skipped、0 failures、81-key localization PASS）；Linux managed build；Windows hostless tests。

FINDING：Linux native harness 退出 134，`EntryPointNotFoundException load_config`；`nm` 只见 `load_repo_config/update_repo_config`；四个隔离 fixture 结果见 [runtime-evidence.jsonl](runtime-evidence.jsonl) 和 `.codex/runtime/file-safety-audit-20260820/dynamic-evidence.md`。

BLOCKED：WinUI product build 因 macOS 无法执行 `XamlCompiler.exe`；真实 iOS device/Share Extension、真实 iCloud/OneDrive、远程 Provider、clean notarized Mac 均无授权或环境。

编译、ViewModel/hostless 测试、截图、fixture、harness 均未被当作真实目标平台 E2E。

## 排除项与收尾

- InFlight filtered-only cursor 按 fs-watcher 合同降为 residual。
- 未闭合误操作的中间 symlink、batch token、Share ticket ID 候选不升级。
- 不合并其他并发审计目录 findings。
- 本轮只修改本审计目录九个台账文件；未回滚工作树既有改动。
- 收尾：存在 5,053 个 current semantic `PENDING`、15 条未修复 finding、3 条流程/4 个目标平台 blocked，故不能宣称完成或可发布。
