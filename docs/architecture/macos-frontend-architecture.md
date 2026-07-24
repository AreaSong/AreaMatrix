# macOS 前端架构稳定化

> 本文记录 AreaMatrix 当前 macOS SwiftUI 前端的长期落位规则。目标不是一次性重写，而是让新增功能高效复用、边界清楚、持续可验证。
>
> 阅读时长：约 5 分钟。

---

## 目标

当前实现已证明端到端路径可行。前端治理目标是：

- 新功能有明确落点，不再随机进入 `Views/Main` 或顶层 `Models`。
- 通用平台能力可复用，不在多个 model 或 view 中重复手写。
- Core / UniFFI / SwiftUI 边界稳定，避免调用路径漂移。
- 测试支撑可以复用，降低后续 feature 验证成本。
- 保持行为不变地渐进迁移，不用大重写替代真实治理。

## 目录职责

| 目录 | 职责 | 不应该放 |
|---|---|---|
| `App/` | app 入口、菜单、生命周期、依赖装配、全局服务启动 | feature 业务状态、页面局部动作 |
| `Bridge/` | `CoreBridge`、Core 调用封装、snapshot / DTO 转换、错误映射 | SwiftUI 视图、平台 UI 对话框、业务页面状态 |
| `Bridge/Generated/` | 本地生成 UniFFI 产物 | 手写业务逻辑 |
| `Bridge/UniFFI/` | Xcode 当前消费的 tracked UniFFI binding | 手写业务逻辑 |
| `PlatformServices/` | AppKit、FileManager、iCloud、FSEvents、open/save panel、NSWorkspace、Pasteboard、系统能力检测 | SwiftUI 视图、Core schema 语义、feature 局部状态 |
| `Features/<FeatureName>/` | 对应业务域的 View / Model / State / Actions / Support | 无 owner 的通用工具、跨 feature 平台副作用 |
| `Views/DesignSystem/` | 通用 UI 组件、主题、效果、控件 | 业务流程、Core 调用、文件 IO |
| `Views/` | 现有跨 feature 入口和迁移区 | 新增复杂业务 feature |
| `Models/` | 现有 UI state / presentation state / routing state 的迁移区 | 新增大型 feature model、平台适配实现 |
| `Resources/` | 静态资源 | 运行时生成内容 |

`PlatformServices/` 是目标落点；既有平台服务仍可能暂时留在 `App/` 或 `Models/`。触达相关代码时按风险和验证能力渐进迁移。

`Models/`、根 `Views/`、`Views/Main/`、`Views/Onboarding/` 与 `Views/Settings/` 由
`MacOSMigrationZoneGovernanceTests` 作为受控迁移区精确盘点。当前 `Models/` 和
`Views/Onboarding/` 已无 Swift 文件；其他保留项必须有 owner 和退出条件。删除或继续迁出时同步更新
inventory，新增业务 View / State / Action 不得回流这些目录。

## Feature 落点

新增或明显修改以下能力时，优先收敛到 feature 目录：

- `Features/MainList/`
- `Features/Import/`
- `Features/Settings/`
- `Features/Onboarding/`
- `Features/AI/`
- `Features/Search/`
- `Features/SyncConflicts/`
- `Features/FileActions/`
- `Features/CommandPalette/`
- `Features/Detail/`
- `Features/RepositoryLifecycle/`

每个 feature 可以按需要包含：

- `Views`
- `Model` / `State`
- `Actions`
- `Routing`
- `Support`
- feature-local tests support

只有当组件跨多个 feature 复用且不携带业务语义时，才放入 `Views/DesignSystem/` 或共享 support。

当前 11 个 Feature 目录由 `MacOSFeatureOwnershipGovernanceTests` 精确登记职责、风险边界和验证重点。
新增 Feature 目录必须先补 owner inventory；跨 feature 公共能力仍需至少两个真实调用方后再抽取。

## Bridge 边界

Swift 调用 Rust Core 的手写入口是 `Bridge/`。

- View 不直接调用 UniFFI 生成函数。
- Feature model 不绕过 `CoreBridge` 调用 Core 生成绑定。
- Core DTO 转成 Swift UI snapshot 的逻辑优先靠近 Bridge。
- `CoreError` 应尽量在 Bridge 或 model 边界映射成 App/UI 语义错误；View 不应承担错误分类。
- `Bridge/Generated/` 和 `Bridge/UniFFI/` 保持纯生成绑定。

受控例外必须明确。名称和职责为只读的 reader 必须使用 `SQLITE_OPEN_READONLY`，不得以 fallback
创建、迁移或修改 `.areamatrix/index.db`；需要写入或修复时必须进入独立的用户确认路径。

### SQLite 只读 reader 例外

当前登记两个 Bridge 层 SQLite 只读 reader：

| Reader | 用途 | 打开策略 | 失败与退出条件 |
|---|---|---|---|
| `SQLiteExistingRepositoryMetadataReader` | Core 正常打开前读取 schema version、repo path、last opened time | 有 WAL/SHM sidecar 时以 `SQLITE_OPEN_READONLY` 打开 live DB；无 sidecar 时使用 `immutable=1` URI | DB 缺失、损坏、schema 为空或高于支持上限时失败，不创建、迁移或修复；当 Core 提供等价的不可用态只读合同后移除例外 |
| `SQLiteAISummaryMetadataReader` | 读取已保存 AI summary 展示数据 | `SQLITE_OPEN_READONLY`，查询表存在性后读取单行 | 表缺失返回无数据；未知 route/context 或 DB 错误显式失败；当 Core summary read API 覆盖该展示合同后移除例外 |

两个 reader 都不能回退到 writable connection。live WAL 只读打开可能参与 SQLite 共享内存锁协调，
但 reader 不创建 metadata schema，不修改 `index.db` 或 `index.db-wal`，也不承担 repair/migration。

## 默认 Core 服务装配

macOS 默认 Core 服务由 `App/AppCoreServices.swift` 集中装配。Feature model 或 view
通过协议注入接收默认能力，测试代码继续显式注入 test double。

- 新增低风险 Core 默认能力优先进入 `AppCoreServices`，避免各 feature 自行构造
  `CoreBridge()`。
- 初始化、导入、DB 修复、同步冲突、iCloud conflict、AI 隐私 / 远程 provider
  等高风险专项路径允许受控保留直接 `CoreBridge()` 默认构造。
- 保留的直接 `CoreBridge()` 默认构造必须由治理测试登记；登记项变化时说明风险归属和收口条件。
- 不为了集中化把高风险写操作伪装成通用服务；先保持风险边界可见，再按专项收口。

### 受控例外治理地图

`MacOSDefaultCoreServicesGovernanceTests` 是直接 `CoreBridge()` 默认构造的代码级
inventory。保留项必须落入下列专项之一，并在收口时补充对应验证。

| 专项 | 入口文件 | 保留原因 | 收口条件 | 最小验证 |
|---|---|---|---|---|
| App shell 仓库生命周期 | `App/AppShellModel.swift` | 初始化、真实导入、startup recovery、外部变化同步会触碰用户文件、`.areamatrix/` 或 DB / FS 一致性 | 读校验、写初始化、导入、恢复、外部同步的默认能力分开装配；写路径仍能清楚暴露风险边界 | `AreaMatrixShellTests`、`AreaMatrixShellValidatePathTests`、`InitializingStepIntegrationTests`、相关 file-safety 测试 |
| Import 执行与预检 | `Features/Import/ImportEntrySheetView.swift`、`ImportBatchCopyImportModel.swift` | copy / move / index、duplicate / name conflict、iCloud placeholder 与导入 session 可能影响源文件、最终目录和 DB | 只读预览能力可集中；写入导入、冲突批处理、duplicate 预检必须由导入专项验证覆盖后再收口 | Import page / integration tests、duplicate / iCloud / storage-mode tests、file-safety acceptance evidence |
| DB repair 与 recovery | `Features/Onboarding/DatabaseRepairConfirmView.swift` | metadata repair、startup recovery 和 diagnostics 关系到 DB、`.areamatrix/` 与恢复语义 | repair、recovery、diagnostics 的默认能力分别声明；收口不改变确认、重试、诊断隐私门槛 | `DatabaseRepairConfirmPageFeatureTests`、startup recovery tests、DB / recovery file-safety evidence |
| AI 隐私与远程 provider | `Features/AI/AIPrivacyRulesModel.swift`、`RemoteProviderConfigModel.swift`、`RemoteProviderConfigState.swift` | 隐私规则写入、provider 启停、credential lifecycle 和远程能力涉及用户数据离开本机的边界 | 只读状态读取可集中；隐私规则写入、provider 修改、credential 操作保持单独边界和同意路径 | `AIPrivacyRulesPageIntegrationVerifyTests`、`RemoteProviderConfigFeatureTests`、credential lifecycle tests |
| Sync / iCloud conflict | `Features/SyncConflicts/SyncConflictReviewModel.swift` | conflict detect / preview / resolve / apply 可能影响外部变化回流、iCloud 副本和用户文件选择 | list / read-only 状态可集中；preview、resolve、apply 继续分离，并保留 replace / confirmation 防线 | SyncConflict / ICloudConflict page tests、replace confirmation tests、file-action integration tests |

## 本地化与 operation snapshot

`AppLocalizer` 是 application-owned 文案的响应式解析入口。Welcome 右上角只切换设备级
`AppLanguage`；General 设置页只编辑同一界面语言。当前资料库的 `RepoConfig.locale` 只由 Repository
设置页编辑，其他页面只展示只读摘要。两份设置不得通过共享 binding 或保存动作互相改写。

Welcome 控件显示保存的 preference，并按 `system -> zh-Hans -> en -> system` 单击循环；system 模式的
tooltip/accessibility value 同时展示当前 concrete resolution。Repository 的 follow-interface 摘要同样同时
展示 policy 与当前 resolution，不能把跟随状态伪装成固定 locale。

- String Catalog 的资源 locale 只控制翻译、语法和复数；瞬时应用 UI 的日期、数字、文件大小和货币使用
  `Locale.autoupdatingCurrent` 的 region 格式。持久化 generated content 使用内容 locale 对应的确定性格式，
  不读取设备 region，也不新增 region 参数。
- `AppLanguage.system` 只检查 preferred languages 第一项；第一项不支持时直接回退 `en`，不扫描后续项。
- `AppLanguage.system` 在 launch、application activation 与 locale-change notification 时重新解析并广播到
  所有窗口；显式语言不响应系统变化。未知持久化值按 `system` 运行但不隐式写回。
- AreaMatrix 自己的按钮、标签、错误、状态和通知属于 app-owned，必须经 `AppLocalizer`。系统 panel、系统
  菜单和 macOS 权限/服务 UI 属于 OS-owned，保留系统语言；应用不克隆系统文案来强制跟随应用语言。
- `AppDisplayText`、`LocalizedMessage`、catalog key 和翻译结果只用于 presentation，不得持久化到 import
  session、pending external window 或 recovery payload。可恢复状态只保存稳定 domain code、结构化参数和
  必要 verbatim 原值，恢复后再用当前界面语言解析。
- Accessibility label/value/hint/action/announcement 在赋值或发布时解析当前界面语言；
  `accessibilityIdentifier` 使用稳定英文标识，不经过 catalog。
- 仍由应用持有的 toast、banner、sheet 和 progress 使用 descriptor 并可重新解析；传给系统 panel、
  notification 或 service 的应用文案在交付时解析并冻结。
- 用户输入、路径、文件名、provider 名称和其他 verbatim 值不翻译；需要进入 UI state 时携带明确的
  verbatim reason，不伪装成可本地化 key。
- `system` repository policy 只保存跟随关系；current concrete locale 在每台设备独立解析。解析结果改变时
  clean content presentation 立即重投影但不增加 repository revision，dirty classifier draft 和已开始 operation
  继续使用冻结 locale。稳定 category order、file sort mode、selection、expanded state、scroll、focus、route、
  sheet 和 draft identity 不随界面或内容语言改变。

所有生成入口在 operation identity（操作身份）的线性化点捕获 concrete `zh-Hans` 或 `en`。同一次用户
batch 共用一个值；continuation、resume、replay、同一 external sync window 和 automatic provider
fallback 复用原值，new attempt 才重新捕获。设置保存与捕获通过 per-repository write coordinator 串行，
因此一次操作不会看到半提交设置。external window 惰性持有 locale：首次到达队首、准备第一次 Core
  attempt 时冻结；filtered-only window 不冻结。AI 在进入 privacy/provider await 前冻结。

终态失败后的用户显式 retry 是新 attempt；crash recovery、continuation、replay、rollback、同一 external
sync window 与同一 attempt 内的 provider fallback 复用原 context。Undo/Redo 恢复原字节和 provenance，
不按当前设置重新生成。持久化生成格式使用冻结 content locale、UTC 和 format contract version。

Core/UniFFI 请求显式携带快照；macOS 不通过进程级 setter 把界面语言同步给 Core。session/recovery
持久化稳定 operation code、结构化 payload、concrete locale 和必要原值，而不是 `AppDisplayText`。任何
可以在重启后继续生成内容的 import/recovery/external-sync/AI session 都必须持有这组字段；缺失或非法
locale 时 fail closed，不从当前设置补猜。已开始 operation 的 UI progress 可随界面语言刷新，但它产生的
内容保持原快照。

## Platform Services 边界

以下能力属于平台服务，不应藏入 SwiftUI View：

- `FileManager`
- iCloud placeholder 下载或状态检查
- FSEvents / watcher
- `NSOpenPanel` / `NSSavePanel`
- `NSWorkspace`
- `NSPasteboard`
- system capability probing
- OS logging wrappers

平台服务应通过小接口注入到 model 或 app shell，便于测试替身复用。不要为了一个调用点过度抽象；当能力跨 feature 复用或涉及用户文件安全边界时，再抽到稳定服务。

Import progress 在主列表中的临时行展示通过 `ImportProgressListPresentation` 传入，选择状态、row/detail
projection 和文件选择互斥 relay 由 Import feature 持有；MainList 只负责摆放 Import 提供的 table/detail contract，
不得重新持有裸 progress items 或 selection ID。

MainList error recovery 使用 `MainListErrorRecoveryActions` 接收非列表态的 retry / diagnostics fallback；
正常列表态的 diagnostics state 与收集动作继续由 `MainFileListModel` 管理。content shell 不直接保存独立的
diagnostics closure，也不改变 diagnostics 的隐私、脱敏或 Core snapshot 语义。

受控平台例外必须按真实副作用审计，不能只按 Swift API 名称判断：

- `Features/Import/ImportBatchCopyImportSession.swift` 只保留 session snapshot、协议和中断恢复语义；
  `PlatformServices/ImportBatchSessionPlatformServices.swift` 承载 app-owned
  `.areamatrix/import-sessions/current.json` 的 JSON / FileManager 实现。真实临时目录的 save / load /
  missing / corrupt / clear / permission 测试已固定其行为；后续演进仍需按 Import 高风险边界保留写入路径、
  失败降级和回滚证据。
- `PlatformServices/RemoteProviderProbeService.swift` 是独立高风险网络边界。Core 通过
  `prepare_remote_ai_provider_probe` 生成不含 secret 的 method / URL / header / auth / timeout 计划；共享
  `RemoteProviderProbeService` actor 只在平台层读取 Keychain，使用 ephemeral URLSession，禁止 redirect，
  在收到 response header 后立即取消 body，并只回传 transport outcome 与 HTTP status。Core 再通过
  `complete_remote_ai_provider_probe` 映射稳定状态并签发 verification token。Bridge 和平台测试固定 bearer / Anthropic
  header 装配、credential unavailable、connection failure、headers-only、redirect 禁止和显式 performer 注入；Core
  不再读取 Keychain、不再启动 shell/curl/TCP probe，也不再接受进程级 probe runtime 环境路径。
- 平台能力 inventory 已覆盖 `FileManager` 默认实例、`FileHandle`、`URL.resourceValues`、Data 读写、
  脚本写入与环境变量访问；后续新增同类 feature 例外会直接触发治理测试。

AI runtime environment contract 当前由 Core 的 7 个 `AREAMATRIX_*_RUNTIME` key 与治理检查共同固定：
classification、tags、summary 的 local / remote runtime，以及 semantic search 的 remote runtime
由外部集成提供；remote provider probe 已退出 runtime 环境合同。Core 新增或重命名 runtime key 时，
`./dev check governance` 必须失败，不能让跨 Rust / Swift 的环境变量合同静默漂移。

## 架构演进规则

- Feature owner、职责、风险边界和验证重点由 `MacOSFeatureOwnershipGovernanceTests` 维护。
- 受控迁移区的文件、owner 和退出条件由 `MacOSMigrationZoneGovernanceTests` 维护。
- 触达平台副作用时收敛到 `PlatformServices/`，或在治理测试中保留明确的风险归属与退出条件。
- 共享 state、action、routing 或 validation 支撑至少应有两个真实调用方，不按迁移排期预先抽象。

## 文件规模治理

- 手写 Swift 文件达到 450 行后进入 `SwiftFileSizeGovernanceTests` 精确清单，必须记录 owner、继续保留的理由和下一次增长前的拆分触发条件。
- `SwiftFileSizeGovernanceTests` 是近阈值文件、行数上界和拆分触发条件的可执行 inventory；长期文档不重复具体文件名或行数。
- 已进入清单的文件不能超过登记上界，优先按完整职责族拆分，而不是拆散同一语义。
- 500 行是手写 Swift 文件硬上限。`Bridge/Generated/` 与 `Bridge/UniFFI/` 的 UniFFI 生成绑定不适用手写文件阈值，但由生成产物与 bindings drift 门禁单独约束。

## 不做

- 不以目录整理为由进行缺少独立计划、风险说明和验证的大规模文件搬迁。
- 不为了目录漂亮改 UI 行为。
- 不把所有状态塞进单个巨大 store。
- 不在本治理中修改 Core API / UDL，除非发现明确漂移并单独评审。
- 不新增依赖，除非完成用途、许可证、替代方案和供应链风险评审。
- 不把 FileManager / iCloud / watcher 副作用藏进 SwiftUI View。

## 验证

macOS 代码改动后按范围运行：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
./dev test macos
```

只改文档时可不跑 macOS build，但需要说明未运行原因。涉及 docs / skills / governance / prompts 时按对应治理门禁补充检查。

## Related

- [layered-design.md](layered-design.md)
- [ffi-design.md](ffi-design.md)
- [fs-watcher.md](fs-watcher.md)
- [../api/uniffi-recipes.md](../api/uniffi-recipes.md)
