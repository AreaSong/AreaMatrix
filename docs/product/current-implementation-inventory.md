# AreaMatrix 当前实现清单

> 本文以仓库提交 `4599e415` 为证据基线，汇总代码中已经存在的产品能力、macOS 界面、视觉与动效、实验客户端，以及明确未闭环的入口和风险。
>
> 阅读时长：约 45 分钟。

## 摘要

AreaMatrix 已经不是界面原型，而是一套由 Rust Core、UniFFI Bridge 和 SwiftUI macOS 应用组成的本地资料管理产品。正式产品覆盖资料库创建与接管、事务式导入、浏览与详情、分类与批量整理、普通与语义搜索、标签和 Smart List、Undo/Redo、AI 辅助、iCloud/同步冲突、元数据修复、诊断和设置。

macOS 是当前正式产品平台。欢迎页拥有完整的品牌级连续动画；初始化、主工作区、设置、导入、搜索和恢复页面则使用更克制的统一场景转场、玻璃材质、渐变背景、悬停反馈、进度和弹层动画。iOS、Windows 和 Linux 目录中存在真实代码与 Core 接入，但仍属于实验实现，不能等同于正式支持平台。

本清单也记录了若干“界面已出现但能力未闭环”的入口，以及静态审阅发现的文件边界、AI 隐私和减少动态效果等风险。它们不能被描述成已经完成的能力。

## 审阅基线与覆盖证据

本清单冻结在 Git 提交 `4599e4150cfd6d5e02152db4476893d7636cf51e`。覆盖扫描以该提交的 tracked tree 为输入，不把本次新建的清单文件或本机未跟踪材料混进产品基线。

| 覆盖项 | 结果 |
|---|---:|
| Git tracked entries | 4,708 |
| 读取的总字节数 | 150,465,728 |
| 全部换行数 | 1,673,334 |
| 文本文件 | 4,548 |
| 文本字节数 | 65,875,831 |
| 文本换行数 | 1,426,938 |
| 二进制文件 | 151 |
| 符号链接 | 9 |
| 无法读取 | 0 |
| 覆盖清单 SHA-256 | `b77d3ffada99b842a859707ac1523f9de99bfe6180b2137b4694a994e1cafd72` |

tracked tree 的主要组成是：`workflow` 2,417 个条目、`apps` 1,107 个、`core` 651 个、`assets` 185 个、`docs` 95 个、`tasks` 71 个、`scripts` 68 个。数量较大的 `workflow` 主要是版本化 prompt、执行证据和历史材料，不应被计算成产品页面或运行时能力。

本次审阅采用以下组合口径：

- 对 4,708 个 Git tracked entries 读取全部字节；符号链接按链接目标记录，确保没有目录或文件被静默漏掉。
- 对 `docs/`、`.ai-governance/`、Core UDL、Rust 关键实现、macOS 手写 SwiftUI 页面、平台桥接、测试入口和 residual ledger 做逐模块语义复核。
- 对大量 UniFFI 生成绑定、资源和二进制材料按生成合同、符号、文件元数据和调用边界抽查，而不是把生成代码误写成逐字人工通读。
- 仓库中可见 370 个 Rust integration test 源文件和 327 个 macOS Swift test 源文件；这些数字说明覆盖面，不代表本清单执行了全部测试。
- UI 的“页面”按顶层 route、主工作区稳定区域和用户可打开的 sheet/panel/dialog 统计；只服务布局的 Row、Section、Button 等内部组件不单独冒充页面。
- “已实现”只表示代码、Bridge 或产品界面已经存在；是否可正式分发仍取决于签名、公证、真实 iCloud 环境和独立复核等外部证据。

程序化覆盖证明“读到了什么”，不能替代人工语义理解；反过来，产品文档也不能替代源码中的真实状态。下面的功能与 UI 结论均以可定位的源码或长期文档为依据。动效说明属于静态源码审阅结果，本次没有把每个页面都在真实设备、真实 iCloud 和正式签名构建中逐一录屏复现。

状态含义：

| 状态 | 含义 |
|---|---|
| 正式实现 | 位于 macOS 正式产品路径，拥有真实 Core/Bridge 或平台服务支撑，并有相应状态与错误处理。 |
| 部分实现 | 主体存在，但有禁用按钮、缺失数据源、协议闭环不足或环境能力尚未接通。 |
| 实验实现 | 代码可运行或可测试，但不在正式平台支持合同中。 |
| 规划或历史材料 | 仅用于治理、参考或归档，不应被当作可用产品能力。 |

## 一页结论

| 领域 | 当前结论 |
|---|---|
| 正式客户端 | SwiftUI macOS 原生应用，单一 `WindowGroup`，窗口内路由承载 onboarding、主工作区、设置、导入和恢复。 |
| Core | 平台无关 Rust Core，通过 117 个 UDL 公开函数向客户端提供资料库、文件、查询、AI、同步和恢复能力。 |
| 数据 | SQLite 中定义 21 张业务与恢复表；用户原文件仍是资料内容源，`.areamatrix/` 保存应用元数据和生成内容。 |
| 资料库 | 支持创建空资料库、接管已有非空目录、路径校验、扫描恢复、重新索引、元数据修复和诊断。 |
| 文件管理 | 支持 Copy、Move、Index-only 导入，单项与批量整理，重复/冲突处理，Trash 删除和受支持动作的 Undo/Redo。 |
| 检索 | 支持普通搜索、筛选、排序、Saved Search、Smart List、命令面板和语义搜索入口。 |
| AI | 支持本地模型状态、远程 Provider 配置、分类、摘要、标签、隐私规则和调用日志；仍有隐私执行链与远程语义协议风险。 |
| 同步与云 | 支持 watcher 健康、外部变化回流、iCloud 状态、一般同步冲突和 iCloud 冲突审阅。 |
| UI 动效 | Welcome 是高动态品牌场景；其余页面以 0.5–0.8 秒的进入/转场、ambient background、material、hover 和 ProgressView 为主。 |
| 其他平台 | iOS、Windows、Linux 均为实验实现，不属于正式产品支持范围。 |

## 架构与正式平台边界

正式调用链为：

```text
SwiftUI View
  -> ViewModel / PlatformServices / CoreBridge
  -> UniFFI generated Swift binding
  -> Rust Core
  -> SQLite + repository filesystem
```

- macOS App 入口和唯一 `WindowGroup`：`apps/macos/AreaMatrix/App/AreaMatrixApp.swift:22-51`。
- 顶层窗口路由宿主：`apps/macos/AreaMatrix/Views/MainWindowRouteContent.swift:12-84`。
- Rust Core 模块入口：`core/src/lib.rs:8-58`。
- 架构职责和依赖方向：`docs/architecture/overview.md:9-43`。
- 正式平台与实验客户端边界：`docs/product/capability-direction.md:27-35`。

Core 不依赖 macOS 专属 API。目录选择、Finder、Trash、Keychain、iCloud placeholder 下载和 FSEvents 等能力留在 Swift 平台层；业务一致性、数据库、导入合同、冲突与恢复留在 Rust Core。

## Rust Core 已实现能力

`core/area_matrix.udl:2-564` 暴露 117 个公开函数。下面按产品职责归并，而不是按文件逐个罗列。

| 能力组 | 已实现内容 | 代表性 Core API |
|---|---|---|
| 运行时与绑定合同 | 版本、日志初始化、绑定兼容性检查、平台能力矩阵、统一错误映射。 | `get_version`、`init_logging`、`inspect_binding_contract`、`get_platform_capabilities`、`map_core_error` |
| 资料库生命周期 | 路径校验、创建或接管、配置读取与 CAS 更新、启动恢复、手动 rescan/reindex、扫描会话恢复、诊断、元数据修复。 | `validate_repo_path`、`init_repo`、`load_repo_config`、`update_repo_config`、`recover_on_startup`、`reindex_from_filesystem`、`repair_metadata` |
| 概览生成 | 内容语言状态、生成计划、启动、提交、查询、启动恢复、继续、取消和回滚。 | `prepare_overview_regeneration`、`start_overview_regeneration`、`commit_overview_regeneration`、`resume_overview_regeneration`、`rollback_overview_regeneration` |
| 导入与文件存储 | 分类预测、Copy/Move/Indexed 导入、删除到 Trash、移除索引、单文件重命名和改分类。 | `predict_category`、`import_file_with_result`、`delete_file`、`remove_index_entry`、`rename_file`、`move_to_category` |
| 批量操作 | 批量改分类、批量删除到 Trash、批量重命名的 preview token 与 apply。 | `preview_batch_move_to_category`、`batch_move_to_category`、`preview_batch_delete`、`batch_delete_to_trash`、`preview_batch_rename`、`batch_rename` |
| 分类器 | 手工纠正、保存规则、影响预览、规则列表、创建/更新/删除、恢复默认和恢复最后有效版本。 | `correct_file_category`、`save_classifier_rule`、`preview_classifier_rule_impact`、`create_classifier_rule`、`restore_last_valid_classifier` |
| 浏览与查询 | 文件列表、详情、目录树、普通搜索、facets、分页、Saved Search、Smart List 和命令索引。 | `list_files`、`get_file`、`list_tree_json`、`search_files`、`list_filter_facets`、`run_smart_list`、`list_command_targets` |
| 标签与笔记 | 单文件标签增删查、批量加标签、规则建议、AI 建议应用、Markdown sidecar 笔记读写。 | `add_tag`、`batch_add_tags`、`suggest_tags_for_file`、`apply_tag_suggestions`、`read_note`、`write_note` |
| Undo/Redo | 操作历史、可撤销资格、Undo、Redo 和结果反馈。 | `list_undo_actions`、`undo_action`、`list_redo_actions`、`redo_action` |
| 缺失文件恢复 | 缺失状态、重新链接、移除仅存数据库记录。 | `get_missing_file_state`、`relink_missing_file`、`remove_missing_file_record` |
| AI 配置与能力 | AI 配置、本地模型状态、远程 Provider probe/enable/disable、分类建议、摘要、标签建议、fallback、调用日志。 | `load_ai_config`、`get_local_model_status`、`prepare_remote_ai_provider_probe`、`suggest_category_with_ai`、`generate_ai_summary`、`suggest_tags_with_ai` |
| AI 隐私 | 隐私规则列表、更新和显式评估。 | `list_ai_privacy_rules`、`update_ai_privacy_rules`、`evaluate_ai_privacy` |
| 语义检索 | 语义查询和索引构建。 | `semantic_search`、`build_embedding_index` |
| 同步与云 | 一般同步冲突、iCloud 冲突、云存储状态、OneDrive 风险提示、导入冲突批处理、外部变化回流、内容语言恢复、FSEvents cursor 和 watcher 健康。 | `detect_sync_conflicts`、`resolve_sync_conflict`、`list_icloud_conflicts`、`resolve_icloud_conflict`、`sync_external_changes`、`record_watcher_health` |

Core API 的产品合同和错误语义集中在 `docs/api/core-api.md:2900-3023` 及其后的分组章节；UDL 是客户端绑定入口，不替代产品文档。

### Core 行为细节

- 普通搜索会检索文件名、相对路径、分类、笔记与索引元数据，并支持 `kind:`、`cat:` / `category:`、`after:`、`before:`、`tag:`、`note:`。解析器会识别未闭合引号、不平衡括号、未知字段、缺失值和非法日期，并给出位置或近似字段建议：`core/src/search/parser.rs:3-43,52-99,170-219,249-300`。
- 中文搜索包含一份常用汉字首字母映射，可用于有限的拼音首字母匹配；它不是完整拼音库：`core/src/search/pinyin.rs:1-32,34-201`。
- 导入实现不仅写数据库，还包含 hash 去重、目标路径规划、staging row、safe move、替换时 Trash/backup、源文件移除和失败恢复模块：`core/src/storage/mod.rs`、`core/src/storage/import.rs`、`core/src/storage/safe_move.rs`、`core/src/storage/replacement_trash.rs`。
- 文件监听与外部回流持久化 FSEvents cursor、watcher health、external sync receipt，并对 created/modified/removed/renamed 分支分别建模；平台只负责提供事件，Core 决定数据库和恢复语义。
- 测试合同还覆盖 camera import、Files 多选导入、Share Extension、mobile library/detail/repository connect、desktop main/import、Windows/Linux repository connect、cloud permission、command index、watcher、manual rescan 和跨平台 Replace。它们证明 Core/adapter 边界已经存在，但不自动把对应实验客户端升级为正式支持平台。

## 数据模型

`docs/architecture/data-model.md:25-47,131-145` 定义 21 张 SQLite 表。前 15 张属于核心 schema，后 6 张由相应能力首次使用时创建或检查：

| 表 | 责任 |
|---|---|
| `schema_version` | 数据库 schema 版本。 |
| `files` | 文件身份、相对路径、分类、存储模式、可用性和索引元数据。 |
| `change_log` | 导入、整理、同步、恢复等操作时间线。 |
| `notes` | 文件笔记和修订状态。 |
| `tags` | 文件标签关系。 |
| `undo_actions` | 可撤销动作及其恢复信息。 |
| `fs_event_cursor` | 外部文件事件消费位置。 |
| `external_sync_receipts` | 外部事件回流的幂等和结果记录。 |
| `scan_sessions` | 初始化、重新索引和恢复扫描会话。 |
| `repo_config` | 资料库级配置值。 |
| `repo_config_revision` | 配置 compare-and-swap 修订。 |
| `saved_searches` | Saved Search 和 Smart List。 |
| `recoverable_operations` | 可恢复长操作及其状态。 |
| `overview_regeneration_items` | 概览重生成条目进度。 |
| `overview_provenance` | 概览语言、来源和生成履历。 |
| `ai_call_log` | AI 调用审计。 |
| `ai_summaries` | 当前摘要内容与所有权。 |
| `ai_summary_revisions` | 摘要修订与冲突处理。 |
| `import_sessions` | 导入会话状态。 |
| `import_conflicts` | 导入冲突及决策。 |
| `semantic_index_entries` | 语义检索索引条目。 |

## macOS 顶层页面总览

`apps/macos/AreaMatrix/Features/Onboarding/OnboardingRoute.swift:4-22` 定义 18 个窗口级 route。所有 route 都由 `MainWindowRouteContent` 承载，并统一应用：

- `.id(routeIdentity)`，确保状态切换创建新的场景身份。
- `.transition(.areaMatrixScene)`。
- `.animation(.areaMatrixSceneFlow, value: routeIdentity)`。
- 插入时从 `opacity 0 + y 20 + scale 0.96` 进入；移除时向 `y -16 + scale 0.98` 淡出。

| Route / 页面 | 页面内容与主要交互 | 视觉与动效 |
|---|---|---|
| `loadingConfiguration` | 启动时读取全局配置并决定进入 onboarding 还是资料库。 | 玻璃内容面板、`ProgressView`、短延迟淡入；没有连续复杂动画。证据：`OnboardingIntroStepViews.swift:167-180`。 |
| `welcome` | 品牌欢迎、四张能力卡、键盘左右切换、主题预览、拖入目录、开始扫描叙事。 | 全产品最复杂动画：鼠标视差、渐变 blobs、卡片错峰进入、magnetic hover、glare、haptic、终端打字、扫描环、ripple、deep-dive 和白闪切场。证据：`WelcomeStepView.swift:85-135,295-364`。 |
| `choosePath` | 路径输入、系统目录选择、推荐路径、目录拖放、继续或返回。 | 标题在输入聚焦时降透明度；drop zone 边框 quick fade；页面本体使用 entrance motion。证据：`OnboardingIntroStepViews.swift:14-164`。 |
| `validatePath` | 展示路径、权限、是否已初始化、非空目录、iCloud、扫描会话等检查；支持重试或继续。 | checklist 行按状态切换图标和颜色，加载使用 `ProgressView`，错误/警告以 glass section 呈现。证据：`ValidatePathStepView.swift:3-67`。 |
| `confirmRepositoryInitialization` | 区分 Create 与 Adopt，解释将写入的元数据、安全不变量、iCloud 警告和退出确认。 | 重点是分层卡片、警告色和确认弹窗；随 route 做统一场景转场。证据：`ConfirmInitStepView.swift:3-130`。 |
| `initializing` | 展示初始化、扫描、恢复、步骤行、总体进度和 safe-point cancel。 | 进度条、旋转指示、步骤状态交替；取消采用停止在安全点的反馈，而不是立即消失。证据：`InitializingStepView.swift:3-150`。 |
| `initializationFailed` | 错误详情、恢复建议、脱敏诊断确认、重试、更换路径和退出。 | 红/橙状态卡、可展开诊断、确认 dialog；无品牌级循环动画。证据：`InitFailedStepView.swift:3-180`。 |
| `initializationDone` | 成功清单、Finder 入口、打开资料库和失败后重试。 | 成功色、完成图标、分组清单、页面进入动画。证据：`InitDoneStepView.swift:3-130`。 |
| `mainLoading` | 打开资料库、启动 recovery、加载 tree、扫描状态、错误、重试和取消。 | tree skeleton、`ProgressView`、状态文本切换；保留布局稳定。证据：`MainLoadingView.swift:3-147`。 |
| `mainRepoError` | 重试、重新连接、修复、诊断、Finder reveal，并区分外部移除。 | 错误插图/图标、glass actions、dialog 和 sheet；随重试状态显示进度。证据：`RepositoryErrorView.swift:68-249`。 |
| `dbRepairConfirm` | startup recovery、repair preflight、内容语言、metadata-only 确认、诊断、repair 或 rescan。 | 高风险警告层级、步骤和结果状态；执行时使用 progress，确认时使用 dialog。证据：`DatabaseRepairConfirmView.swift:43-195`。 |
| `settingsRepository` | 这是取消或过渡期间的 repository settings fallback，不是完整设置页。 | `ContentUnavailableView`，只有标准 route 过渡。证据：`OnboardingIntroStepViews.swift:4-12`。 |
| `settingsGeneral` | 完整七栏设置工作区。 | sidebar shell、material 分区、内容延迟进入；普通设置控件只做 hover、selection 和 sheet 过渡。证据：`GeneralSettingsView.swift:44-110`。 |
| `importProgress` | 导入队列、单项执行状态、停止在安全点、重试当前项、诊断和 Finder。 | 每项 `ProgressView`、状态色和结果切换；无 Welcome 式连续动画。证据：`ImportProgressView.swift:43-108`。 |
| `importResult` | Imported/Skipped/Failed 过滤、逐项详情、标签建议、已有文件、失败重试、change log 和脱敏导出。 | 结果筛选切换、状态图标、sheet/alert、页面进入动画。证据：`ImportResultView.swift:18-115,170-228`。 |
| `mainEmpty` | 进入三栏主工作区，但资料库当前没有可展示文件。 | 通用 empty-state：图标 glow、标题/正文/按钮 stagger、CTA shimmer 和 hover。 |
| `mainList` | 完整三栏资料库工作区。 | ambient 背景降噪，表格/侧栏保持稳定；动作主要使用 hover、popover、sheet、toast 和统一 route transition。 |
| `configurationError` | 全局配置读取失败，支持重试或重新进入 setup。 | 错误 icon、说明、动作按钮和页面淡入。证据：`OnboardingIntroStepViews.swift:184-210`。 |

### 全局入口与快捷键

| 入口 | 行为 | 证据 |
|---|---|---|
| `⌘I` | 从菜单打开 Import。 | `apps/macos/AreaMatrix/App/AreaMatrixApp.swift:31-40` |
| `⌘,` | 打开 Settings。 | `apps/macos/AreaMatrix/App/AreaMatrixApp.swift:37-40` |
| `⌘K` | 打开或切换 Command Palette。 | `apps/macos/AreaMatrix/App/AreaMatrixApp.swift:42-45`、`MainRepositoryContentToolbar.swift:106-109` |
| `⌥⌘Z` | 打开 Undo History。 | `apps/macos/AreaMatrix/App/AreaMatrixApp.swift:46-49` |
| `⌘Z` | 在主工作区打开 Undo History 路径，而不是静默修改文件。 | `apps/macos/AreaMatrix/Features/FileActions/MainRepositoryContentUndoHistory.swift:12-21,93-98` |
| `⇧⌘Z` | 尝试执行最新 Redo；不可执行时打开带原因的 History。 | `MainRepositoryContentUndoHistory.swift:12-21,100-163` |
| `⌘F` | 聚焦普通搜索入口。 | `MainRepositoryContentToolbar.swift:101-105` |
| Welcome `⌘O` | 选择资料库目录。 | `apps/macos/AreaMatrix/Features/Onboarding/WelcomeStepView.swift:225-240` |
| Welcome `←` / `→` | 在能力场景间切换，并触发 alignment haptic。 | `WelcomeStepView.swift:73-82,285-292` |
| Finder / Dock Open Files | Finder 拖放、Dock/系统“打开文件”和多文件批次都会进入同一 Import Entry。 | `apps/macos/AreaMatrix/Features/Import/ImportEntryRequest.swift:3-8`、`AreaMatrixApp.swift:199-219` |

主窗口还提供 App Language sheet、setup 退出确认、全局顶部 toast 和导入 sheet。toast 以 `move(top) + opacity` 插入，不挤压主内容：`apps/macos/AreaMatrix/Views/MainWindow.swift:24-37,69-105,121-141`。

## 主资料库工作区

`apps/macos/AreaMatrix/Views/Main/MainRepositoryContentView.swift:116-137` 组合出真正的三栏生产界面。

### Toolbar

`MainRepositoryContentToolbar.swift:32-115` 已实现：

- 资料库菜单和资料库级操作。
- 普通搜索与语义搜索模式切换。
- search scope、sort 和 filters。
- Undo History。
- Import 和 Settings 入口。

Toolbar 使用系统 toolbar、popover、menu 和 sheet 动画，不做持续背景动画；搜索模式和筛选变化主要是 SwiftUI 状态切换与 quick fade。

### Sidebar

`MainRepositoryContentSidebar.swift:35-170` 已实现：

- 分类目录树和文件计数。
- Tags filter。
- Smart Lists。
- 右键菜单。
- 文件拖放目标和改分类入口。

视觉上以选中高亮、悬停、展开/折叠和 drop-target 边框反馈为主。主工作区背景使用 subdued ambient 配色，避免与内容竞争。

### File List

`MainListPane.swift:21-68` 和 `MainRepositoryContentFileTable.swift:14-187` 已实现：

- loading、empty、error 和 list 状态。
- SwiftUI `Table`、多列排序、单选与多选、分页。
- 普通/语义结果分组和去重。
- Finder reveal、重命名、改分类、分类器纠正、删除、复制路径等单项菜单。
- 批量标签、批量分类、批量重命名和批量删除。

表格本身保持稳定，不对每一行做重动画；状态变化使用系统 selection、context menu、popover、sheet 和统一的 0.2–0.5 秒淡入。

### Detail Pane

`MainRepositoryDetailPane.swift:62-115` 根据上下文显示：

- 导入进度详情。
- 多选摘要。
- 单文件详情。
- loading、error、missing 和 empty 状态。

单文件详情由 `MainRepositorySelectedFileDetailPane.swift:44-148` 提供四个 tab：

| Tab | 已实现内容 | 动效与反馈 |
|---|---|---|
| Meta | 文件状态、标签、路径、大小、分类、来源、存储模式和文件动作。 | tab selection、tag popover、action menu、错误/成功反馈。 |
| Summary | AI 摘要加载、生成、编辑、保存、清除、revision conflict 和 provenance。 | 生成进度、保存状态、确认 dialog、内容 crossfade。 |
| Log | change-log 时间线、external sync、diagnostics。 | 时间线行进入、loading/error/empty 状态切换。 |
| Note | sidecar 笔记创建、编辑、自动保存和失败重试。 | 编辑状态、保存中/已保存提示和错误反馈，不做连续动画。 |

### 全局工作区 Overlay

`MainRepositoryContentView.swift:121-136` 还承载：

- Finder drop preview overlay。
- batch tag Undo toast。
- external sync banner。

Overlay 使用 0.8 秒级 motion token、material、阴影和淡入/移除；toast 和 banner 不改变主列表布局。

## macOS 二级页面、弹层与特殊状态

除 18 个窗口级 route 外，下面这些也是用户可以真实打开或到达的稳定界面。系统 `alert`、`confirmationDialog` 和只含一行说明的内部 Row 不重复拆成独立产品页。

| 页面 / surface | 已实现内容 | 视觉与动效 |
|---|---|---|
| App Language | 中英文界面语言 segmented picker，可从全局入口打开。 | 标准 sheet；选择后由 environment locale 刷新文本，无独立连续动画。`GeneralSettingsContentViews.swift:3-45`。 |
| Root `AREAMATRIX.md` Confirmation | 检查根文件是缺失、可安全追加受管块还是不安全；可 Reveal in Finder、取消或启用，明确永不写 `README.md`。 | 520 pt 警告 sheet，状态文字按可执行性变红；标准 sheet transition。`GeneralSettingsContentViews.swift:241-275`。 |
| Search Filters / Tags Filter | 分类、类型、导入/修改日期、storage、tag 以及 tag match mode；支持重置和立即刷新。 | toolbar/sidebar popover、filter chip quick fade、系统 Picker/DatePicker。 |
| Saved Search | 预览当前 query/scope/filters、命名、结果数、保存和进入 filter 编辑。 | 标准 action sheet，保存中 progress，错误 banner 和 confirmation。 |
| Smart List Management | Rename、Duplicate、Edit Query、Delete；编辑查询时实时跑 diagnostic/result count。 | 标准 sheet、模式化表单、loading/error/result 状态切换。`SmartListManagementSheet.swift:3-103`。 |
| Search Index Status | 显示 unavailable/indexing/ready、原 query/scope，支持 Retry/Close。 | 小型 action sheet；状态图标和标准 sheet transition。`SearchRouteViews.swift:3-40`。 |
| Query Error / Query Help | 解析错误、位置、建议和可安全应用的修正；Help popover 入口存在。 | 错误 banner + popover；Help 内容当前固定为 `Loading help...`，因此属于部分实现。 |
| Command Palette | Commands、Navigation、Current Selection、Recent、Smart Lists、File Candidates；键盘上下选择、Enter 执行、disabled reason。 | material overlay、输入聚焦、选中行高亮和 sheet transition。 |
| Classifier Rule Editor | 从设置或批量新分类 handoff 打开，编辑规则、校验并把分类结果带回原页面。 | master/detail selection、validation banner、sheet transition。 |
| Classifier Rule Handoff | “为什么分到这里”、关键词/扩展名候选、priority、规则预览、保存未来规则、进入影响预览。 | summary card、Toggle/Stepper、保存进度与成功/失败反馈。`ClassifierRuleHandoffRouteView.swift:3-175`。 |
| Classifier Impact Preview | 预览规则对现有文件的影响，支持返回规则编辑。 | preview table 和状态反馈；最终 apply 按钮仍禁用。 |
| Rename / Change Category / Classifier Correction | 文件名校验、冲突、Finder 入口；分类 preview、仅改 metadata 或移动文件、纠正分类并选择是否记住规则。 | 标准 sheet、inline validation、progress/result；高风险动作先 preview。 |
| Delete File | 根据 storage mode 选择 Move to Trash 或 Remove from Index，展示不可用原因和诊断。 | destructive sheet、Trash availability 状态和确认按钮。 |
| Batch Add Tags / Category / Rename / Delete | 多选摘要、disabled reason、preview token、apply、逐项结果与 Undo。批量重命名支持 prefix、date prefix、保留 basename + sequence 和 replace text。 | 标准 sheet、preview table、progress、结果色和 Undo toast。 |
| Tag Editor / Rule Suggestions | 手工增删标签、基于规则的标签建议、全选、编辑 slug/display name、应用和重试。 | popover 或 sheet、chip selection、inline validation。 |
| AI Tag Suggestions | 单文件高置信度选择、编辑、接受/拒绝、重试、隐私规则和调用日志追踪。 | chip/list 状态、ProgressView、apply 结果和嵌套 trace sheet。`AITagSuggestionsPanel.swift:3-103`。 |
| Batch AI Tag Suggestions | 至少两文件时打开；逐文件建议、接受高置信度/已选项、拒绝、确认 apply、失败重试。 | 720 pt sheet、confirmation dialog、loading/apply/result 状态；可继续打开 call detail 和 privacy rule。`BatchRenameTrigger.swift:213-323`。 |
| Undo History / Undo Preview / Redo Feedback | 加载 undo/redo action log、聚焦最近动作、预览受影响项、执行 Undo/Redo、展示过期/阻塞/失败原因。 | sheet、选中行、progress、toast；完成后局部刷新列表/详情/change log。 |
| AI Classification Suggestion | 请求建议、confidence/context、接受/拒绝/改分类/手工分类、move preview、remember rule。 | 建议状态 transition、confidence tint、ProgressView、apply confirmation。 |
| AI Fallback / Recovery | 显示 AI disabled、provider/model/privacy/internal failure 等原因；提供 retry、普通分类、Local Model Status 或 Remote Config。 | `ReasonStatusCard`、badge、disabled reason 和嵌套 recovery sheet。`AIClassificationFallbackStatusRegion.swift:22-70`。 |
| AI Call Detail | 按 ID 读取 feature、route、provider、model、status、sent fields、privacy rule、result/error；覆盖 loading/not-found/error/retry。 | 580 pt sheet、ProgressView、只读 key/value rows。`AIClassificationCallLogDetailSheet.swift:82-203`。 |
| AI Privacy Rule Reference | 从 AI 结果跳到具体 rule，显示类型、pattern、作用域、enabled、命中次数和 last match；支持 missing/error/retry。 | 540 pt sheet；只读详情和状态切换。`AIClassificationPrivacyRuleReference.swift:95-190`。 |
| Local Model Status / Diagnostics | 安装、路径、版本、大小、feature support、health check、安装帮助、Finder 和诊断摘要复制。 | status badge、progress、嵌套 diagnostics sheet；Repair 仍禁用。`LocalModelStatusView.swift:49-81,148-181,224-245`。 |
| Remote Provider Config | endpoint、model、Keychain credential、usage scopes、data-flow confirmation、probe、enable/disable 和删除 credential。 | 表单、probe progress、成功/失败 banner；disable 使用二级确认 sheet。 |
| AI Privacy Rules / Templates | master/detail CRUD、folder/category/keyword/extension/tag/field filtering、remote gate、规则测试、模板批量加入和未保存退出确认。 | 760 × 700 sheet、selection/editor、template sheet；focused rule 会 0.2 秒滚动到中央并保留约 1.2 秒高亮。`AIPrivacyRulesView.swift:388-392`、`AIPrivacyRulesRoute.swift:161-180`。 |
| AI Call Log | feature/route/status/date/search filters、列表和详情、删除 selected、clear all。 | filter/list/detail transition 与 destructive confirmation；脱敏导出尚未开放。 |
| Import Replace Confirmation | 单文件、多文件和文件夹各有 Replace preflight/confirmation；没有 Trash 或 Core safety plan 时禁止执行。 | 嵌套 sheet、警告摘要、明确确认和结果反馈。`ImportEntrySheetView.swift:184-203`。 |
| General Sync Conflict Review | conflict detail、strategy、preview、Replace confirmation、apply/retry/result。 | sheet、warning card、progress 和状态切换。 |
| iCloud Conflict List / Minimal Resolution | list/refresh/diagnostics/Finder；单项版本预览、Keep Both、Trash 前确认、apply/retry。 | list sheet 再打开 resolution sheet；标准 sheet、progress 和 destructive confirmation。 |
| Missing-file Recovery State | 详情页显示 missing/hash mismatch/unavailable/failed，打开系统文件选择器 relink，或移除仅存数据库记录。 | inline warning、原生 file picker、relink progress/result；没有自定义连续动画。 |
| Startup Recovery Status | main loading 内显示 checking/completed/warnings/failed、severity、recoverability、technical details 和 retry。 | tinted banner、DisclosureGroup、ProgressView/状态 icon；不是单独顶层 route。`StartupRecoveryErrorRecoveryView.swift:3-113`。 |

这些二级页面大多使用系统 sheet/popover/dialog 动画。复杂的循环动画没有分散到业务表单中，而是集中在 Welcome 和 Design System；这也是为什么“页面很多”不等于“每页都有独立炫技动画”。

## 设置工作区

`GeneralSettingsView.swift:95-110` 定义七个设置 tab。

| 设置页 | 已实现内容 | 视觉与动效 |
|---|---|---|
| General | Copy/Move/Index-only 默认导入模式；生成内容写入 `.areamatrix/generated/` 或受控根 `AREAMATRIX.md`；`ignore.yaml`；App language；Appearance。 | Form/Picker/Toggle、material section 和延迟 entrance；切换 root overview 会先打开安全确认。Appearance 当前只有 `system` 且 Picker 禁用。 |
| Repository | 路径、配置 revision、overview output、content language、cloud warning、fallback to Inbox、Replace 许可状态、健康、平台能力、概览重生成、安全操作、诊断和恢复入口。Replace 在本页只读展示，实际开关位于 Advanced。 | 状态 badge、capability rows、progress、warning card 和确认 dialog。 |
| Classifier | 规则列表和编辑器、CRUD、打开 YAML、恢复最后有效配置、恢复默认、validation 和影响预览。 | 选择高亮、editor state、validation feedback、sheet；影响预览的最终 apply 仍未开放。 |
| AI | 总开关、provider preference、分类/摘要/标签/语义功能 toggle、本地模型、远程 Provider、隐私、调用日志和 pause 状态。 | Toggle、segmented choice、状态 badge、嵌套 sheet 和确认 dialog；无持续背景动画。 |
| Integrations | iCloud 状态、风险提示、冲突列表和 Finder 入口。 | 云状态图标、warning、loading、list transition 和 sheet。 |
| Advanced | recovery tools、诊断、日志、概览输出、root `AREAMATRIX.md`、Replace import toggle。 | 高影响项使用 warning card 与二次确认；诊断使用 progress/result。 |
| About | App/Core/Bridge 版本、licenses、HTTPS links、脱敏诊断、日志，以及内嵌 Platform Capabilities / binding contract 检查。 | 信息分区、link hover、progress/result；不做品牌级动画。 |

设置窗口并不是 SwiftUI 独立 `Settings` Scene，而是主窗口 route。整个工作区使用 sidebar shell，内容视图在切换后延迟进入（`GeneralSettingsView.swift:44-52`）。

`overviewOutput` 在 General、Repository 和 Advanced 三个设置 surface 都可编辑。General 与 Advanced 在切换到根 `AREAMATRIX.md` 时会先展示文件状态与安全确认；Repository 使用带 revision 冲突处理的配置编辑器。三处修改的是同一个资料库配置字段，不是三套独立概览系统。

## 导入页面

### Import Entry Sheet

`ImportEntrySheetView.swift:108-205` 已实现三类内容形态：单文件、多文件和文件夹。进入方式不只 file picker，还包括 Finder drop、Dock / 系统 Open Files，以及从 Command Palette 恢复 import-conflict batch；目标可以是 Auto classify、指定 category 或 repository root：`ImportEntryRequest.swift:3-20,78-102`。

- 单文件 preview。
- 批量 destination、storage mode、naming 和 category override。
- 命名支持统一 prefix；批量重命名规则还支持 date prefix、保留 basename + sequence、replace text 和大小写敏感选项：`ImportBatchNamingOptionsSection.swift:3-113`。
- 文件夹 recursive scan。
- hidden files 和 symlink 选项。
- duplicate 与 name conflict 决策。
- iCloud placeholder 下载、失败和 retry。
- Replace 二次确认。
- conflict batch review，包括 Skip、Keep Both、Replace 和逐项决定所需的 preview/apply 状态。
- import session 和 retry context。

视觉上使用 thin material、渐变边框和 page entrance（`ImportEntrySheetView.swift:125-142`）。文件拖入和选择变化有 border/highlight 反馈；真实文件写入前通过 preview、确认、progress、result 分离副作用。

### Import Progress

`ImportProgressView.swift:43-108` 展示队列总进度、单项执行状态、停止在安全点、当前项重试、诊断和 Finder。动效以系统 `ProgressView`、状态 icon、颜色切换和结果淡入为主。

### Import Result

`ImportResultView.swift:18-115,170-228` 提供 Imported、Skipped、Failed 过滤，逐项原因，标签建议，已有文件入口，失败项重试，Core change log 和脱敏结果导出。动效为 filter selection、row state、sheet、alert 和标准页面进入。

## 搜索、Smart List 与命令面板

### 普通搜索与语义搜索

搜索路由和状态集中在 `MainRepositoryContentSearchRouting.swift:3-162`、`SearchEmptyRouteView.swift:3-109`、`QueryErrorRouteView.swift:3-130` 和 `SemanticSearchResultsView.swift:3-183`。

已实现：

- normal / semantic mode。
- query debounce。
- scope、sort、filters 和 tags。
- 文件名、路径、分类、笔记和已索引元数据搜索；不包含 PDF/图片 OCR 或任意文件内容全文索引。
- `kind:`、`cat:` / `category:`、`after:`、`before:`、`tag:`、`note:` 高级语法，以及引号/括号/日期/未知字段诊断。
- 有限的常用中文首字母匹配；不是完整拼音输入法或全文拼音索引。
- query parse error 和 empty state。
- Saved Search 创建和管理。
- Smart List 执行、复制、重命名、改查询和删除。
- indexing status、build 和 cancel confirmation。
- semantic/normal result grouping、dedupe、pagination 和 “Why this matched”。
- 隐私、AI call log 和 recovery route。

搜索交互保持工具型体验：输入与筛选使用 quick fade，结果分页和状态用标准 list transition；semantic build 使用 progress 和 cancel dialog，不使用 Welcome 的连续动画。

### Command Palette

`CommandPaletteView.swift:3-180`、`CommandPaletteState.swift:119-134` 和 `CommandPaletteRoutingSupport.swift:61-160` 实现：

- `Cmd-K` 打开。
- query、loading、error 和 empty。
- Commands、Navigation、Current Selection、Recent、Smart Lists 和 File Candidates 分组。
- 上下键、Enter、disabled reason 和 confirmation label。
- Import、Settings、Search、批量动作、Smart List、文件聚焦、帮助和关联页面路由。

命令面板使用 material overlay、输入焦点、选中行高亮和 sheet transition。

## AI 页面与工作流

| 页面或面板 | 已实现内容 | 状态与动效 |
|---|---|---|
| AI Settings | 总开关、provider preference、各 AI feature toggle、隐私入口、call log 和 pause。 | Toggle/Picker、状态 badge、sheet、confirm；`AISettingsPane.swift:80-190`。 |
| Local Model Status / Diagnostics | 安装状态、版本、路径、大小、feature support、health check、安装帮助、Finder、诊断摘要和复制。 | loading/progress、status badge、嵌套 diagnostics sheet；Repair 按钮目前禁用。 |
| Remote Provider Config | Provider URL、model、Keychain credential、usage scopes、data-flow confirmation、connection test、privacy gate、enable/disable/remove key。 | probe progress、成功/失败状态、credential confirm、sheet。 |
| Privacy Rules | list/create/edit/delete、templates、folder/category/keyword/extension/tag、field filtering、remote gate、规则测试和未保存退出确认。 | master/detail selection、editor validation、dialog、test result。 |
| AI Classification | Ask AI、confidence/context、accept/reject/change/manual、remember rule、move preview、fallback、privacy 和 call log。fallback 可打开 Local Model Status、Remote Config 或普通分类。 | 生成 progress、confidence color、suggestion transition、reason card、confirm。 |
| AI Summary | load/generate/regenerate/save/clear；generated/user-owned ownership；CAS revision conflict；privacy/provenance/call log；replace/reload/review。 | progress、内容 crossfade、save state、conflict dialog。 |
| AI Tags | single/batch；high-confidence、select、edit、apply、retry、reject、manual；privacy 和 call log。 | chip selection、loading、apply result、undo feedback；batch 使用独立 720 pt review sheet。 |
| AI Call Log / Detail | filters、date range、list/detail、sent fields、privacy/provider/model/result、delete selected 和 clear all；AI 分类/摘要/标签可直接跳到具体 call ID。 | filter/list/detail transition、nested sheet、destructive confirmation；redacted export 尚未开放。 |
| Privacy Rule Reference | 从 AI fallback 或 call trace 打开具体规则，显示 kind、pattern、applies-to、enabled、match count 和 last matched。 | 只读 sheet、loading/not-found/error/retry。 |

关键实现文件包括 `AISettingsPane.swift`、`LocalModelStatusView.swift`、`RemoteModelConfigSheet.swift`、`AIPrivacyRulesView.swift`、`AIClassificationSuggestionPanel.swift`、`AISummaryEditorView.swift`、`AITagSuggestionsPanel.swift` 和 `AIClassificationCallLogDetail.swift`。

## 文件操作与批量界面

主列表、详情 action menu、toolbar 和 Command Palette 可以打开以下真实 sheet/panel：

- Rename File。
- Change Category。
- Classifier Correction。
- Classifier Rule Handoff / “Why classified here”。
- Classifier Impact Preview。
- Delete File。
- Replace Confirmation。
- Batch Add Tags。
- Batch AI Tag Suggestions。
- Batch Category。
- Batch Rename。
- Batch Delete。
- Undo History、Undo Preview 和过期/阻塞原因。
- Redo latest 与 Redo Feedback。
- Tag Suggestions。
- Batch Tag Undo Toast。
- Missing-file Relink。

这些页面沿用同一交互规则：preview 与 apply 分离，高影响动作显示受影响文件和不可用原因，执行中显示 progress，结束后通过 toast、result、change log 或 Undo 状态反馈。

## 同步、iCloud 与冲突页面

### Needs Review

`apps/macos/AreaMatrix/Features/SyncConflicts/SyncConflictEntryView.swift:78-220` 提供 banner、panel 和 conflict list 入口，通知用户存在需要人工审阅的同步变化。

### General Sync Conflict Review

`SyncConflictReviewView.swift:89-242` 覆盖 notLoaded、loading、loaded、empty 和 failed，展示受影响版本、strategy picker、preview、apply result 和 replace confirmation。

### iCloud Conflict List

`ICloudConflictListView.swift:221-384` 覆盖 loading、empty、list 和 error；每一行可以 resolve 或 reveal，并提供 refresh、diagnostics 和 Finder。

### iCloud Minimal Resolution

`ICloudConflictMinimalSheet.swift:34-237` 展示 version preview、capability 和 strategy；支持 Keep Both，单版本进入 Trash 前二次确认，以及 apply、retry 和 diagnostics。

这些界面明确不自动删除冲突版本。UI 只收集决策，写操作由 Core resolve/report 合同执行。动画主要是状态切换、list、progress、sheet 和 confirmation dialog。

## 动效与视觉系统

### 通用 Motion Tokens

`apps/macos/AreaMatrix/Views/DesignSystem/Effects/AreaMatrixMotionTokens.swift:3-63` 定义统一节奏：

| Token | 数值 | 用途 |
|---|---:|---|
| Flash | 0.15 秒 | 短促高亮和确认闪现。 |
| Quick fade | 0.2 秒 | hover、边框、筛选和轻状态切换。 |
| Entrance | 0.5 秒 | 普通页面和内容进入。 |
| Theme toggle | 0.3 秒 | 主题预览切换。 |
| Hover settle | 0.4 秒 | 悬停离开后的视觉复位。 |
| Scene parallax | 0.16 秒 | 指针视差跟随。 |
| Scene enter/exit | 0.6 秒 | 顶层 route 切换。 |
| Overlay/progress | 0.8 秒 | overlay、扫描和强调进度。 |
| Deep dive | 0.6 秒 | Welcome 深入场景。 |
| Pulse | 2.5 秒 | 呼吸和保护状态。 |
| Glow | 1.25 秒 | 图标和 CTA 光晕。 |
| Scan ripple | 1.2 秒 | Welcome 扫描涟漪。 |
| Shimmer | 3–4 秒 | CTA、卡片表面和空态。 |
| Cursor blink | 0.45 秒 | Welcome 终端光标。 |
| Ambient blobs | 6 / 7 / 8 / 9 秒 | 四个背景色团的呼吸、位移和缩放。 |
| Ambient orbit | 60 秒 | 背景整体缓慢旋转。 |
| Spring | 0.6 秒，damping 0.8 | 场景与较大元素回弹。 |
| Hover spring | 0.3 秒，damping 0.6 | 卡片、图标和磁吸 hover。 |

### 场景转场

`apps/macos/AreaMatrix/Views/DesignSystem/Effects/AreaMatrixSceneMotion.swift:3-15,83-110` 实现：

- 页面插入：透明度 0、向下 20 pt、scale 0.96。
- 页面移除：透明度 0、向上 16 pt、scale 0.98。
- 场景元素还可组合 blur 16、2D rotation、3D rotation 和 pointer parallax ±12°。

### Ambient Background

`apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixAmbientBackground.swift:13-123` 实现四个渐变 blob 的呼吸、偏移、缩放和 60 秒 orbit，并叠加 blur、blend mode、noise 和 vignette。颜色和位置会随 scene 变化：onboarding 较鲜明，workspace/settings 更低对比。场景选择位于 `apps/macos/AreaMatrix/Views/MainWindow.swift:45-62,171-181`。

### 普通页面 Shell

`apps/macos/AreaMatrix/Views/DesignSystem/AreaMatrixPageShell.swift:3-39,54-127,148-170` 提供：

- thin material 玻璃面板、描边和 50 pt shadow。
- 页面从 `opacity 0 + y 12` 在 0.5 秒内延迟进入。
- empty state 的 icon glow、header/body/footer stagger、CTA shimmer 和 hover。

因此，普通工作区、设置、导入和恢复页面并非“没有动效”，但它们使用的是辅助理解和状态反馈的短动画，而不是 Welcome 的叙事式连续动画。

### 其他可见特效与反馈

| 效果 | 实现 |
|---|---|
| Decoded Text | 场景标题先用 ASCII 扰动尾部字符，再按字符逐步解码成目标文本；完成时触发 level-change haptic。`AreaMatrixTextEffects.swift:3-61`。 |
| Theme Toggle | sun/moon 使用 symbol replace，按钮 hover 放大，切换时旋转 360° 并触发 alignment haptic。`AreaMatrixControls.swift:3-65`。 |
| Primary CTA | pulse aura、glow breath、3–4 秒 shimmer、hover 上浮/缩放、阴影增强、magnetic hover 和 icon bounce。`AreaMatrixControls.swift:68-128,181-205`。 |
| Link Hover | 标题下划线显现；trailing arrow 旧图标向右上移出，新图标从左下滑入。`AreaMatrixControls.swift:131-179`。 |
| Launch Logo | logo 从 `y -20`、scale 0.85 以 spring 进入，并带 teal shadow。`AreaMatrixSceneComponents.swift:28-51`。 |
| Subtitle Breath | 欢迎副标题 opacity 在 1.0 与 0.72 间以 3 秒周期呼吸。`AreaMatrixSceneComponents.swift:54-84`。 |
| Folder Launch | 文件夹 glow/scale 脉冲，plus 发光，文档/图片/表格符号按不同周期上下漂浮。`AreaMatrixSceneComponents.swift:119-187`。 |
| Top Banner / Toast | 主窗口状态消息以 `.move(edge: .top) + opacity` 插入和移除。`MainWindow.swift:24-37`。 |
| Drop Overlay | 拖放图标使用持续 spring bounce，遮罩从 opacity + scale 0.96 进入。`AreaMatrixOverlays.swift:247-273`。 |
| AI Privacy Focus | 从 AI 结果跳到具体规则时，以 0.2 秒滚动到中心；目标保持约 1.2 秒强调背景/描边。`AIPrivacyRulesView.swift:388-392`、`AIPrivacyRulesRoute.swift:161-180`。 |

## Welcome 品牌场景详细动效

Welcome 是单独设计的动态体验。`WelcomeSceneSwitcher.swift:25-34` 定义六个场景：default、classify、security、tracking、help 和 start。

### 卡片与指针交互

`AreaMatrixFeatureCard.swift:59-116,119-220` 和 `WelcomeStepView.swift:85-135` 实现：

- 四张 Feature Card staggered entrance。
- 鼠标移动产生 ±12° 视差和卡片 3D 倾斜。
- hover 某张卡片时，其余卡片 opacity/saturation 降到约 0.4。
- 当前卡片出现 spotlight、glare、阴影、顶部 accent 和 icon bounce。
- magnetic hover 让按钮/卡片向指针轻微吸附。
- idle glare 在静止时循环扫过。
- 卡片对齐触发 haptic feedback。
- 支持键盘左右切换场景、theme override 和目录 drag overlay。

### Scan Sequence

`WelcomeStepView.swift:295-364` 和 `AreaMatrixOverlays.swift:64-173` 实现开始扫描后的完整序列：

1. ambient 背景 blur。
2. 主内容 blur、scale 和 opacity 下降。
3. terminal typewriter 逐字输出。
4. cursor 以 0.45 秒闪烁。
5. 扫描环持续旋转。
6. progress color wash 横向推进。
7. ripple 向外扩散。
8. scene step 依次切换。
9. deep dive 放大到约 2.5 倍。
10. white flash 覆盖窗口。
11. 切换到 Choose Path。

### 四组 Diorama

| Diorama | 已实现效果 | 证据 |
|---|---|---|
| Classification | 文件卡滑入、3D rotation、scan line、highlight flash 和分类落位。 | `AreaMatrixClassificationDiorama.swift` |
| Protection | shield pulse、数据流、spark 和 ripple。 | `AreaMatrixProtectionDiorama.swift` |
| Timeline | spinner、粒子、逐字文本和重命名 crossfade。 | `AreaMatrixTimelineDiorama.swift` |
| Workflow | 事件流、虚线位移、双向 pulse、数据库旋转与 glow。 | `AreaMatrixWorkflowDiorama.swift` |

## 实验客户端

这些目录证明跨平台探索并非空壳，但正式产品文档明确不把它们列为支持平台。

### iOS

Swift Package 包含 library、Share Extension、executable 和 test target；存在真实 `@main` App，并通过 FFI 连接 Core：`apps/ios/Package.swift:11-58`、`apps/ios/AreaMatrixApp/AreaMatrixIOSApp.swift:4-9`、`apps/ios/AreaMatrix/App/AreaMatrixIOSApp.swift:3-50`。

| iOS 页面 | 已实现内容 | 视觉与动效 |
|---|---|---|
| Connect Repository | iCloud / Files folder picker、security-scoped access、最近资料库、过期访问重连、只读 preflight 和 Help。 | `NavigationStack` + inset-grouped `List`；检查时显示 `ProgressView`，使用系统 navigation/sheet 动画。 |
| Create / Adopt Confirm | 空资料库创建；非空目录接管；metadata 和云风险 acknowledgment；失败重试、换目录、取消。 | 系统 destination push、Toggle、warning tint 和 progress。 |
| iCloud Permission | permission denied、access expired、placeholder 未下载、重试、打开 Settings 和重新选目录。 | 状态 icon、系统导航转场和 loading。 |
| Mobile Library | refresh、recent/name/size sort、文件、分类、Needs Review、share-import takeover report、sync conflict banner、Camera 和 Files 导入。 | 原生 List/toolbar/refresh、sheet 和 navigation；没有自定义连续动画。`MobileLibraryView.swift:148-518`。 |
| File Detail | segmented Meta / Log / Note；metadata、hash、来源、change log、只读 note、missing-file recovery 入口。 | Picker 切 tab，loading/error/empty 状态用系统 List transition。`MobileFileDetailView.swift:3-311`。 |
| Camera Import Review | 系统相机、照片预览、重拍、文件名、分类、Copy import、冲突处理、retry/result。 | 系统 camera sheet，再进入 review sheet；preview image、progress/status tint。`CameraImportView.swift:8-149`。 |
| Files Import Review | Files 多选、总大小、逐项 preview、目标分类、单文件改名、冲突策略、retry 和批量结果。 | 系统 file importer + review sheet；Replace 再打开二级确认 sheet。`FilesImportReviewSheet.swift:3-136`。 |
| Share Extension | 读取分享对象、选择资料库/分类、文件名、排队保存、打开主 App；主 App 启动后消费 queue。 | 系统 extension navigation、status icon 和 progress；没有品牌动效。`ShareImportView.swift:3-148`。 |
| Sync Conflict Review | Needs Review 入口、版本策略、Replace 明示确认和 apply。 | navigation destination、Toggle、destructive action 和状态反馈。 |
| Missing-file Recovery | locate、relink、retry、decide later、确认后仅删除数据库记录。 | sheet、系统 file picker、warning/destructive 状态。 |
| Repository Settings | 资料库摘要、fallback to Inbox、重连/换目录、平台能力和诊断。 | Form/List、Toggle、loading/error/result。 |
| Platform Differences | 平台 capability 与 binding contract 检查，可跳 Repository Settings。 | Picker、ProgressView 和 report rows；该页的 Export diagnostics 仍为空 action。 |

iOS 没有 macOS Welcome 那套 blobs、视差、Diorama 或 deep-dive；当前视觉主要依赖系统 List、NavigationStack、sheet、ProgressView 和 SF Symbols。

限制：`Package.swift` 的 linker 仍固定到仓库内 debug Core 路径（macOS/iOS 各一条 `-L.../debug`），因此这是实验客户端，不是可正式归档分发的 iOS 产品：`apps/ios/Package.swift:25-33`。

### Windows

Windows 存在真实 WinUI App、11 个顶层 XAML surface 和 native Core client 装配：`apps/windows/AreaMatrix/App.xaml.cs:5-18`、`apps/windows/AreaMatrix/MainWindow.xaml:13-45`、`apps/windows/AreaMatrix/MainWindow.xaml.cs:15-75`。

| Windows 页面 | 已实现内容 | 视觉与动效 |
|---|---|---|
| Choose Repository | folder picker、recent repositories、validation、Create/Adopt 路由。 | WinUI controls、InfoBar、ProgressRing；route 通过 `Visibility` 切换。 |
| OneDrive Notice | 云状态、风险说明、选本地目录、继续 OneDrive、打开 watcher status。 | Dialog-like XAML、状态文本和 ProgressRing。 |
| Create / Adopt Confirm | 空目录初始化；非空目录接管 acknowledgments、预览和错误恢复。 | 标准 XAML form、checkbox、warning/status。 |
| Main Window | toolbar、搜索、Needs Review、分类侧栏、文件表、详情栏、drag/drop 和 refresh。 | 三栏 Grid、ListView、InfoBar、ProgressRing；没有自定义 Storyboard。`WindowsMainWindow.xaml:79-356`。 |
| Import | 文件/文件夹/拖放、Copy/Move、preserve structure、preview/results、name conflict 和 Replace preflight/apply。 | Dialog XAML、progress/status、Replace confirmation 区域。 |
| Sync Conflict | main/detail banner、Review/Later/Retry、Replace plan、checkbox 和 apply。 | 可折叠 Border/InfoBar，状态由 visibility 切换。 |
| Missing-file Recovery | locate、relink、retry、仅删除记录。 | Dialog、warning 和 result state。 |
| Watcher Status | watcher 健康、restart、诊断、打开资料库和请求 rescan。 | status rows、ProgressRing、InfoBar。 |
| Rescan Confirm | preview、no-user-file-mutation 说明、确认、执行与结果。 | 二次确认、progress/result。 |
| Platform Differences | capability snapshot、binding target、supported APIs/type mappings/missing capabilities、跳 Repository Settings。 | ProgressRing 和 report list；本页 Export diagnostics 明确 unavailable。`apps/windows/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs:148-169`。 |
| Repository Settings | 资料库摘要、fallback to Inbox、重连/换目录、平台能力、诊断导出。 | Form-like XAML、InfoBar、异步导出状态；这里的诊断导出是真实实现，和 Platform Differences 页的禁用按钮不同。 |

Windows XAML/C# 中未发现 `Storyboard`、`DoubleAnimation`、`ConnectedAnimation` 或 Composition 动效定义；可见动态主要来自系统控件、ProgressRing、InfoBar 和页面 Visibility 切换。

限制：详情 `Log`、`Note` tab 明确 disabled：`WindowsMainWindow.xaml:346-355`。Replace 在缺少 Core plan、Recycle Bin 或 Core safety backup 时禁用。结论仍是实验实现，尚未进入正式支持合同。

### Linux

- C# ViewModel、Core bridge 和 GtkBuilder `.ui` 合同覆盖 Choose Repository、Local Folder Notice、Create/Adopt Confirm、Main Window、Sync Conflict、Import/Replace、Missing-file Recovery、Watcher Status、Rescan Confirm、Repository Settings 和 Platform Differences。
- `LinuxDesktopShell.CreateDefault` 会装配 native Core client、主查询、冲突、导入、恢复、watcher 和设置 service：`apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs:138-163`。
- `.ui` 文件包含真实 `GtkDialog`、`GtkBox`、`GtkColumnView`、`GtkDropTarget`、`GtkButton` 等合同；例如 Import 声明文件/文件夹、drop target、Copy/Move、Replace confirmation 和 results：`apps/linux/AreaMatrix/Features/Import/LinuxImportDialog.ui:4-211`。
- 这些页面没有可验证的生产动效；代码和 `.ui` 中未发现 animation/transition/spinner 实现。
- 关键限制是 `.csproj` 只有 `net9.0` 和 `.ui` CopyToOutput，没有生产 `OutputType`、GTK/Adwaita package dependency 或生产 `Program.cs`：`apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-20`。

结论：这是可测试的 headless shell、ViewModel/Core bridge 和 UI contract fixture，不是仓库中可直接启动的 GTK/Adwaita 桌面产品。

## 明确的部分实现或不可用入口

下列入口不能写成完整能力：

| 项目 | 当前状态 | 证据 |
|---|---|---|
| AI call-log 脱敏导出 | Action 为空且永久 disabled。 | `AIClassificationCallLogDetail.swift:203-207` |
| Local Model Repair | Action 为空且永久 disabled。 | `LocalModelStatusView.swift:166-174` |
| Clear AI generated suggestions | 按钮 disabled。 | `AISettingsPane.swift:180-186` |
| Classifier impact apply | 两个保存/apply 按钮 action 为空且 disabled；当前只有 preview。 | `ClassifierImpactPreviewSheet.swift:151-166` |
| Appearance | 仅有 `system`，Picker 永久 disabled。 | `GeneralSettingsContentViews.swift:162-171` |
| Semantic Pause | UI 控件存在，但没有对应 Core pause API 的完整闭环。 | `SemanticIndexBuildControls.swift:102-114` |
| Query Help | 固定显示 `Loading help...`，没有可见数据源。 | `QueryErrorRouteView.swift:116-130` |
| Platform Differences 导出诊断 | 明确显示 unavailable；这是诚实禁用，不是可执行功能。 | `apps/macos/AreaMatrix/Features/Settings/PlatformDifferencesView.swift:181-195` |
| Repository Settings fallback route | 只显示 `ContentUnavailableView`，不应误认为第二套完整设置页。 | `OnboardingIntroStepViews.swift:4-12` |
| iOS Platform Differences 诊断 | 按钮为空 action 且 disabled；iOS Repository Settings 的诊断入口是另一条实现，不能混为一谈。 | `apps/ios/AreaMatrix/Features/Help/PlatformDifferencesView.swift:292-302` |
| Windows 详情 Log / Note | 两个 tab 明确 disabled，只有 Meta 可用。 | `apps/windows/AreaMatrix/Features/Library/WindowsMainWindow.xaml:346-355` |
| Linux 生产 UI host | 有 ViewModel、Core bridge 和 `.ui` 合同，但没有 production executable、GTK/Adwaita dependency 或 `Program.cs`。 | `apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-20` |

另外，Welcome 的若干 Diorama 展示文本没有经过 `L10n`：`AreaMatrixClassificationDiorama.swift:90`、`AreaMatrixProtectionDiorama.swift:45`、`AreaMatrixTimelineDiorama.swift:214-217`。它们是本地化一致性风险。

## 静态审阅发现的实现风险

以下是代码静态审阅发现，尚未通过专项复现、攻击路径验证或真实环境测试确认，因此不能直接写成已经可利用的漏洞。

### AI 隐私控制链

- 隐私规则可以持久化：`core/src/ai_privacy_rules/persistence.rs:23-64`。
- 统一 evaluator 目前主要由显式 API 暴露：`core/src/ai_privacy_rules.rs:347-365`。
- 分类、标签和摘要 producer 使用各自的简化阻断判断：`core/src/ai_classification_suggestion/implementation.rs:47-55,101-115`、`core/src/ai_tags_suggestion/implementation.rs:54-62,120-135`、`core/src/ai_summary/implementation/privacy.rs:3-21`。

风险：用户保存的 folder、category、tag、extension 和 field filtering 规则，可能没有统一约束所有远程 classification/tags/summary payload。需要用真实规则矩阵和 outbound payload 测试确认。

### 文件与 symlink 边界

- 通用数据库连接没有与 repair 路径同等级的 `index.db` symlink 拒绝：`core/src/db/connection.rs:17-60,137-147`；对比 `core/src/repair.rs:525-533,712-731`。
- import、单项/批量改分类的中间目录检查可能跟随 symlink：`core/src/storage/destination.rs:279-301`、`core/src/storage/move_to_category/target.rs:57-76`、`core/src/batch_category/fs_move.rs:14-31`。
- overview generated parent 和 regeneration whitelist 主要依赖 lexical path 检查：`core/src/overview/mod.rs:80-128,232-240,494-506`、`core/src/overview/regeneration/execution.rs:374-391`。
- missing-file relink、AI context 和 semantic content 读取也需要统一的 no-follow/read boundary：`core/src/missing_file_recovery/filesystem.rs:55-99,124-168`、`core/src/ai_classification_suggestion/context.rs:72-95`、`core/src/ai_summary/context.rs:95-118`、`core/src/semantic_search/store/types.rs:268-294`。

风险：在恶意或异常 symlink 布局下，实际读写目标可能偏离资料库边界。需要专项 filesystem fixture 验证。

### Recovery 与 preview token

- 初始化重试会按名称和目录形状清理 `.areamatrix.init-*`，未见 creator marker 或 journal identity：`core/src/repo_init.rs:253-330`。
- batch category/rename preview token 没有绑定完整的文件 hash/size/mtime；batch delete 的 inspected state 更完整：`core/src/batch_category/plan.rs:275-291`、`core/src/batch_rename/plan_types.rs:204-219`、`core/src/batch_delete/inspect.rs:18-57,93-106`。

风险：异常目录命名或 preview/apply 之间的外部变化需要更严格的身份绑定和 stale-plan 测试。

### 语义搜索闭环

- 远程搜索 payload 主要包含 query/filter/pagination/provider，build payload 主要包含 filter/provider：`core/src/semantic_search/executor.rs:170-237`。
- 本地索引实现以 token terms 为主：`core/src/semantic_search/store.rs:31-53,163-180`。
- remote build 返回后仍写入本地 semantic index：`core/src/semantic_search/implementation.rs:292-358`。

结论：搜索入口、索引状态和远程 route 已存在，但“真实远程 embedding corpus 构建与检索”的协议闭环仍不足，应标为部分实现。

### 可访问性与动画

macOS 手写 UI 中未检索到 `accessibilityReduceMotion`、`reduceMotion` 或 Reduce Transparency 分支，同时检索到 36 处 `repeatForever`。对运动敏感用户而言，Welcome 的视差、blob、glare、scan、ripple 和 deep-dive 缺少系统级降级路径。

建议把 Reduce Motion 作为 P2 可访问性修复：关闭视差和循环动画，缩短场景位移，保留必要的 opacity 状态反馈。

## 工程与分发边界

- `scripts/dev_tools/`、`dev`、`task-loop` 和 `scripts/task_loop/` 是构建、检查、workflow、release、Codex OS 和静默任务循环工具，不是终端用户功能。
- `workflow/versions/**`、`workflow/templates/**`、`tasks/**` 和 `.codex/**` 是版本规划、prompt execution、证据、任务和代理运行材料；其中 v1 历史 execution 已完成或归档的任务状态不能冒充当前产品功能。
- `apps/macos/AreaMatrix/Bridge/Generated/**` 是 UniFFI 生成绑定，负责把 117 个 UDL API 映射到 Swift；大量重复类型和序列化代码不是额外业务能力。
- `assets/brand/**`、macOS asset catalog 和 AppIcon 是正式品牌资源；`assets/prototypes/landing/index.html`、`assets/prototypes/workspace/index.html` 及其修补脚本是视觉原型/参考，不是当前 App 内的网页页面。正式 macOS UI 已是 SwiftUI，不使用这些 prototype 充当运行时界面。
- iOS/Windows/Linux 的 test projects、Core contract tests 和 UI smoke tests证明相应边界可被自动核验，但不等同于已签名、已分发或正式支持。
- 历史 prompt execution 的完成度只证明任务材料和执行证据覆盖，不等于正式分发完成。
- 签名、公证、stapled disk image、clean Mac、真实 iCloud placeholder 和 tester/feedback 等外部证据由 [residual ledger](../../workflow/residuals/README.md) 统一记录。
- 独立 reviewer、远端 CI 和 branch protection 证据不能由本地代码检查替代。
- 历史愿景、模板和已关闭 backlog 只属于 reference，不是当前产品未完成项。

## 维护规则

当以下内容发生变化时，应同步更新本清单：

- `OnboardingRoute` 新增、删除或改变顶层页面。
- 主工作区、设置 tab、Import/AI/Conflict sheet 增删。
- `AreaMatrixMotionTokens` 或 Welcome 场景改变。
- Core UDL 新增、删除或破坏性调整公开函数。
- 正式平台支持边界改变。
- 上述部分实现入口完成闭环或被移除。
- 静态风险通过测试确认、修复或被证明不成立。

## Related

- [产品概览](overview.md)
- [产品能力](capabilities.md)
- [产品界面地图](product-surfaces.md)
- [用户工作流](workflows.md)
- [macOS 前端架构](../architecture/macos-frontend-architecture.md)
- [Core API](../api/core-api.md)
- [数据模型](../architecture/data-model.md)
- [文档导航](../README.md)
- [Residual Ledger](../../workflow/residuals/README.md)
