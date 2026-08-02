# 工程成熟路线图

> AreaMatrix 在核心功能闭环完成后，继续把代码从“能跑”推进到“可复用、可维护、可持续高速扩展”的工程成熟状态。
>
> 阅读时长：约 9 分钟。

---

## 目标定义

本文定义的 100% 不是所有未来产品功能都完成，而是 **macOS 前端与跨层工程治理达到长期可扩展状态**。

达到 100% 时应满足：

- 新功能先找到 feature owner，再写代码。
- 新功能主要只改自己的 `Features/<FeatureName>/`，少量触达 `Bridge/`、`PlatformServices/`
  或测试支撑；跨 feature 改动需要有明确原因。
- SwiftUI View 只负责展示和交互，不直接做文件 IO 或平台副作用。
- Swift 调用 Rust Core 只走 `CoreBridge` 和受控 Bridge 扩展。
- `Bridge/Generated/` 与 `Bridge/UniFFI/` 保持纯生成绑定。
- FileManager、iCloud、FSEvents、open/save panel、NSWorkspace、Pasteboard 等平台能力进入 `PlatformServices/` 或明确迁移路径。
- Import、FileActions、Settings、AI、Search、MainList 等功能域有稳定落点。
- 通用 UI、loading / empty / error 状态、sheet / alert routing、async action、fixture 和 mock
  bridge 已沉淀成可复用模式。
- 高风险用户文件边界有固定评审、验证和回滚口径。
- 测试支撑能复用，新增 feature 不需要重复搭建 fixture 和 mock。
- 架构规则能通过文档、review 和自动化检查防止漂移。

### 100% 验收证据矩阵

状态只依据当前权威文件和可执行证据：`已证明` 表示已有直接门禁、多调用方测试或可复核的连续演进记录；
`部分证明` 表示工程主干成立但工程证据仍不完整。该矩阵只评工程成熟度，不替代测试、CI、review，正式
分发 readiness 继续由 residual ledger 单独判断。

| 完成条件 | 权威实现 / 规则 | 自动化或验收证据 | 当前状态 |
|---|---|---|---|
| 新功能先找到 feature owner | `apps/macos/AGENTS.md`、`Features/*` | `MacOSFeatureOwnershipGovernanceTests` 精确 inventory 12 个 owner | 已证明 |
| 新功能以 feature-local 改动为主 | migration zone inventory、feature owner 规则 | `MacOSMigrationZoneGovernanceTests` 禁止旧区新增文件；PR 模板记录 owner / 跨 feature 理由；`feature-evolution-evidence.json` 及 governance check 核验治理基线后的 3 轮真实演进批次 | 已证明 |
| SwiftUI View 不直接做平台 IO | `macos-frontend-architecture.md`、`PlatformServices/` | `testSwiftUIViewFilesDoNotOwnPlatformIO`、platform capability inventory | 已证明 |
| Swift 调用 Core 只走手写 Bridge | `Bridge/`、`AppCoreServices` | `testGeneratedCoreCallsStayInsideBridge`、`MacOSDefaultCoreServicesGovernanceTests` | 已证明 |
| Generated / UniFFI 保持纯生成 | `Bridge/Generated/`、`Bridge/UniFFI/` | generated artifact governance、`./dev bindings verify`、macOS CI bindings gate | 已证明 |
| 平台能力进入 PlatformServices 或有迁移路径 | `PlatformServices/`、受控 App adapter | platform capability / default adapter / NSWorkspace / SQLite governance tests | 已证明 |
| 主要功能域有稳定落点 | 12 个 `Features/<Owner>/` | feature owner inventory 记录 responsibility、risk、validation | 已证明 |
| 通用 UI、async 与 recovery 模式可复用 | DesignSystem、feature-owned routing、Settings diagnostics generation、FileActions undo support | Repository / Advanced / About 共享 diagnostics generation；Batch Rename / Delete / Change Category 共享 undo 后处理，均有多调用方 XCTest | 已证明 |
| 高风险用户文件边界有固定口径 | `CODE_REVIEW.md`、file-safety 规则、Import / repair / conflict tests | forbidden-touch、失败恢复和真实临时 repo 证据充分；真实 iCloud placeholder 与正式分发证据由 residual ledger 独立阻断，不降低工程边界成熟度 | 已证明 |
| 测试支撑可复用 | shared queues、temporary FS、fixtures、test doubles | `TestSupportNamingGovernanceTests` 与多个 feature 真实调用方 | 已证明 |
| 文档、review、CI 能阻止架构漂移 | docs、AGENTS、CI governance | governance XCTest membership、Swift file size、bindings、coverage、SwiftLint、SwiftFormat CI gates | 已证明 |

矩阵当前 11 条完成条件均为`已证明`，AreaMatrix 的工程成熟度达到本文定义的 100%。这不表示产品功能永远完成，
也不表示正式版本已可分发；真实 iCloud placeholder、Developer ID 签名 / 公证、正式 DMG、clean Mac、tester
和 release owner 证据继续保留在 residual ledger，不能用本地测试代替或伪造关闭。

连续演进证据的权威 registry 已归档为 `../../evidence/feature-evolution-evidence.json`。`./dev check governance` 会核验治理
基线提交、至少 3 个不同日期的后续批次、feature owner 路径、必要的 App / Bridge / Platform wiring 与测试路径。
后续真实功能批次应继续追加记录，而不是重写或删除既有证据。

## 100% 成熟度账本

这条路线的核心目标是把 AreaMatrix 从“功能可以继续堆”推进到“功能可以稳定、高效、低风险地持续新增”。
百分比只描述工程成熟度，不描述产品功能数量。

| 能力等级 | 成熟度 | 状态定义 | 升级证据 |
|---|---:|---|---|
| A. 架构主线清晰 | 0%-30% | Rust Core / UniFFI / Swift Platform / SwiftUI UI 主链路清楚，核心功能闭环能跑 | `docs/architecture/layered-design.md`、`ffi-design.md`、Core API / UDL 对齐，macOS build/test 能证明主链路 |
| B. 规则固定 | 30%-45% | feature 落点、Bridge 边界、PlatformServices 目标和高风险约束写入 docs / AGENTS | `apps/macos/AGENTS.md`、`macos-frontend-architecture.md`、本文一致；新增代码有可查落点 |
| C. 样板形成 | 45%-60% | 2-3 个核心 feature 成为后续实现样板，不再靠临场组织文件 | MainList、FileActions、Import / Settings 中至少两个形成 View / State / Actions / Support 样板，并通过 build/test |
| D. 复用主干成型 | 60%-75% | PlatformServices、DesignSystem、TestSupport、错误和 async 状态模式可跨 feature 复用 | 新增 feature 不重复搭平台副作用、mock bridge、fixture、loading / error / empty 处理 |
| E. 自动化守边界 | 75%-90% | 关键边界可被本地检查、CI 或 review checklist 发现漂移 | 非 Bridge 直接 UniFFI、SwiftUI 平台副作用、生成绑定手写逻辑、Core API / UDL drift 有检查或明确 review gate |
| F. 长期演进稳定 | 90%-100% | 新功能默认局部落地，跨层改动有证据，稳定公共能力可按需模块化 | 连续多个 feature 在不扩大旧迁移区的情况下完成；可考虑稳定能力 Swift Package 化或更强 CI 门禁 |

> 旧版按阶段的“D 前段”描述仅保留为演进记录，不再作为当前总进度。当前状态以“当前治理进度（证据口径）”表为准。

当前工程已经完成大量局部治理：主架构与 feature owner 已基本归位，
MainList、FileActions、Import、Settings、Onboarding、AI、SyncConflicts 等主要功能域已有稳定落点；
TestSupport 请求日志与结果队列已在多个 feature 复用，Bridge、生成绑定、平台能力和默认服务也已有治理测试。
FileActions、Search、SmartList 与 SyncConflicts 的 sheet host 已归回各自 feature，通用 lifecycle 只保留顺序组合。
FileActions 的 batch change category、batch delete 与 batch rename 现在共享同一套 undo token 规范化、
action-log 加载和 toast 状态转换；各动作仍保留自己的成功条件与风险提示，不合并 confirmation、Core apply
或 selection cleanup 等业务语义不同的路径。
`MainRepositoryContentView` 的生产默认服务装配也已归入 App 层轻量 assembly，并保留 View-owned `@StateObject` identity。
App appearance、cursor 与 haptic 已由共享 interaction feedback adapter 承接，View-like 文件的全局平台写入也已有门禁。
Command Palette 搜索焦点恢复、Search presentation routing、FileActions batch / undo presentation state 和
Import conflict batch relay state 也已归回各自 feature；semantic index confirmation、privacy rule / call log
route 和 sync conflict review route 同样由 Search / SyncConflicts routing state 承载，shell 只持有
feature-owned 值类型，Search debounce / facets task host 也已归回 Search owner。手写 Swift 文件已建立
450 行近阈值精确清单与 500 行硬限制。Import progress 的动态 presentation、selection state、detail
projection 与互斥 relay 已由 Import owner 承载；MainList error 的 retry / diagnostics fallback 也已合并为
MainList-owned recovery contract。`RepoConfigSnapshot` fixture family 与 Local File URL platform adapter family
也已完成自然拆分；当前 450 行近阈值清单只登记 454 行的
`MacOSArchitectureBoundaryGovernanceTests.swift`，并冻结其继续增长。macOS CI 也已从“目录缺失时跳过”升级为
工程 / 源码缺失即失败，并由本地 governance check 防止 skip guard 回流。Import session persistence 已迁入
`PlatformServices`；AI remote provider probe 已切换为 Core prepare / complete 两阶段合同，并由共享
`RemoteProviderProbeService` actor 使用 Keychain 与 headers-only URLSession 执行，禁止 redirect，只回传净化 observation。
Core 的 classification / tags / summary runtime 响应脱敏已收敛到
`core/src/ai_runtime.rs`，由三个 executor 复用并保留各自 fallback / 长度策略；四类外部进程调用也已
收敛到 `core/src/external_runtime.rs`，统一最小环境、timeout、独立 Unix process group、后代进程回收、
kill / wait、stdout 上限与 stderr 丢弃策略。旧 probe shell/runtime、Core curl/TCP fallback 和进程级 probe
环境变量合同已经删除，TOCTOU 路径竞态不再存在。接下来继续治理长期隐私、credential lifecycle 和发布证据。旧
`Models` / `Views` 迁移区也已建立精确 inventory，
新增业务文件回流会被 XCTest / CI 阻断。12 个 Feature 目录也已建立 owner、风险和验证 inventory，
新增 Feature 必须先明确 owner 才能进入代码面。

## 当前治理进度（证据口径）

当前状态：

- 核心功能闭环：已完成。
- 顶层运行架构：已清晰，采用 Rust Core / UniFFI / Swift Platform / SwiftUI Feature UI。
- macOS 前端落点规则：已基本稳定。当前主要落点包括 `Features/MainList/`、
  `Features/FileActions/`、`Features/Import/`、`Features/Settings/`、
  `Features/Onboarding/`、`Features/AI/`、`Features/SyncConflicts/`、
  `Features/Search/`、`Features/Detail/`、`Features/CommandPalette/`、`Features/Diagnostics/`、
  `Features/RepositoryLifecycle/` 和 `PlatformServices/`。
- 旧迁移区收缩：`Models/` 当前已为空；`Views/Onboarding/` 当前无 Swift 文件；
  `Views/Main/` 主要剩 shell / lifecycle / sidebar / toolbar 文件；`Views/Settings/`
  主要剩通用 scaffold 组件。
- 执行层复用：MainList、FileActions、Import、Settings、Onboarding、AI 和
  SyncConflicts 的 View / State / Actions / Support 边界已明显成型；TestSupport
  已形成 shared shell、error mapper、temp cleanup、mirror assertion、request log、result / step queue、
  naming governance 底座，并有大量 feature-local support / fixtures / test double；Core AI runtime
  响应脱敏也已有共享 utility 和三个真实调用方。
- 自动化边界：非 Bridge Core 调用、生成绑定目录、SwiftUI 平台 IO / 全局 AppKit 写入、Feature
  平台能力、默认服务构造、SQLite 与 CoreError 例外已有治理测试；Feature 平台能力盘点已覆盖
  `FileManager` 默认实例、`FileHandle`、`URL.resourceValues`、Data 读写、脚本写入和环境变量访问；
  `core/tests/external_runtime_governance.rs` 还会扫描 Core 源码，禁止直接 spawn / wait_with_output /
  output，防止新的外部进程绕过共享执行器；
  tracked Swift bindings 已有本地与 CI
  exact drift gate；手写 Swift 文件达到 450 行后必须登记 owner、理由与拆分触发条件，且不得继续增长，
  500 行仍是硬上限，UniFFI 生成绑定由独立清单与 drift gate 管理。
- macOS CI 已显式开启 Xcode coverage，并对 Swift Watcher 精确文件清单执行 60% 门槛、对全部手写
  Bridge 文件执行 50% 门槛；生成绑定不计入手写覆盖率，target / 文件清单缺失、空集合和 direct
  `xctest` fallback 均不能形成 coverage PASS。
- 当前治理重点：继续补强 AI credential lifecycle、隐私与发布证据，使复用与自动化检查成为新增功能的默认路径。
- Import 高风险读写路径已完成一轮依赖隔离：预检器不再隐式构造 `CoreBridgeBatchFileLoader`，由 App 组合根提供 `ImportFeatureDependencies.batchFileLoader`；批量导入的 conflict batcher、undo store、session store 和占位符下载器现在都是组合边界的必传能力，生产 sheet 统一从同一 scope 接收。后续仍需清理其他 Feature 中仅供 Preview / 旧调用点的 `.live` 便利默认值，并保持真实 Core 与文件安全验证。
- Import session persistence 已有真实临时目录的 save / load / missing / corrupt / clear / permission
  回归证据，并已迁入 `PlatformServices/ImportBatchSessionPlatformServices.swift`；后续演进不得改变
  app-owned metadata 路径或失败不阻断导入的语义。
- Remote provider probe 已有 Core plan / observation 状态矩阵、Keychain credential unavailable、bearer / Anthropic
  header 装配、URLSession redirect status、timeout failure、headers-only body 取消和 Bridge enable 闭环证据。
  Core 不读取 secret、不执行网络、不启动 probe 进程；平台层不回传响应正文、header 或底层错误原文。
  自定义 endpoint 的 URL userinfo 已由 Core 与平台层双重拒绝；Swift 任务取消会终止 URLSession，
  清理 pending probe，且不会产生 verification token。
- 分发证据、外部冒烟或决策类 residual 仍以 residual ledger 为准；它们不改变本文的工程成熟度百分比，
  但会阻止把项目表述为正式分发状态已完全闭合。

当前不能再用“65%-70%”或“缺少54%”作为全项目结论：前者与上方 11/11 已证明矩阵冲突，后者也没有对应的权重和验收证据。
本项目至少要同时看以下维度；只有每一行都满足关闭条件，才能声明“全量长期治理 100%”。

| 维度 | 当前状态 | 直接证据 | 仍需满足的 100% 条件 |
|---|---|---|---|
| 工程成熟度矩阵 | 100%（11/11） | 本文“100% 成熟度账本”、`./dev check governance`、macOS governance XCTest | 保持证据随真实演进批次更新 |
| Cargo / CoreSDK 构建治理 | 已落地 | `.build/cargo/*` lane、Xcode dependency file、`./dev doctor build`、CoreSDK verify | 持续监控 cache 命中率和跨 lane 锁等待 |
| UI 反馈与场景化开发 | 已落地 | `#Preview`、developer scenario launcher、Python/Swift scenario inventory、Preview xcconfig | 为新增页面持续补齐状态/语言/窗口场景 |
| Swift 物理模块化 | 进行中 | `AreaMatrixCoreContracts`、`AreaMatrixCoreBridgeContract`、`AreaMatrixUIFoundation`、`AreaMatrixPlatformKit` 已作为 Swift Package 被 App target 真实链接；`CoreBridgeBoundary` 已独立并有 Package/Xcode 双重验证，运行时 CoreBridge、UniFFI 适配和 Feature 仍在 App target | 提取稳定的 CoreBridge runtime/适配边界并迁移 Feature 模块组；保持按能力分组，不创建一页一个 Package |
| Feature 依赖隔离 | 部分完成（生产 Feature scope 已显式化） | `AppCommandRouter`、App 组合 assembly、feature-local `FeatureManifest` 和 `FeatureManifestGraph` 已落地；Import 的 batch file loader、single-file preflight、batch/folder conflict prechecker 和 undo store 已由 `ImportFeatureDependencies` 经 `MainWindow` 显式传入；Feature `.live` 便利入口已移出生产 target，测试兼容入口只存在于 `AreaMatrixTests` | 继续把低风险平台 adapter 默认值按真实调用方收口到 App composition；高风险 CoreBridge 例外保持单独登记，不以万能容器隐藏风险 |
| 扩展注册机制 | 已落地（内置扩展） | Feature-owned manifest 已由 App registry 组合；`AreaMatrixCoreContracts` 提供 command / import-source / AI-provider 的 typed registry、依赖和 owner 校验；App runtime registry 对每个内置扩展执行 contract-version、未知 ID、缺失 registration 和重复 registration 门禁 | 继续随模块演进维护 manifest 与 registration；第三方运行时插件仍属于非目标，须另行完成签名、沙箱、权限和 API 兼容模型后再评估 |
| 本地验证与 CI | 部分完成 | changed validation、CoreSDK/绑定/治理门禁已存在 | `./dev test changed`、macOS 全量测试、远端 CI 和 branch protection 都有新鲜证据 |
| 正式发布与外部治理 | 未闭合（外部阻断） | residual：`v1-rl-002`、`v1-rl-003`、`v1-rl-004`、`v1-rl-006`、`v2-risk-001`、`v2-dep-003`、`v2-dep-004` | 真实 iCloud、Developer ID/公证/clean Mac、release decision、独立复核、remote CI/branch protection 证据闭合 |

因此，“还缺少 54%”不是当前有效结论。准确说法是：**工程成熟度矩阵已经达到本文定义的 100%，但全量长期治理仍未达到 100%，因为模块化、依赖隔离以及外部发布/治理证据仍未闭合；这些项不能用一个未经定义的百分比相加替代。**

最近同步依据：

- 当前文件系统审计显示主要 feature owner 已归位，`Models/` 当前为空，`Views/Main/` 和
  `Views/Settings/` 主要保留 shell / scaffold，`Views/Onboarding/` 当前无 Swift 文件。
- `AreaMatrixTests` 当前已有 shared shell / error / temp / mirror / naming-governance 底座，
  Import、Settings、Onboarding、AI、SyncConflicts、Detail、FileActions、MainList 均已有
  feature-local support / fixtures / test double。
- `TestRequestLog`、`TestResultQueue`、`TestStepQueue` 和 `VoidResultQueue` 已替代多组重复请求数组与
  手写结果队列；Rename、ChangeCategory 与 CommandPalette recorder 也已复用 request log，分类预测
  recorder 已服务 ChangeCategory、single-file Import、folder Import 和 drop Import。
- Database Repair 的 feature 与 integration 套件已共享
  `DatabaseRepairConfirmPageTestDoubleSupport.swift` 中的 metadata repair recorder 和语义请求断言，
  不再各自维护重复 `CoreMetadataRepairing` 实现；命名治理固定该 double 继续留在 TestDoubleSupport。
- TestSupport 命名治理已将 `*Tests.swift` 中 Recording / Recorder / Noop / TestDouble / Stub / Spy
  内联声明清零；精确 inventory 当前为空，任何新增内联 double 都会使测试失败。
- Batch Add Tags、Detail Note 与 Platform Differences 的 recorder 已分别归入 feature-local
  `BatchAddTagsTestDoubleSupport.swift`、`NoteTestDoubleSupport.swift` 和
  `PlatformIntrospectionTestDoubleSupport.swift`，并统一复用请求日志与语义断言。
- Change Category、Classifier Correction、Delete、External URL、Local File URL 与 Import Conflict
  的最后 9 个内联 double 已复用现有 owner 或归入 feature-local `*TestDoubleSupport.swift`；
  Import Conflict 的共享 preview fixture 现在保留 blocked item，apply report 也按实际策略统计。
- `SwiftFileSizeGovernanceTests` 已精确盘点所有达到 450 行的手写 Swift 文件并冻结其当前行数上界；
  `ConfigurationFixtures.swift` 与 `AppPlatformServiceAdapters.swift` 已分别按完整 fixture / platform adapter
  family 拆分；当前近阈值 inventory 只包含 454 行的 `MacOSArchitectureBoundaryGovernanceTests.swift`；
  `MacOSArchitectureBoundaryGovernanceTests.swift` 的通用文件扫描 helper 已提取到
  `MacOSGovernanceFileSystemTestSupport.swift`；当前新增的 remote provider platform contract 扫描仍保持在同一
  architecture governance owner 下，并要求下一次增长前继续提取独立扫描族或 shared assertion helper。
- 架构治理测试已固定生成 `ReindexReport` 只在 Bridge 转换，并显式盘点已迁入 PlatformServices 的
  Import session persistence，以及 iCloud placeholder download 与 AI Keychain 等仍需专项安全证据的例外。
- `MainRepositoryContentLifecycle` 已改为按原 modifier 顺序组合 FileActions、Search、SmartList、
  SyncConflicts 和 Import 的 feature-owned route host / relay；治理测试禁止具体 sheet builder 与
  Import conflict relay 回流，并固定对应实现留在各自 feature。
- FileActions 的四个 batch route、undo history route、undo toast state 与 action-log failure 已统一收敛为
  `MainFileActionRoutingState`；Import conflict command route 已统一经 `ImportConflictBatchRelayState`
  enqueue 并一次性消费。治理测试禁止这些裸 `@State` 回流 content shell。
- Undo History 菜单 relay、Command Palette 菜单 relay 与 undo / redo 快捷键 modifier 已分别归回
  FileActions 和 CommandPalette；lifecycle 只按既有 modifier 顺序组合 feature-owned command host，
  独立治理测试同时固定所有权与顺序。
- Command Palette 打开前搜索焦点记录、关闭后一次性恢复与重复切换状态已归入
  `CommandPaletteFocusRoutingState`，行为测试与治理测试不再用 shell 裸布尔值表达该 feature 状态。
- Search toolbar filter、sidebar tag filter 与 Smart List management route 已由
  `MainRepositorySearchRoutingState` 独立承载；两个 popover 仍保持不同状态，Smart List 编辑往返只监听
  toolbar filter dismiss，治理测试禁止对应裸 route state 回流 content shell。
- `MainRepositoryContentAssembly` 已在 App 层显式装配 content shell 的 Core / Platform 默认服务，
  包括 `MainFileListModel` 先前隐藏的六项默认依赖；View initializer 不再解析生产默认值，
  仍通过惰性 factory 创建并持有五个 `@StateObject` identity。
- `AppKitInteractionFeedbackPerformer` 已统一承接 appearance、cursor 与 haptic；架构测试禁止
  View-like 文件直接使用这些 AppKit API 或发布 `NotificationCenter.default.post`。
- classifier rule editor 保存结果已从进程级通知广播改为当前 route 的直接闭包回传，移除了多实例
  同时存活时误响应同一次保存事件的路径。
- classifier rule editor 的 load / save recovery state 已拆成互斥转换：加载失败不再同时伪造保存失败，
  保存失败保持已加载 snapshot 与用户 draft，并由回归测试固定 retry 所需状态不丢失。
- configured repository bootstrap、打开已有仓库与初始化完成后的首次打开现在统一通过
  `beginMainOpening(repoPath:scanSession:)` 建立 cancellation token、startup recovery checking、可选 scan session
  与 tree loading 初始状态；三条入口只保留各自后续的保存路径和错误恢复语义。
- Repository Settings 的 stale repository path 同步失败会保留当前可见配置和待持久化 snapshot，错误横幅只重试
  `updateConfig`，不通过整页 reload 混淆可见路径与已持久化路径；成功后清除 pending sync 与错误状态。
- Repository、Advanced 与 About Settings diagnostics 共享 `SettingsDiagnosticsGeneration` 隔离异步结果；
  reload、离开页面或显式取消会使当前收集失效，已经在执行的 collector / exporter 即使随后返回，也不能
  把新状态覆盖成迟到的 collected / failed。
- initialization failure 与 main repository error diagnostics 在 `OnboardingModel` 内分别维护请求 generation；
  同一路由中取消 collecting 后，即使 Core collector 随后返回，也保持 idle，不再依赖 repo path 检查间接防护。
- Import progress 与 Database Repair diagnostics 也分别固定同路由取消 generation；Database Repair 页面退出会使
  collecting 结果失效，四类恢复入口均有挂起 collector 的迟到结果回归测试。
- `./dev bindings verify` 已使用 `Cargo.lock` 锁定的 UniFFI 生成器，在临时目录规范化并精确比较
  Xcode tracked Swift/header/module map；macOS CI 与 governance check 已固定该门禁，现存 tracked
  bindings 漂移也已同步消除。
- 最近一次完整 `./dev test macos`、SwiftFormat、SwiftLint、定向 feature tests 和架构治理 tests 均通过。
- 当前未以本文更新关闭任何 residual；分发证据与分发决策仍以 `workflow/residuals/` 和
  对应 version residual 为准。

## 到 100% 的治理目标

### 目标冻结与基线审计（40%-45%）

目的：把“架构清晰，执行层复用不足”的判断固化为可追踪基线。

范围：

- 本文维护 100% 目标、成熟度区间、完成证据和非目标。
- `docs/architecture/macos-frontend-architecture.md` 继续作为 macOS 前端落点规则。
- 审计当前 `Features/`、`PlatformServices/`、`Models/`、`Views/`、`Bridge/`、测试支撑和大文件风险。

稳定证据：

- 路线图、macOS 前端架构文档和 `apps/macos/AGENTS.md` 不互相冲突。
- 只读审计能列出当前 feature owner、平台副作用散落点、大文件候选和受控例外。
- docs / governance / quality / prompts / diff 检查通过，或明确记录未运行原因。

### 执行层样板化（45%-60%）

目的：让后续新功能有可复制的写法，而不是每个功能各写各的。

优先样板：

- `Features/MainList/`：列表过滤、selection、loading、error、empty、detail entry 和 Search / FileActions 交界。
- `Features/FileActions/`：单文件、多选、批量动作、确认、错误映射、刷新策略。
- `Features/Import/` 或 `Features/Settings/`：一个高风险路径样板，一个复杂设置页样板。

稳定证据：

- 至少两个 feature 具备稳定的 View / State / Actions / Support 边界。
- 新增同类能力时无需回到顶层 `Views/Main` 或顶层 `Models` 扩张。
- macOS build 和 `./dev test macos` 通过。

样板化治理矩阵：

| 顺序 | 治理项 | 当前证据 | 目标落点 | 验证门槛 |
|---:|---|---|---|---|
| 1 | MainList 剩余边界审计 | `Features/MainList/` 已承载 pane、state、selection、presentation、file table、loading、error、detail、external sync；`Models/MainFileList*` 已不再存在 | 保持 MainList 作为列表类样板，继续明确与 Detail、Search、FileActions、Import progress 的 route contract | 只读审计；docs / diff 检查 |
| 2 | MainList 样板拆分 | `Views/Main` 当前主要是 content shell、lifecycle、sidebar、toolbar；MainList 文件未超过 500 行 | 不改行为地继续收敛 shell 注入、route state、loading / error / empty 和 detail entry 样板 | macOS build、`./dev test macos` |
| 3 | FileActions 执行模式沉淀 | `Features/FileActions/` 已承载 rename / delete / category move / batch / tag sheets、state 与 routing support；相关 sheets 已归入 feature | 单文件、多选、批量动作共享 action state、confirmation、error mapping、refresh 和 undo pattern | macOS build、`./dev test macos`，高风险动作保留确认证据 |
| 4 | Import 高风险模板收口 | `Features/Import/` 已覆盖 single file、folder、batch、progress、result、conflict、iCloud placeholder；Import TestSupport 已明显成型 | 固化高风险 feature 的 View / State / Actions / Platform adapter / TestSupport 模板，平台副作用只在明确服务或受控例外内 | macOS build、`./dev test macos`，用户文件安全验证按任务风险补充 |
| 5 | Settings / Onboarding owner 稳定化 | `Features/Settings/` 与 `Features/Onboarding/` 已建立；`Views/Settings` 只剩通用 scaffold，`Views/Onboarding` 当前无 Swift 文件 | 继续收口 App shell 初始化 / recovery 编排、危险设置验证口径和平台能力边界 | docs / diff 检查；进入代码迁移后跑 macOS build/test |
| 6 | TestSupport 复用主干整理 | `AreaMatrixTests` 已形成 shared shell / error / temp / mirror / naming-governance 底座，内联 double inventory 已清零，并有 feature-local support / fixtures / test double | 保持内联 inventory 为零，控制 shared builder 膨胀，按 feature 继续拆近 500 行 fixture / governance 文件 | macOS test；必要时补 feature-local verification |

这些治理项是长期边界参考，不是 live execution queue。进入正式代码实施前，若需要版本化推进，应按 `workflow/` discussion / changes / plans / drafts / queue / promotion 规则生成 copy-ready 与 verify-ready；小型局部改动也必须保留目标、非目标、落点、验证和回滚口径。

MainList 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| MainList 已归位部分 | `Features/MainList/` 已承载 list pane、state、selection、presentation support、file table、loading、current list error、detail actions 和 external sync actions | 保持为 MainList 样板基础，后续主列表展示、选择、loading、error、empty 继续优先落在这里 |
| Content shell 迁移区 | App 层 `MainRepositoryContentAssembly` 已承担生产默认服务装配；Import conflict relay、Import progress presentation / selection、FileActions batch / undo routing、Command Palette focus routing、Search tasks / semantic / filter routing、SyncConflict review routing 与 MainList error recovery contract 已归回各自 feature，`MainRepositoryContentLifecycle.swift` 只按原顺序组合 feature-owned host | 保持 shell 只做跨 feature 组合，不把 Search、Detail、FileActions、Import 实现重新混入 MainList |
| Detail 交界 | Detail view、note、tag、log、multi-selection summary 已归入 `Features/Detail/`，MainList 通过 detail entry / selected file contract 接入 | 只明确 MainList 到 Detail 的 entry contract；Detail 自身作为独立样板继续治理 |
| FileActions 交界 | `Features/FileActions/` 已有 rename / delete / category move / batch / tag sheets、state 与 routing support；MainList 仍触发 action route | 只保留 MainList 调起动作的 route contract；执行模式、refresh 和 undo policy 留给 FileActions 收口 |
| Search 交界 | `Features/Search/` 已承载搜索 UI、route、semantic search、saved search、smart list 支撑与 presentation routing state；toolbar / content shell 仍组合 feature entry | 不重构 Search 语义，只隔离 MainList 对 search results / visible files 的消费边界 |
| Import 交界 | Main list 支持空状态导入和 drop target；Import progress 的动态 presentation snapshot、selection state、table/detail projection 与选择互斥 relay 已由 `Features/Import/ImportProgressListIntegration.swift` 承载 | MainList 只摆放 Import 提供的 table/detail contract；导入执行和高风险模板继续留给 Import owner |
| 膨胀风险 | MainList feature 文件当前未超过 500 行；具体 sheet / dialog host、Import conflict relay、Import progress contract、FileActions batch / undo state、Command Palette focus state、Search tasks / presentation state、SyncConflict review state、error recovery contract 和默认服务装配已退出通用 lifecycle 实现 | 后续只在出现新的自然 owner 边界时继续拆分，不以单纯降行数为目标 |

MainList 收口建议：

1. 保持 `MainRepositoryContentView` / lifecycle shell 只组合 feature-owned contract，新增功能不得重新引入
   裸 route、progress selection、diagnostics fallback 或生产默认服务；生产装配继续由 App assembly 统一承担。
2. 保持 `MainFileListModel` 作为当前 MainList owner 内聚 model，避免过早拆出多个 store 导致 Search / Detail /
   FileActions 行为漂移。
3. 以 `Features/MainList/MainListPresentationSupport.swift`、`MainRepositoryContentFileTable.swift`
   等现有支撑为样板，后续新增 visible-file、count、empty/list status 和 progress presentation 能力优先放入 MainList。
4. 验证固定为 macOS build 和 `./dev test macos`；如果触碰 delete、move、iCloud conflict、import progress 或真实文件路径，再按高风险边界补充验证和回滚说明。

MainList 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 让 `Features/MainList/` 承担主列表展示入口、loading / empty / error 组合和可见文件 presentation 支撑，形成列表类 feature 可复制样板 |
| 允许触达 | `Features/MainList/**`、`Views/Main/MainRepositoryContentView.swift`、`Views/Main/MainRepositoryContentLifecycle.swift`、sidebar / toolbar shell，以及必要的 Xcode project 引用 |
| 暂不触达 | `CoreBridge` 合同、`core/area_matrix.udl`、Rust Core、真实文件删除 / 移动 / 导入行为、Search 语义、Detail 内部 tab、FileActions 执行动作 |
| 拆分产物 | 新增或扩展 MainList presentation / content entry 支撑，把 `visibleFiles`、`listCountText`、empty state、list loading indicator、current list error route 等从 content shell 中剥离出稳定边界 |
| 保留迁移区 | content shell 继续作为跨 feature 组合入口；Search、Detail、FileActions、Import 仍通过现有 contract 接入，后续按各自样板继续收口 |
| 风险控制 | 不改变 UI 文案、交互、Core 调用顺序、导入 drop target、搜索结果计算和 selection 行为；若发现必须触碰高风险文件路径或 Core 写操作，应暂停并重新评审 |
| 验证 | 代码变更后运行 `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO` 和 `./dev test macos`；docs 同步后运行 governance / skills / quality / prompts / diff 检查 |
| 回滚 | 保持纯结构性拆分；若验证失败且无法快速定位，应回退新增 MainList presentation / entry 文件和对应调用点，不影响已有功能闭环 |

FileActions 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| 已归位动作 model | `Features/FileActions/` 已承载 rename、delete、category move、batch delete、batch change category、batch rename、batch tag、confirmation sheet、route / state 的主要业务状态与动作入口 | 保持为 FileActions 样板基础，后续新增文件动作优先放入该 feature |
| Sheet 已归位部分 | `RenameFileSheet.swift`、`DeleteFileConfirmSheet.swift`、`ChangeCategorySheet.swift`、`BatchDeleteConfirmSheet.swift`、`BatchChangeCategorySheet.swift`、`MainFileActionRoutingSheet.swift` 已在 `Features/FileActions/` | 后续不再把文件动作 sheet 回流到 `Views/Main`；sheet 细分按单文件 / batch / tag / undo 自然边界推进 |
| Content glue 迁移区 | `MainFileActionRoutingState` 已统一承载四个 batch route、undo history route、undo toast state 与 action-log failure；默认 services 已由 App assembly 装配，primary / batch sheet host 已由 `Features/FileActions/` 持有，lifecycle 只组合 host | 继续提炼 FileActions refresh / undo policy；content shell 只持有一个 feature-owned 值，不把 Search、SmartList、SyncConflicts 一起迁入 FileActions |
| 高风险动作 | delete、remove from index、move category、rename、batch delete、batch rename 和 iCloud conflict resolution 都可能影响用户文件、metadata 或 undo / change log | 任何代码实施必须保留确认弹窗、disabled reason、undo token、error mapping 和 refresh 证据；触碰真实文件操作时按 file-safety 规则升级风险 |
| 测试支撑 | 已有 `RenameFilePageFeatureTests`、`DeleteFilePageFeatureTests`、`ChangeCategoryPageFeatureTests`、`FileActionsIntegrationVerifyTests`、`BatchDeletePageIntegrationVerifyTests`、`BatchChangeCategoryPageIntegrationVerifyTests`、`BatchRenameUndoPageFeatureTests` | FileActions 收口应复用这些测试作为回归证明；如迁移 route host，则补充 routing / sheet smoke 覆盖 |
| 膨胀风险 | FileActions 当前多个文件处于 300-400 行区间，尚未超过 500 行；风险集中在 route host、refresh / undo policy 和 batch action support 继续增长 | 拆分应以 action route、batch route、refresh / undo policy、state support 为自然边界，不以单纯降行数为目标 |

FileActions 收口建议：

1. 继续稳定 `Features/FileActions` 的 action route host / batch route support 边界，把文件动作 refresh、undo、
   disabled reason 和 sheet host 与 Search / SmartList route 分开。
2. 将 batch change category、batch delete、batch rename 的 route construction、disabled reason 和 apply refresh
   统一成可复用 support，避免 list context menu、detail multi-selection 和 command palette 各写一套 glue。
3. Sheet 已经归入 feature，后续按风险分层治理 sheet 内部结构：先处理低行为风险的 presentation / section
   support，再评估 delete、move、iCloud resolution 等高风险动作。
4. 保持 `MainFileListModel` 的动作方法作为当前执行入口；不在 FileActions 收口中重写 CoreBridge 调用、不改变 delete / move / rename 行为。

FileActions 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 让 `Features/FileActions/` 承担文件动作 route、confirmation、disabled reason、refresh / undo policy 的稳定样板 |
| 允许触达 | `Features/FileActions/**`、`Views/Main/MainRepositoryContentView.swift`、必要的 content shell route wiring 和 Xcode project 引用 |
| 暂不触达 | Core API / UDL、Rust Core、真实文件删除 / 移动算法、iCloud conflict resolution 语义、Search / SmartList route 语义、MainList presentation |
| 拆分产物 | FileActions route host / batch route support / refresh policy 支撑，复用单文件、多选、批量动作的确认、错误和刷新模式 |
| 风险控制 | 不改变确认弹窗、disabled reason、Core 调用顺序、undo token 处理、selection 清理、change log refresh、用户文件安全语义；若触碰真实文件操作或 iCloud resolution，应暂停并走高风险评审 |
| 验证 | 代码变更后运行 macOS build、`./dev test macos`，并重点关注 FileActions、Rename、Delete、ChangeCategory、BatchDelete、BatchChangeCategory、BatchRenameUndo 相关 XCTest |
| 回滚 | 保持结构性拆分；若验证失败且无法快速定位，应回退新增 FileActions support / host 文件和对应调用点，不影响现有动作闭环 |

Import 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| 已归位 feature owner | `Features/Import/` 已承载 single file、folder、batch copy、progress、result、drop target、duplicate / name conflict、iCloud placeholder、session recovery 和 conflict batch relay state 的主要 UI / state / actions | 保持 Import 为高风险 feature 样板；后续导入能力不回流到 `Views/Main` 或顶层 `Models` |
| 受控平台副作用 | `ImportPlatformServices.swift` 已承载 folder scan、source inspection 和 iCloud placeholder detection；`ImportSingleFilePreflightSupport.swift` 仍可触发 placeholder 下载；`ImportBatchSessionPlatformServices.swift` 承载 session persistence 实现，`ImportBatchCopyImportSession.swift` 只保留 snapshot / protocol / recovery 语义 | 这些属于 Import 高风险模板的一部分，后续应显式保留 preflight、placeholder policy、session recovery 和 no-user-file-touch 证据 |
| Core 写入边界 | single / batch / folder import 通过 CoreBridge import 能力进入 Core，Swift 层负责预检、选择、progress、retry、result route 和 recoverability 展示 | 不在 Import 收口中重写 Core 导入事务；只收口 Swift presentation、preflight、progress、retry 和测试支撑 |
| TestSupport 成型 | `ImportSingleFileTestSupport.swift`、`ImportBatchImportTestSupport.swift`、`ImportProgressTestSupport.swift`、`ImportResultTestSupport.swift`、`ImportFolderTestSupport.swift` 与配套 test double / fixtures 已覆盖 single、folder、batch、progress、result | 继续保持 Import feature-local support，避免新增导入测试复制 temp repo、mock bridge、fixture factory |
| 大文件风险 | Import feature 当前最大 Swift 文件处于 400 行左右；Import XCTest 当前未超过 500 行，但 `ImportFolderConflictResolutionTests.swift`、`ImportSingleFileNameConflictCoreTests.swift`、`ImportSingleFilePageIntegrationVerifyTests.swift` 仍偏大 | 按 preview state、copy session、progress route、result summary、fixture support 拆 natural boundary，不以行数本身为目标 |
| 用户文件安全 | copy / move / index、duplicate resolution、iCloud placeholder、folder scan、retry / recovery 都可能影响用户文件或 DB / filesystem 一致性 | 任何代码实施必须说明 touched files、forbidden touches、rollback / recovery、DB / filesystem 一致性验证；触碰真实导入执行时按 Mission-Critical 处理 |

Import 收口建议：

1. 继续维护 Import 高风险模板边界：preflight、source inspection、iCloud placeholder policy、duplicate / name
   conflict、progress / retry、result summary、session recovery、forbidden touches。
2. 继续收口测试支撑：保持 single / folder / batch / progress / result 的 feature-local support，
   保持内联 double inventory 为零，并对 duplicate precheck helper 做局部抽取。
3. 将 `ImportBatchCopyImportSession`、`ImportProgressRouteState`、`ImportResultRouteActions`
   作为恢复 / progress / result 样板，不在同一轮重写 Core import transaction。
4. 对平台副作用保持显式：folder scan 和 iCloud placeholder 下载应继续是受控服务 / adapter，不藏入 SwiftUI View。

Import 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 让 `Features/Import/` 成为高风险文件导入能力的 View / State / Actions / Platform-adapter / TestSupport 样板 |
| 允许触达 | `Features/Import/**`、Import 相关 XCTest support、必要的 docs / Xcode project 引用 |
| 暂不触达 | Core API / UDL、Rust Core 导入事务、真实文件 move / copy / index 算法、DB schema / migration、FSEvents 回流、非 Import feature |
| 拆分产物 | Import safety template、shared test support 边界、progress / retry / result / recovery support 的稳定落点 |
| 风险控制 | 不改变 copy / move / index 语义、duplicate strategy、replace confirmation、iCloud placeholder 下载触发条件、session file 路径或 DB / filesystem 一致性行为；若必须触碰这些行为，应暂停并进入高风险确认 |
| 验证 | 代码变更后运行 macOS build、`./dev test macos`，并重点关注 ImportSingleFile、ImportFolder、ImportBatch、ImportProgress、ImportResult、iCloud placeholder、duplicate / name conflict 相关 XCTest；触碰真实导入执行时补充 file-safety acceptance evidence |
| 回滚 | 保持结构性拆分或测试支撑收口；若验证失败且无法快速定位，应回退新增 Import support / template 文件和调用点，不影响现有导入闭环 |

Settings / Onboarding 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| Settings owner | `Features/Settings/` 已形成 General、Repository、Classifier、Integrations、Advanced、About、PlatformDifferences 分区；`Views/Settings` 只保留通用 scaffold | 后续新增设置项默认进入 Settings feature；继续收口危险设置、平台能力和测试支撑边界 |
| Onboarding owner | `Features/Onboarding/` 已承载 Welcome、ValidatePath、Initializing、InitDone、InitFailed、MainLoading、DB repair；`Views/Onboarding` 当前无 Swift 文件 | 后续重点是 App shell 初始化 / recovery 编排与 feature owner 的 contract，不再把 onboarding UI 放回旧目录 |
| 平台能力边界 | Settings / Onboarding 的 NSWorkspace、NSPasteboard、FileManager、path picker、capability probing 等能力已大量进入 `PlatformServices/` 或 App shell services | 新增平台能力优先进入 `PlatformServices/` 或 App shell services；迁移时保留现有注入点，不把平台副作用藏进 SwiftUI view |
| 大文件风险 | Settings / Onboarding feature 文件当前未超过 500 行；`ClassifierSettingsModel.swift`、`OnboardingInitializationProgress.swift` 等仍需按 pane、section、action state、platform adapter、support view 控制增长 | 按自然边界拆分；不为了目录完整一次性搬迁或为了行数拆散语义 |
| 测试支撑 | Settings 已有 Repository / Configuration / RemoteProvider / Classifier 等 support；Onboarding 已有 repository initialization、path validation、startup recovery、platform capability test double | Settings / Onboarding 收口继续保持 feature-local support 与 shared shell support 的归属，避免新的大参数 shared builder 膨胀 |
| 风险边界 | Settings 涉及 config 写入、classifier rules repair、diagnostics export、logs / Finder / pasteboard、repository health；Onboarding 涉及 path validation、repo init、startup recovery、import entry route | 不在 owner 切分中改变配置、初始化、repair、diagnostics、repo opening 或 import entry 语义；触碰真实初始化 / repair / file write 时按高风险规则确认 |

Settings / Onboarding 收口建议：

1. 保持 `Features/Settings/` 与 `Features/Onboarding/` 作为稳定 owner；后续新增页面、状态和 support
   不再扩张顶层 `Models` 或旧 `Views` 目录。
2. Settings 后续重点：classifier rules 写入、diagnostics export、repository health、integrations / iCloud
   能力继续保持平台服务和高风险验证边界。
3. Onboarding 后续重点：App shell 中的初始化、startup recovery、database repair 和 import entry route
   与 feature owner 的 contract 清晰化。
4. 平台 adapter 只随触达渐进迁移到 `PlatformServices` 或 App shell，不为目录完整一次性改所有注入。

Settings / Onboarding 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 稳定 Settings 与 Onboarding 的 feature owner，使后续设置页、首次启动、路径验证和初始化能力保持局部落地 |
| 允许触达 | `Features/Settings/**`、`Features/Onboarding/**`、`Views/Settings` 通用 scaffold、App shell contract、必要的测试 support 与 Xcode project 引用 |
| 暂不触达 | Core API / UDL、repo 初始化语义、startup recovery、classifier rules repair 写入、diagnostics export、真实配置写入行为、import entry 执行链 |
| 拆分产物 | Settings / Onboarding 子域 support、App shell contract、危险设置验证口径、测试 support 归属 |
| 风险控制 | 不改变配置保存、repo path validation、repo initialization、repair、diagnostics、Finder / pasteboard 操作或 import entry route；若实施中必须触碰这些行为，应暂停并重新评审 |
| 验证 | docs-only 运行 governance / skills / quality / prompts / diff；代码迁移后运行 macOS build、`./dev test macos`，并重点关注 Settings、ValidatePath、InitDone、InitFailed、Initializing 相关 XCTest |
| 回滚 | owner 切分应保持渐进；若验证失败且无法快速定位，应回退新增 feature owner 文件和迁移调用点，不影响现有 Settings / Onboarding 闭环 |

TestSupport 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| 共享底座 | `AreaMatrixShellTestDoubleSupport.swift` 已承担 shell 级 fixture、route requirement、settings/general/main-list/onboarding builder；`CoreErrorMappingTestDoubleSupport.swift`、`TestTemporaryDirectoryFileSystemTestSupport.swift`、`TestMirrorDescriptionSupport.swift` 已形成 error / temp / mirror shared support | 保持为 shared support 基线，只放跨多个 feature 共用且不携带业务语义的录制器、fixture builder、temp repo helper |
| feature-local 导入支撑 | `ImportSingleFileTestSupport.swift`、`ImportBatchImportTestSupport.swift`、`ImportProgressTestSupport.swift`、`ImportResultTestSupport.swift`、`ImportFolderTestSupport.swift` 与配套 fixtures / test double 已表达 single / folder / batch / progress / result 局部支撑 | 归入 Import feature-local support，避免复制 temp repo / downloader / preflight / scanner helper |
| feature-local settings / onboarding 支撑 | `RepositorySettingsTestSupport.swift`、`ConfigurationTestDoubleSupport.swift`、`RemoteProviderConfigTestSupport.swift`、`RepositoryInitializationTestDoubleSupport.swift`、`RepositoryPathValidationTestDoubleSupport.swift`、`StartupRecoveryTestDoubleSupport.swift` 等已分别对应 settings、remote provider、init / validate path / startup recovery 场景 | 这些应作为 feature-local support 或子域 support，继续按 Settings / Onboarding owner 归位 |
| 过大测试文件 | 当前 `AreaMatrixTests` 下没有超过 500 行的手写 Swift 文件；454 行的 `MacOSArchitectureBoundaryGovernanceTests.swift` 已进入近阈值 inventory，`RepoConfigSnapshot` 完整 fixture family 已迁入 `RepositoryConfigFixtures.swift`，`ConfigurationFixtures.swift` 降至阈值以下 | 保持 450 行精确清单和冻结上界；架构治理文件下一次增长前提取独立扫描族或 shared assertion helper，fixture 后续仍按完整语义族迁出 |
| 剩余重复 | 内联 recorder inventory 已清零；少量局部 file-system helper 和近阈值 fixture 仍需按触达场景治理 | 把真正跨 feature 可复用的 builder 抽到 shared support，其余只保留 feature-local helpers，不为目录整齐扩大迁移面 |
| 风险边界 | test support 会影响用户文件安全、temp repo 行为、import/recovery 证据、settings write / repair、startup recovery、iCloud / placeholder 相关验证 | 任何收口都不能删除必要的高风险验证；共享 support 只能复用构造，不得模糊风险证据或替代真实路径验证 |

TestSupport 收口建议：

1. 继续把 shared support 的边界写明：`AreaMatrixShellTestDoubleSupport` 仅收跨 feature 通用的 shell builder 和 route requirement，不能继续承载 feature-specific helper。
2. Import / Settings / Onboarding / SyncConflict / Validation 这几类高风险 feature 的 test support 保持 feature-local，必要时再抽子域 shared support，不直接回到顶层。
3. 维持 `SwiftFileSizeGovernanceTests` 的 450 行精确清单；测试 fixture 再次接近阈值时继续按完整 snapshot fixture family 迁出，而不是为了行数把语义拆散。
4. 新增测试默认先找 feature-local support；只有多个 feature 真正共享且不携带业务语义时，才提升到 shared support。

TestSupport 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 建立 `AreaMatrixTests` 的 shared support / feature-local support / high-risk fixture 边界，让新增测试直接复用而不是复制 helper |
| 允许触达 | `AreaMatrixTests/` 内的 `*TestSupport.swift`、`*TestFixtures.swift`、共同 helper、必要的测试命名与 Xcode project 引用 |
| 暂不触达 | 产品行为、Core API / UDL、Rust Core、真实文件系统语义、用户数据路径、只为压行而拆散断言 |
| 拆分产物 | shared support 归属规则、feature-local support 归属规则、fixture factory 命名约定、超长测试文件的治理口径 |
| 风险控制 | 不删除高风险测试证据，不把 integration verify 变成 mock-only，不用共享 helper 掩盖文件安全、DB、一致性或 recoverability 验证 |
| 验证 | docs-only 运行 governance / skills / quality / prompts / diff；代码迁移后运行相关 feature test / integration verify；高风险变更按 file-safety acceptance checklist 补充 evidence |
| 回滚 | 支撑代码调整应保持纯归属收口；若验证失败且无法快速定位，应回退 support 迁移和命名调整，不影响现有测试覆盖 |

### 复用主干建设（60%-75%）

目的：把反复出现的能力沉淀成工程资产。

范围：

- `PlatformServices/` 收口 FileManager、iCloud、FSEvents、open/save panel、NSWorkspace、Pasteboard、system capability probing。
- `Views/DesignSystem/` 收口真正跨 feature 复用的 UI 组件和状态视图。
- `AreaMatrixTests/Support` 或 feature-local `Support` 收口 temporary repo builder、mock / recording bridge、fixture factories、assertion helpers。
- 通用 loading / error / empty、async action、sheet / alert routing 模式有可复用实现或明确样板。

稳定证据：

- 新 feature 不再复制平台副作用、fixture、mock bridge 或同类错误状态处理。
- 仍保留在 `App/`、`Models/`、`Views/` 的迁移区代码有 owner 和退出条件。
- 高风险用户文件路径有失败、回滚、恢复和 forbidden-touch 测试或验收证据。

### 自动化治理（75%-90%）

目的：让架构规则不只靠人记忆。

候选门禁：

- 非 `Bridge/` 区域不得直接调用 UniFFI 生成函数。
- `Bridge/Generated/` 与 `Bridge/UniFFI/` 不得出现手写业务逻辑。
- SwiftUI View 中新增 FileManager、iCloud、watcher、NSWorkspace、NSPasteboard 等平台副作用需被检查或 review gate 捕获。
- 手写 Swift 文件达到 450 行后必须通过精确清单说明 owner、职责边界和拆分触发条件，且不得继续增长；500 行是硬上限。
- Core API / UDL / docs drift 继续保持可见。

当前证据：`./dev bindings verify` 已覆盖 UDL 到 Xcode tracked Swift bindings 的内容漂移，
`macos-ci.yml` 在 Core build 后执行该只读门禁，`./dev check governance` 防止 CI 步骤被静默移除；
macOS project / sources 缺失会直接阻断 build/test、SwiftLint 与 SwiftFormat，本地 `./dev check all`
也不再把缺失工程视为可跳过状态；`SwiftFileSizeGovernanceTests` 已覆盖手写 Swift 近阈值 inventory、
冻结上界和 500 行硬限制；`MacOSMigrationZoneGovernanceTests` 精确冻结顶层 `Models`、根 `Views`、
`Views/Main`、`Views/Onboarding` 与 `Views/Settings` 的当前保留文件、owner 和退出条件；
`MacOSFeatureOwnershipGovernanceTests` 精确冻结 12 个 Feature 目录及其职责、风险和验证重点；
生成绑定明确排除并由独立门禁治理。`./dev check governance` 同时核对所有 macOS governance XCTest
与 `AreaMatrixTests` Sources membership，避免门禁文件存在但未进入测试 target 的静默失效；macOS
runner 对本地 Xcode system content mismatch 也返回明确 blocked 状态，避免无 XCTest 证据时误报 PASS；
Core 与 macOS 的 `AREAMATRIX_*_RUNTIME` key 合同也由同一门禁双向核对。
macOS runner 的 `--coverage-gate` 还会从 `.xcresult` 读取 `xccov` JSON，按可执行行加权计算
Watcher 与手写 Bridge 覆盖率；当前真实全量 XCTest 证据分别为 66.67% 和 59.85%。

稳定证据：

- 本地 `./dev` check、CI 或 review checklist 能覆盖主要漂移。
- 触发规则时有清晰失败信息或 review 指南。
- 架构例外必须有原因、风险、退出条件和 owner。

### 长期稳定与模块化（90%-100%）

目的：只把真正稳定、复用明确的能力提升为更强边界。

可选方向：

- 将稳定 UI kit、平台服务抽象、测试支撑或纯 Swift utility 抽成 Swift Package。
- 为高复用 feature 模式提供轻量模板或 checklist。
- 将成熟自动化检查纳入默认 CI。
- 用 ADR 或架构文档记录重大的例外、模块化边界和重审条件。

稳定证据：

- 连续多个 feature 以局部改动完成，没有扩大旧迁移区。
- 旧迁移区有精确 inventory，新增文件回流会在本地 XCTest 与 macOS CI 中失败。
- 公共能力抽取有至少两个真实调用方，不为了抽象而抽象。
- 新贡献者可以从 docs 和 AGENTS 判断代码落点、验证命令和风险边界。
- 100% 目标的每条验收项都有文件、测试、CI、review 或审计证据支撑。

## 治理路线

### 1. Checkpoint 基线治理

目标：冻结已完成的架构规则和低风险归位成果。

范围：

- `apps/macos/AGENTS.md`
- `docs/architecture/macos-frontend-architecture.md`
- `docs/architecture/layered-design.md`
- `PlatformServices/` 起步
- `Features/Search/` 起步
- Bridge startup recovery 归位

稳定标准：

- macOS build 和 test 通过。
- docs / governance / quality / prompt / diff 检查通过。
- 后续改动能明确从这个节点继续演进。

### 2. MainList 样板化

目标：建立第一个低风险、主路径 feature 样板。

状态：样板基本成型。列表过滤、selection、状态 banner、当前列表错误视图、多选详情入口、
file table、presentation support 和 external sync actions 已归入 `Features/MainList/`；
后续重点是继续收敛 content shell 注入、route wiring 以及与 Detail / Search / FileActions /
Import progress 的 contract。

范围：

- 当前列表过滤与展示 helper。
- selection / detail entry / loading / current list error 等状态边界。
- 主列表 route 与 Search / FileActions / Detail 的交界。

稳定标准：

- `Features/MainList/` 成为新增主列表能力的默认落点。
- `Views/Main` 不再继续吸收新的主列表业务逻辑。
- 不再依赖顶层 `Models` 承载 MainList 状态；content shell 中的剩余组合逻辑有明确 owner。

### 3. FileActions 收拢

目标：统一 rename、delete、change category、batch actions、tag actions 的动作边界。

状态：动作 UI、状态和 route support 已归入 `Features/FileActions/`。rename、delete、
change category、batch delete、batch change category、batch rename、batch tag 和 confirmation
sheet 已有 feature 落点；后续重点是沉淀单文件、多选和批量动作的 refresh / undo / disabled
reason 复用模式。

范围：

- action state。
- sheet routing。
- CoreBridge 调用边界。
- 错误映射和刷新策略。

稳定标准：

- 新增文件动作时进入 `Features/FileActions/`。
- 单文件、多选、批量动作共享可复用支撑。
- 高风险删除、移动、重命名路径保持显式确认和测试证据。

### 4. SyncConflicts owner 归位

目标：把 iCloud conflict / sync conflict 的 review、preview、resolve、entry banner 与 routing
收敛到独立 feature，同时保持 Bridge 和用户文件安全边界清晰。

状态：owner 已归位。iCloud conflict / sync conflict 的主要 View、Model、State、Apply context、
routing actions 与 review sheet host 已归入 `Features/SyncConflicts/`；Bridge 封装仍保持在
`Bridge/`；review route state 与 sheet host 已由 SyncConflicts owner 承载，Main shell 只保留 feature host composition。

范围：

- iCloud conflict list / minimal review / resolution apply context。
- sync conflict entry / review / replace confirmation。
- review route 与 MainList / FileActions / Settings 入口交界。
- CoreBridge conflict listing / detecting / resolving 边界。

稳定标准：

- 新增 conflict review 或 resolution UI 默认进入 `Features/SyncConflicts/`。
- Bridge 继续作为 Core conflict API 的唯一手写入口。
- read-only listing、preview、resolve、Trash / backup / change-log 安全语义有测试证据。
- 不把 iCloud 下载、文件删除、覆盖、移动行为藏进 SwiftUI View。

### 5. Import 高风险治理

目标：把导入路径变成高风险 feature 的标准模板。

状态：高风险模板基本成型。single file、folder、batch、progress、result、duplicate /
naming conflict、iCloud placeholder 相关 View / Model / State / Actions 已归入
`Features/Import/`；`Bridge/CoreImporting.swift` 仍保持在 `Bridge/`。后续重点是继续明确
FileManager / iCloud / session persistence 等平台副作用边界，并保持 Import TestSupport 内联 double 为零。

范围：

- single file import。
- folder preview / scanner / batch import。
- duplicate conflict。
- iCloud placeholder。
- copy / move / index 模式。
- result summary 和 retry / recovery。

稳定标准：

- `Features/Import/` 有清晰 View / Model / State / Actions / Support 边界。
- 任何真实用户文件写入、移动、覆盖、占位符下载都能对应验证和回滚说明。
- 不把 FileManager 或 iCloud 副作用藏进 SwiftUI View。

### 6. Settings 分区

目标：设置页按能力域稳定拆分，避免继续膨胀。

状态：owner 已建立。General、Repository、Classifier、Integrations、Advanced、About 和
PlatformDifferences 已归入 `Features/Settings/`；`Views/Settings` 当前只保留通用 scaffold。
后续重点是危险设置、配置写入、classifier rules repair、diagnostics export 和 iCloud 设置的验证口径。

范围：

- General。
- Repository。
- Classifier。
- Integrations。
- Advanced。
- Diagnostics。
- Recovery。
- Privacy / AI。

稳定标准：

- 新增设置项能找到稳定 owner。
- 设置页 model 不继续吸收无关平台能力。
- 危险设置项保留确认、失败回滚和恢复入口。

### 7. AI feature 稳定化

目标：让 AI 能力继续扩展时不污染隐私、远程 provider、UI 状态和 CoreBridge 边界。

状态：owner 稳定。provider config、privacy rules、summary、classification suggestion、tag
suggestion、local model status 等能力已有 `Features/AI/` 落点；remote provider probe 的平台运行时已归位
到 `PlatformServices/RemoteProviderProbeService.swift`。Core 已拆成 prepare / complete 两阶段合同，平台层使用
Keychain 与受限 URLSession 执行 headers-only probe，禁止 redirect，只回传净化 outcome / HTTP status；旧 shell
runtime、全局环境变量和 Core 进程执行路径已移除。后续重点是保持 provider config / privacy rules / call log
之间的 consent 与 credential 生命周期证据，并继续收口少量直接 bridge 受控例外。

范围：

- provider config。
- privacy gate。
- summary editor。
- classification suggestion。
- semantic search fallback。
- call log / provenance。

稳定标准：

- AI 远程调用、用户数据离开本机、provider credential 都有明确边界。
- AI UI 状态和 Core / provider 调用不混在同一个大文件里。
- 本地优先与显式授权规则可被测试和 review。

### 8. PlatformServices 完整化

目标：统一平台副作用落点。

状态：复用主干在建。`PlatformServices/` 已覆盖 Import scan、Import session persistence、FSEvents watcher、iCloud status、
NSWorkspace、Pasteboard、settings / onboarding capability probing，以及 remote provider Keychain / URLSession probe；
App 层 interaction feedback adapter 已统一 appearance、cursor 与 haptic。Import placeholder 下载与 AI Keychain
仍是需要显式 owner 和安全证据的受控例外；现有平台 capability inventory 已覆盖 `FileHandle`、
`URL.resourceValues`、session persistence、URLSession、Security、脚本和环境变量等真实 IO。

范围：

- FileManager。
- iCloud。
- FSEvents。
- NSOpenPanel / NSSavePanel。
- NSWorkspace。
- NSPasteboard。
- system capability probing。

稳定标准：

- SwiftUI View 不直接做平台副作用。
- 可复用平台服务通过小接口注入 model 或 app shell。
- 仍留在 `App/` 或 `Models/` 的平台能力有退出条件。

### 9. Tests Support 收敛

目标：让测试支撑成为工程资产。

状态：复用主干已明显成型。shared shell / error / temp / mirror / naming-governance 支撑已存在，
多个 feature 已有 feature-local support / fixtures / test double；`RepoConfigSnapshot` 基础 fixture family
已从通用配置 fixture 中独立出来。后续重点是控制 `AreaMatrixShellTestDoubleSupport.swift`、
`TestSupportNamingGovernanceTests.swift` 继续膨胀，并保持内联 double inventory 为零。

范围：

- temporary repo builder。
- mock bridge / recording bridge。
- fixture factories。
- assertion helpers。
- feature-local test support。

稳定标准：

- 新增 feature 测试不复制大段支撑代码。
- 高风险路径有失败、回滚、恢复和 forbidden-touch 证据。
- fixture 命名能反映 feature owner。

### 10. 架构边界自动化

目标：让关键规则可检查。

候选检查：

- View / feature model 不直接调用 UniFFI 生成函数。
- `Bridge/Generated/` 和 `Bridge/UniFFI/` 无手写业务逻辑。
- 新增平台副作用优先进入 `PlatformServices/`。
- 新增复杂业务视图优先进入 `Features/<FeatureName>/`。
- Core API / UDL / docs drift 检查保持可见。

稳定标准：

- 本地 check 或 CI 能发现主要架构漂移。
- review 不再完全依赖人工记忆。

### 11. 文档与治理闭环

目标：保证工程规则长期不失真。

范围：

- `docs/architecture/**`
- `docs/roadmap/**`
- `apps/macos/AGENTS.md`
- `CODE_REVIEW.md`
- CI / governance checks

稳定标准：

- 文档讲清楚当前架构、执行路径、验证口径和非目标。
- 新人读文档能知道代码该放哪里。
- 每次 feature 治理都更新对应稳定证据或残余风险。

## 执行原则

- 不做一次性全仓库大搬家。
- 不为了行数拆分而拆分。
- 不改变 UI 行为作为架构治理的副作用。
- 不修改 Core API / UDL，除非发现明确漂移并单独评审。
- 不新增依赖，除非完成用途、许可证、替代方案和供应链风险评审。
- Import、FSEvents、iCloud、DB、reindex、staging recovery、删除、移动、覆盖等高风险边界必须单独说明影响、风险、验证和回滚。

## 验证策略

按改动路径选择最小充分验证：

- macOS 代码改动：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
./dev test macos
```

- docs / governance / prompt 相关改动：

```bash
./dev check governance
./dev check skills
./dev check quality
./dev check prompts
./dev check diff
```

- workflow discussion 或 execution 结构变更：按 `workflow/AGENTS.md` 运行对应 doctor。

## 进度更新规则

本文的百分比只表示工程成熟度，不表示产品功能数量。更新时必须依据当前文件、验证命令和审计证据，不根据主观感觉调整。

## Related

- [version-roadmap.md](version-roadmap.md)
- [../architecture/macos-frontend-architecture.md](../architecture/macos-frontend-architecture.md)
- [../architecture/layered-design.md](../architecture/layered-design.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../development/testing.md](../development/testing.md)
- [../../CODE_REVIEW.md](../../CODE_REVIEW.md)
