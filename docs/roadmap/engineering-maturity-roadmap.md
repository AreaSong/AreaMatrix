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

当前成熟度约为 B 后段到 C 入口：主架构清晰，规则已起步，接下来要把执行层复用和样板做实。

## 当前进度口径

当前状态：

- 核心功能闭环：已完成。
- 顶层运行架构：已清晰，采用 Rust Core / UniFFI / Swift Platform / SwiftUI Feature UI。
- macOS 前端落点规则：已稳定起步，已有 `Features/MainList/`、`Features/FileActions/`、
  `Features/Search/`、`Features/CommandPalette/`、`Features/SyncConflicts/`、
  `Features/AI/`、`Features/Import/` 和 `PlatformServices/`。
- 执行层复用：仍在迁移中。主要 feature owner 已开始归位，但 `Views/Main`、顶层
  `Models`、Settings / Onboarding 以及测试支撑仍承载较多历史代码；Import 已有 owner
  落点，但平台副作用抽取和测试支撑复用尚未完成。
- 当前治理重点：从“功能各自能跑”继续推进到“状态、动作、routing、validation、测试
  fixture 可以跨 feature 复用”。

因此当前工程成熟度按本文口径约为 40%-45%。这不是功能完成度，而是工程治理成熟度。

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
| 1 | MainList 剩余边界审计 | `Features/MainList/` 已有 pane、selection、status banner、visible filtering；`Models/MainFileList*` 和 `Views/Main/MainRepository*` 仍有主列表逻辑 | 明确 MainList、Detail、Search、FileActions 的交界和剩余迁移原因 | 只读审计；docs / diff 检查 |
| 2 | MainList 样板拆分 | `MainWindow.swift`、`MainFileListDetailSupport.swift`、`MainRepositoryContent*` 接近或超过 500 行 | 不改行为地收敛 route、state、loading、error、empty 和 detail entry 样板 | macOS build、`./dev test macos` |
| 3 | FileActions 执行模式沉淀 | `Features/FileActions/` 已有 rename / delete / category move / batch state；相关 sheets 仍在 `Views/Main` | 单文件、多选、批量动作共享 action state、confirmation、error mapping 和 refresh pattern | macOS build、`./dev test macos`，高风险动作保留确认证据 |
| 4 | Import 高风险模板收口 | `Features/Import/` 已有 single file、folder、batch、progress、result；测试 support 仍分散，FileManager / iCloud 副作用仍需继续隔离 | 固化高风险 feature 的 View / State / Actions / Support / TestSupport 模板，平台副作用只在明确服务或受控例外内 | macOS build、`./dev test macos`，用户文件安全验证按任务风险补充 |
| 5 | Settings / Onboarding owner 切分 | Settings 和 Onboarding 仍主要位于 `Views/Settings`、`Views/Onboarding` 和顶层 `Models` | 建立 `Features/Settings/`、`Features/Onboarding/` 迁移计划，先切分 owner，不一次性搬全量文件 | docs / diff 检查；进入代码迁移后跑 macOS build/test |
| 6 | TestSupport 基线整理 | `AreaMatrixTests` 下已有多个 `*TestSupport`、fixtures 和 page integration tests | 定义共享 support 与 feature-local support 的边界，避免新增测试复制支撑代码 | macOS test；必要时补 feature-local verification |

这些治理项是长期边界参考，不是 live execution queue。进入正式代码实施前，若需要版本化推进，应按 `workflow/` discussion / changes / plans / drafts / queue / promotion 规则生成 copy-ready 与 verify-ready；小型局部改动也必须保留目标、非目标、落点、验证和回滚口径。

MainList 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| MainList 已归位部分 | `Features/MainList/` 已承载 list pane、selection、status banner、visible filtering、current list error pane 和 multi-selection detail entry | 保持为 MainList 样板基础，优先让后续主列表展示、选择、loading、error、empty 继续落在这里 |
| Content shell 迁移区 | `Views/Main/MainRepositoryContentView.swift` 仍聚合 toolbar、sidebar、list、detail、search、semantic search、batch sheets、sync conflict route 和大量 CoreBridge 注入 | 先拆 view shell / route state / MainList entry，不在同一轮迁移 Search、Detail、FileActions 全部实现 |
| Detail 交界 | `Views/Main/MainRepositoryDetailPane.swift` 和 `Models/MainFileListDetailSupport.swift` 承担 detail tab、multi-selection summary、tag、note、log、semantic detail 和 sync conflict banner | 只明确 MainList 到 Detail 的 entry contract；Detail 自身作为独立样板，不混入 MainList 拆分 |
| FileActions 交界 | `Features/FileActions/` 已有 rename / delete / category move / batch state；但 action sheets、batch sheets 和 refresh glue 仍在 `Views/Main/**` | 只保留 MainList 调起动作的 route contract；执行模式沉淀留给 FileActions 收口 |
| Search 交界 | `Features/Search/` 已承载搜索 UI/route 组件；但 toolbar search state、semantic index confirmations、smart list sheets 仍由 `MainRepositoryContentView` 聚合 | 不重构 Search 语义，只隔离 MainList 对 search results / visible files 的消费边界 |
| Import 交界 | Main list 支持空状态导入、drop target、import progress rows 和 import progress detail | 保留导入入口与 progress row contract；Import 高风险模板留给 Import 收口 |
| 膨胀风险 | `MainWindow.swift` 540 行；`MainFileListDetailSupport.swift` 502 行；`MainRepositoryContentActionRouting.swift`、`MainListSystemActions.swift`、`MainFileListDiagnosticsActions.swift`、`MainRepositoryMultiSelectionActions.swift` 均接近 500 行 | 优先拆 natural boundary：window shell、content shell、routing、detail support、diagnostics / undo support；不以单纯降行数为目标 |

MainList 收口建议：

1. 从 `MainRepositoryContentView` 提取 MainList entry / content shell 支撑，降低主 content 对 list/detail/search/action 的直接耦合。
2. 保持 `MainFileListModel` 作为过渡聚合 model，避免过早拆出多个 store 导致 Search / Detail / FileActions 行为漂移。
3. 将 `Views/Main/MainRepositoryContentNoteDrafts.swift` 中与 `visibleFiles`、`listCountText`、empty/list status、selected import progress 相关的 MainList presentation support 收拢到 `Features/MainList/` 或明确留作 content-shell bridge。
4. 验证固定为 macOS build 和 `./dev test macos`；如果触碰 delete、move、iCloud conflict、import progress 或真实文件路径，再按高风险边界补充验证和回滚说明。

MainList 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 让 `Features/MainList/` 承担主列表展示入口、loading / empty / error 组合和可见文件 presentation 支撑，形成列表类 feature 可复制样板 |
| 允许触达 | `Features/MainList/**`、`Views/Main/MainRepositoryContentView.swift`、`Views/Main/MainRepositoryContentNoteDrafts.swift`，以及必要的 Xcode project 引用 |
| 暂不触达 | `CoreBridge` 合同、`core/area_matrix.udl`、Rust Core、真实文件删除 / 移动 / 导入行为、Search 语义、Detail 内部 tab、FileActions 执行动作 |
| 拆分产物 | 新增或扩展 MainList presentation / content entry 支撑，把 `visibleFiles`、`listCountText`、empty state、list loading indicator、current list error route 等从 content shell 中剥离出稳定边界 |
| 保留迁移区 | `MainFileListModel` 继续作为临时聚合 model；Search、Detail、FileActions 仍通过现有 contract 接入，后续按 FileActions 和 Detail 样板继续收口 |
| 风险控制 | 不改变 UI 文案、交互、Core 调用顺序、导入 drop target、搜索结果计算和 selection 行为；若发现必须触碰高风险文件路径或 Core 写操作，应暂停并重新评审 |
| 验证 | 代码变更后运行 `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO` 和 `./dev test macos`；docs 同步后运行 governance / skills / quality / prompts / diff 检查 |
| 回滚 | 保持纯结构性拆分；若验证失败且无法快速定位，应回退新增 MainList presentation / entry 文件和对应调用点，不影响已有功能闭环 |

FileActions 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| 已归位动作 model | `Features/FileActions/` 已承载 rename、delete、category move、batch delete、batch change category、batch rename route / state 的主要业务状态与动作入口 | 保持为 FileActions 样板基础，后续新增文件动作优先放入该 feature |
| Sheet 迁移区 | `RenameFileSheet.swift`、`DeleteFileConfirmSheet.swift`、`ChangeCategorySheet.swift`、`BatchDeleteConfirmSheet.swift`、`BatchChangeCategorySheet.swift`、`MainFileActionRoutingSheet.swift` 仍在 `Views/Main` | 先按单文件 action sheet 与 batch action sheet 两类分边界，不一次性搬完所有 sheet |
| Content glue 迁移区 | `MainRepositoryContentActionRouting.swift` 承担 action binding、route sheet、rename/delete/category submit wrapper、iCloud conflict apply 和部分 search / smart list route；`MainRepositoryContentCategoryMoveRefresh.swift` 与 `MainRepositoryMultiSelectionActions.swift` 承担 batch route、refresh、undo toast 和 selection glue | 优先提炼 FileActions route host / refresh policy，不把 Search、SmartList、SyncConflicts 一起迁入 FileActions |
| 高风险动作 | delete、remove from index、move category、rename、batch delete、batch rename 和 iCloud conflict resolution 都可能影响用户文件、metadata 或 undo / change log | 任何代码实施必须保留确认弹窗、disabled reason、undo token、error mapping 和 refresh 证据；触碰真实文件操作时按 file-safety 规则升级风险 |
| 测试支撑 | 已有 `RenameFilePageFeatureTests`、`DeleteFilePageFeatureTests`、`ChangeCategoryPageFeatureTests`、`FileActionsIntegrationVerifyTests`、`BatchDeletePageIntegrationVerifyTests`、`BatchChangeCategoryPageIntegrationVerifyTests`、`BatchRenameUndoPageFeatureTests` | FileActions 收口应复用这些测试作为回归证明；如迁移 route host，则补充 routing / sheet smoke 覆盖 |
| 膨胀风险 | `MainRepositoryContentActionRouting.swift` 498 行、`MainRepositoryContentCategoryMoveRefresh.swift` 494 行、`MainRepositoryMultiSelectionActions.swift` 497 行；`MainFileRenameActions.swift` 490 行、`MainFileCategoryMoveState.swift` 487 行 | 拆分应以 action route、batch route、refresh / undo policy、state support 为自然边界，不以单纯降行数为目标 |

FileActions 收口建议：

1. 先建立 `Features/FileActions` 的 action route host / batch route support 边界，把 `MainRepositoryContentActionRouting.swift`
   中 rename、delete、change category 的 submit wrapper 和 sheet host 与 Search / SmartList route 分开。
2. 将 batch change category、batch delete、batch rename 的 route construction、disabled reason 和 apply refresh
   统一成可复用 support，避免 list context menu、detail multi-selection 和 command palette 各写一套 glue。
3. Sheet 迁移按风险分层：先迁移或包裹低行为风险的 route host / support，再评估是否移动
   `RenameFileSheet`、`DeleteFileConfirmSheet`、`ChangeCategorySheet` 等 UI 文件。
4. 保持 `MainFileListModel` 的动作方法作为当前执行入口；不在 FileActions 收口中重写 CoreBridge 调用、不改变 delete / move / rename 行为。

FileActions 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 让 `Features/FileActions/` 承担文件动作 route、confirmation、disabled reason、refresh / undo policy 的稳定样板 |
| 允许触达 | `Features/FileActions/**`、`Views/Main/MainRepositoryContentActionRouting.swift`、`Views/Main/MainRepositoryContentCategoryMoveRefresh.swift`、`Views/Main/MainRepositoryMultiSelectionActions.swift`、必要的 sheet wrapper 和 Xcode project 引用 |
| 暂不触达 | Core API / UDL、Rust Core、真实文件删除 / 移动算法、iCloud conflict resolution 语义、Search / SmartList route 语义、MainList presentation |
| 拆分产物 | FileActions route host / batch route support / refresh policy 支撑，复用单文件、多选、批量动作的确认、错误和刷新模式 |
| 风险控制 | 不改变确认弹窗、disabled reason、Core 调用顺序、undo token 处理、selection 清理、change log refresh、用户文件安全语义；若触碰真实文件操作或 iCloud resolution，应暂停并走高风险评审 |
| 验证 | 代码变更后运行 macOS build、`./dev test macos`，并重点关注 FileActions、Rename、Delete、ChangeCategory、BatchDelete、BatchChangeCategory、BatchRenameUndo 相关 XCTest |
| 回滚 | 保持结构性拆分；若验证失败且无法快速定位，应回退新增 FileActions support / host 文件和对应调用点，不影响现有动作闭环 |

Import 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| 已归位 feature owner | `Features/Import/` 已承载 single file、folder、batch copy、progress、result、drop target、duplicate / name conflict、iCloud placeholder 和 session recovery 的主要 UI / state / actions | 保持 Import 为高风险 feature 样板；后续导入能力不回流到 `Views/Main` 或顶层 `Models` |
| 受控平台副作用 | `ImportSingleFilePreflight.swift` 会检查 source 文件、hash、iCloud placeholder 并触发 placeholder 下载；`ImportFolderScanner.swift` 会枚举目录；`ImportBatchCopyImportSession.swift` 会写入 / 清理 `.areamatrix/import-sessions/current.json` | 这些属于 Import 高风险模板的一部分，后续应显式保留 preflight、placeholder policy、session recovery 和 no-user-file-touch 证据 |
| Core 写入边界 | single / batch / folder import 通过 CoreBridge import 能力进入 Core，Swift 层负责预检、选择、progress、retry、result route 和 recoverability 展示 | 不在 Import 收口中重写 Core 导入事务；只收口 Swift presentation、preflight、progress、retry 和测试支撑 |
| TestSupport 分散 | `ImportSingleFileTestSupport.swift`、`ImportSingleFileTestFixtures.swift`、`ImportFolderTestSupport.swift`、`ImportBatchPrecheckTestSupport.swift` 及多组 integration verify tests 已存在，但支撑文件和 fixtures 跨 single / folder / batch 分散 | Import 收口优先定义 shared support 与 feature-local support 边界，避免新增导入测试继续复制 temp repo、mock bridge、fixture factory |
| 大文件风险 | `ImportBatchPreviewModel.swift` 500 行；`ImportBatchCopyImportState.swift` 499 行；`ImportEntrySheetView.swift` 491 行；`ImportBatchCopyImportModel.swift` 492 行；多个 Import XCTest 超过或接近 500 行 | 按 preview state、copy session、progress route、result summary、fixture support 拆 natural boundary，不以行数本身为目标 |
| 用户文件安全 | copy / move / index、duplicate resolution、iCloud placeholder、folder scan、retry / recovery 都可能影响用户文件或 DB / filesystem 一致性 | 任何代码实施必须说明 touched files、forbidden touches、rollback / recovery、DB / filesystem 一致性验证；触碰真实导入执行时按 Mission-Critical 处理 |

Import 收口建议：

1. 先建立 Import 高风险模板文档化边界：preflight、source inspection、iCloud placeholder policy、duplicate / name
   conflict、progress / retry、result summary、session recovery、forbidden touches。
2. 优先收口测试支撑：定义 `AreaMatrixTests` 中 Import shared support 与 single / folder / batch
   feature-local support 的边界，避免后续导入场景复制 temp repo 和 mock bridge。
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
| Settings owner | Settings 仍主要位于 `Views/Settings/**` 与顶层 `Models/*Settings*.swift`，暂未形成 `Features/Settings/` owner | 先建立 `Features/Settings/` owner 规则，再按触达页面迁移 General、Repository、Classifier、Advanced、Integrations、About 子域 |
| Onboarding owner | Onboarding 仍位于 `Views/Onboarding/**`、`Models/Onboarding*.swift` 与 `Models/AppShellModel.swift` 中的 `OnboardingModel` | 先建立 `Features/Onboarding/` owner 规则，再切分 Welcome、ValidatePath、Initializing、InitFailed、InitDone / main route |
| 平台能力分散 | Settings model / views 直接注入 NSWorkspace、NSPasteboard、FileManager、ignore rules manager、logs opener、repository revealer；Onboarding 通过 AppShellModel / AppPlatformServices 注入 picker、finder、file opener、path copier | 新增平台能力优先进入 `PlatformServices/` 或 App shell services；迁移时保留现有注入点，不把平台副作用藏进 SwiftUI view |
| 大文件风险 | `AdvancedSettingsSupportViews.swift` 527 行；`GeneralSettingsView.swift` 498 行；`AboutSettingsModel.swift` 499 行；`ClassifierSettingsModel.swift` 496 行；`OnboardingInitializationProgress.swift` 491 行；`ValidatePathStepView.swift` 466 行 | 按 pane、section、action state、platform adapter、support view 拆 natural boundary；先设 owner，不以行数直接搬家 |
| 测试支撑 | Settings 已有 page feature / integration verify / repository test support；Onboarding 已有 init / validate path / initialization tests 和 support，但命名仍跟旧顶层路径绑定 | Settings / Onboarding 收口先定义 feature-local tests support 与 shared support 的归属，迁移代码时同步测试命名与 Xcode project |
| 风险边界 | Settings 涉及 config 写入、classifier rules repair、diagnostics export、logs / Finder / pasteboard、repository health；Onboarding 涉及 path validation、repo init、startup recovery、import entry route | 不在 owner 切分中改变配置、初始化、repair、diagnostics、repo opening 或 import entry 语义；触碰真实初始化 / repair / file write 时按高风险规则确认 |

Settings / Onboarding 收口建议：

1. 先新增 owner 目录和局部规则：`Features/Settings/`、`Features/Onboarding/` 可先放
   `README.md` 或轻量 support 文件，明确子域落点、迁移顺序和禁止事项。
2. Settings 第一批候选迁移：低风险 support / presentation 文件优先，例如 Advanced support views、
   Repository config section / model support；暂不动 classifier recovery 写文件逻辑。
3. Onboarding 第一批候选迁移：Welcome / ValidatePath presentation support 优先；暂不动
   repo initialization、startup recovery、import entry route 和 `OnboardingModel` 主编排。
4. 平台 adapter 只随触达渐进迁移到 `PlatformServices/` 或 App shell，不为目录完整一次性改所有注入。

Settings / Onboarding 拆分边界模板：

| 项目 | 口径 |
|---|---|
| 目标 | 建立 Settings 与 Onboarding 的 feature owner，使后续设置页、首次启动、路径验证和初始化能力不再继续扩张顶层 `Models` / `Views` |
| 允许触达 | `Features/Settings/**`、`Features/Onboarding/**`、低风险 `Views/Settings/**` / `Views/Onboarding/**` presentation support、必要的测试 support 与 Xcode project 引用 |
| 暂不触达 | Core API / UDL、repo 初始化语义、startup recovery、classifier rules repair 写入、diagnostics export、真实配置写入行为、import entry 执行链 |
| 拆分产物 | Settings / Onboarding owner 规则、子域迁移顺序、低风险 support / presentation 样板、测试 support 归属 |
| 风险控制 | 不改变配置保存、repo path validation、repo initialization、repair、diagnostics、Finder / pasteboard 操作或 import entry route；若实施中必须触碰这些行为，应暂停并重新评审 |
| 验证 | docs-only 运行 governance / skills / quality / prompts / diff；代码迁移后运行 macOS build、`./dev test macos`，并重点关注 Settings、ValidatePath、InitDone、InitFailed、Initializing 相关 XCTest |
| 回滚 | owner 切分应保持渐进；若验证失败且无法快速定位，应回退新增 feature owner 文件和迁移调用点，不影响现有 Settings / Onboarding 闭环 |

TestSupport 当前边界记录：

| 边界 | 当前状态 | 收口口径 |
|---|---|---|
| 共享底座 | `AreaMatrixShellTestSupport.swift` 仍承担 shell 级别的 settings writer / config loader / repository opener / path validator / external syncer 等跨 feature 录制器 | 保持为 shared support 基线，只放跨多个 feature 共用且不携带业务语义的录制器、fixture builder、temp repo helper |
| feature-local 导入支撑 | `ImportSingleFileTestSupport.swift`、`ImportFolderTestSupport.swift`、`ImportBatchPrecheckTestSupport.swift`、`ImportSingleFileTestFixtures.swift` 已经表达单文件 / folder / batch 的局部支撑 | 归入 Import feature-local support，避免复制 temp repo / downloader / preflight / scanner helper |
| feature-local settings / onboarding 支撑 | `RepositorySettingsTestSupport.swift`、`RemoteProviderConfigTestSupport.swift`、`InitDoneTestSupport.swift`、`ValidatePathRepairTestSupport.swift` 等已分别对应 settings、remote provider、init / validate path repair 场景 | 这些应作为 feature-local support 或子域 support，继续按 Settings / Onboarding owner 归位 |
| 过大测试文件 | `MainListIntegrationFilterTests.swift` 635 行、`ChangeCategoryPageFeatureTests.swift` 656 行、`MainEmptyImportEntryTests.swift` 571 行、`MainRepoExternalRemovalTests.swift` 517 行、`ImportSingleFilePreflightTests.swift` 520 行、`ImportBatchResultSummaryTests.swift` 513 行 | 不以压行数为唯一目标，但应明确共享 support / fixture / helper 的边界，减少重复 setup 和 fixture 复制 |
| fixture 重复 | 多个 Import / Settings / Onboarding / SyncConflict 测试都在构建 temp repo、静态 settings reader、path validator、recording opener、recording mapper | 把真正跨 feature 可复用的 builder / recorder 抽到 shared support，其余只保留 feature-local helpers |
| 风险边界 | test support 会影响用户文件安全、temp repo 行为、import/recovery 证据、settings write / repair、startup recovery、iCloud / placeholder 相关验证 | 任何收口都不能删除必要的高风险验证；共享 support 只能复用构造，不得模糊风险证据或替代真实路径验证 |

TestSupport 收口建议：

1. 先把 shared support 的边界写明：`AreaMatrixShellTestSupport` 仅收跨 feature 通用的录制器和 repo 构造，不能继续承载 feature-specific helper。
2. Import / Settings / Onboarding / SyncConflict / Validation 这几类高风险 feature 的 test support 保持 feature-local，必要时再抽子域 shared support，不直接回到顶层。
3. 对过大的测试文件优先减少重复 setup、fixture 复制和 per-file builder，而不是为了行数把断言拆散。
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
- 接近或超过 500 行的 Swift 文件必须说明职责边界和拆分计划。
- Core API / UDL / docs drift 继续保持可见。

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

状态：已起步，列表过滤、selection、状态 banner、当前列表错误视图和多选详情入口已归入
`Features/MainList/`；后续重点是继续收敛剩余 `MainFileList*` 状态与 Detail / Search /
FileActions 交界。

范围：

- 当前列表过滤与展示 helper。
- selection / detail entry / loading / current list error 等状态边界。
- 主列表 route 与 Search / FileActions / Detail 的交界。

稳定标准：

- `Features/MainList/` 成为新增主列表能力的默认落点。
- `Views/Main` 不再继续吸收新的主列表业务逻辑。
- 顶层 `Models` 中 MainList 相关文件减少，剩余文件有明确迁移原因。

### 3. FileActions 收拢

目标：统一 rename、delete、change category、batch actions、tag actions 的动作边界。

状态：已起步，rename / delete / change category / batch state / routing actions 已归入
`Features/FileActions/`；后续重点是沉淀单文件、多选和批量动作的共享执行模式。

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

状态：已起步，iCloud conflict / sync conflict 的主要 View、Model、State、Apply context 和
routing actions 已归入 `Features/SyncConflicts/`；Bridge 封装仍保持在 `Bridge/`。

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

状态：已起步，single file、folder、batch、progress、result、duplicate / naming conflict、
iCloud placeholder 相关 View / Model / State / Actions 已归入 `Features/Import/`；
`Bridge/CoreImporting.swift` 仍保持在 `Bridge/`。后续重点是把 FileManager / iCloud /
session persistence 等可复用平台副作用进一步收敛到稳定服务边界，并收敛测试支撑。

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

状态：已起步，provider config、privacy rules、summary、classification suggestion、remote probe
等能力已有 `Features/AI/` 落点；后续重点是继续拆解接近 500 行的状态文件并收敛隐私 /
provider 执行支撑。

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
