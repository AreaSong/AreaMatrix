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

受控例外必须明确：例如短期存在的 SQLite metadata reader，应记录原因、风险和退出条件。

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
| DB repair 与 recovery | `Features/Onboarding/DatabaseRepairConfirmModel.swift`、`DatabaseRepairConfirmView.swift` | metadata repair、startup recovery 和 diagnostics 关系到 DB、`.areamatrix/` 与恢复语义 | repair、recovery、diagnostics 的默认能力分别声明；收口不改变确认、重试、诊断隐私门槛 | `DatabaseRepairConfirmPageFeatureTests`、startup recovery tests、DB / recovery file-safety evidence |
| AI 隐私与远程 provider | `Features/AI/AIPrivacyRulesModel.swift`、`RemoteProviderConfigModel.swift`、`RemoteProviderConfigState.swift` | 隐私规则写入、provider 启停、credential lifecycle 和远程能力涉及用户数据离开本机的边界 | 只读状态读取可集中；隐私规则写入、provider 修改、credential 操作保持单独边界和同意路径 | `AIPrivacyRulesPageIntegrationVerifyTests`、`RemoteProviderConfigFeatureTests`、credential lifecycle tests |
| Sync / iCloud conflict | `Features/SyncConflicts/ICloudConflictMinimalValidation.swift`、`SyncConflictReviewModel.swift` | conflict detect / preview / resolve / apply 可能影响外部变化回流、iCloud 副本和用户文件选择 | list / read-only 状态可集中；preview、resolve、apply 继续分离，并保留 replace / confirmation 防线 | SyncConflict / ICloudConflict page tests、replace confirmation tests、file-action integration tests |

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
- `PlatformServices/RemoteProviderProbeRuntime.swift` 涉及 app-owned runtime 文件、权限、全局环境变量、Keychain 读取、
  网络请求以及 Rust Core `Command` 执行。当前 installer 使用共享 actor 做 single-flight 装配，runtime descriptor 固定
  版本、内容 hash、owner / mode、device / inode，并拒绝任意外部环境路径、弱权限和 symlink；shell runtime 限制
  provider / method / URL，拒绝控制字符 credential，并通过 curl header stdin 传递凭据，避免 curl config 文本注入和
  credential 出现在进程参数中。`RemoteProviderProbeRuntimeInstallerTests` 固定异常内容修复、缓存 descriptor 重校验、
  symlink 替换保护和 CoreBridge 显式 installer 注入。该能力仍是独立高风险安全边界，不能通过单纯移动到
  `PlatformServices/` 宣称完全收口；本地 HTTP fallback 已有响应上限、完整 framing 和网络失败矩阵证据，
  剩余退出条件包括把 descriptor 绑定到 Core 的原子执行句柄，并补足 credential 生命周期证据。
- 平台能力 inventory 已覆盖 `FileManager` 默认实例、`FileHandle`、`URL.resourceValues`、Data 读写、
  脚本写入与环境变量访问；后续新增同类 feature 例外会直接触发治理测试。

AI runtime environment contract 当前由 Core 的 7 个 `AREAMATRIX_*_RUNTIME` key 与治理检查共同固定：
classification、tags、summary 的 local / remote runtime 由外部集成提供；
`AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME` 由 macOS 安装器受控提供。Core 新增或重命名 runtime key、
或 macOS 引用未登记 key 时，`./dev check governance` 必须失败，不能让跨 Rust / Swift 的环境变量合同静默漂移。

## 渐进迁移顺序

1. 规则与路线图先固定：`apps/macos/AGENTS.md`、本文和
   `docs/roadmap/engineering-maturity-roadmap.md` 保持一致。
2. 已起步 feature 持续样板化：MainList、FileActions、Search、CommandPalette、
   SyncConflicts、AI、Import。
3. 下一批优先治理高风险或高膨胀 owner：Settings、Onboarding。
4. 触达平台副作用时收敛到 `PlatformServices/` 或保留明确退出条件。
5. 当多个 feature 跑通同一种 state / action / routing / validation 模式后，再抽共享支撑。

## 文件规模治理

- 手写 Swift 文件达到 450 行后进入 `SwiftFileSizeGovernanceTests` 精确清单，必须记录 owner、继续保留的理由和下一次增长前的拆分触发条件。
- 清单记录当前行数上界；已进入清单的文件不能继续增长，优先按完整职责族拆分，而不是拆散同一语义。
- 500 行是手写 Swift 文件硬上限。`Bridge/Generated/` 与 `Bridge/UniFFI/` 的 UniFFI 生成绑定不适用手写文件阈值，但由生成产物与 bindings drift 门禁单独约束。
- 当前 450 行近阈值清单只登记 459 行的 `MacOSArchitectureBoundaryGovernanceTests.swift`，并冻结其继续增长；
  `RepoConfigSnapshot` fixture family 与 Local File URL platform adapter family 已分别按完整职责迁出，
  架构治理测试的共享扫描能力也已提取到 `MacOSGovernanceFileSystemTestSupport.swift`。下一次扩展
  architecture governance 扫描前，必须继续提取独立扫描族或 shared assertion helper。

## 不做

- 不一次性移动 200+ Swift 文件。
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

## 相关文档

- [layered-design.md](layered-design.md)
- [ffi-design.md](ffi-design.md)
- [fs-watcher.md](fs-watcher.md)
- [../api/uniffi-recipes.md](../api/uniffi-recipes.md)
