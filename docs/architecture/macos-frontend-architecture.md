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

每个 feature 可以按需要包含：

- `Views`
- `Model` / `State`
- `Actions`
- `Routing`
- `Support`
- feature-local tests support

只有当组件跨多个 feature 复用且不携带业务语义时，才放入 `Views/DesignSystem/` 或共享 support。

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

## 渐进迁移顺序

1. 规则与路线图先固定：`apps/macos/AGENTS.md`、本文和
   `docs/roadmap/engineering-maturity-roadmap.md` 保持一致。
2. 已起步 feature 持续样板化：MainList、FileActions、Search、CommandPalette、
   SyncConflicts、AI、Import。
3. 下一批优先治理高风险或高膨胀 owner：Settings、Onboarding。
4. 触达平台副作用时收敛到 `PlatformServices/` 或保留明确退出条件。
5. 当多个 feature 跑通同一种 state / action / routing / validation 模式后，再抽共享支撑。

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
