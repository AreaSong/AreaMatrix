# AreaMatrix macOS Agent Guide

## 定位

- 本目录是 AreaMatrix 的 SwiftUI macOS 原生应用。
- macOS 层负责 UI、平台适配、CoreBridge、watcher 和系统能力封装。
- macOS app 已进入实现态；继续遵守 SwiftUI / CoreBridge / 平台能力分层，不用 mock 或静态数据伪装真实闭环。
- 新增功能默认按 feature 边界落位；目录好看不是目标，目标是后续功能高效复用、可测试、可维护。

## 目录落点

- `App/`：应用入口、菜单、生命周期、依赖装配，以及全局服务启动。不要把 feature 业务状态继续堆进 App。
- `Bridge/`：`CoreBridge`、Core 调用封装、snapshot / DTO 转换、`CoreError` 映射，以及 Swift 调用 Rust Core 的唯一手写入口。
- `Bridge/Generated/` 与 `Bridge/UniFFI/`：只放 UniFFI 生成绑定；不得手写业务逻辑。
- `PlatformServices/` 或现有 `App/` 平台服务文件：AppKit、FileManager、iCloud、FSEvents、NSOpenPanel、NSSavePanel、NSWorkspace、Pasteboard、系统能力检测等平台副作用。新增平台能力优先进入 `PlatformServices/`；既有 `App/` 平台服务可随触达渐进迁移。
- `Features/<FeatureName>/`：按业务域收拢 View / Model / State / Actions / Support。当前 owner 包括 `AI`、`CommandPalette`、`Detail`、`FileActions`、`Import`、`MainList`、`Onboarding`、`RepositoryLifecycle`、`Search`、`Settings`、`SyncConflicts`。
- `Models/`：尚未收拢到 feature 的 UI state、presentation state、routing state 和轻量 view model。新增复杂 model 优先放到对应 `Features/<FeatureName>/`，不要继续扩大顶层 `Models/`。
- `Views/`：现有跨 feature 的 SwiftUI 入口和渐进迁移区。新增业务视图优先放入 `Features/<FeatureName>/`；`Views/DesignSystem/` 只放通用 UI 组件、主题、效果和可复用控件。新增 DesignSystem / Effects Swift 文件时必须同步写入 `AreaMatrix.xcodeproj` 的 PBXFileReference、对应 Group 与 Sources（缺任一环会出现「找不到类型」却难定位到工程登记）。
- `Resources/`：静态资源。
- `AreaMatrixTests/Support` 或 feature-local test support：后续新增 fixture、mock bridge、临时 repo 构造、重复断言 helper 优先收敛到明确支撑目录；不要继续散落成大号测试工具文件。

## 默认依赖装配

- 新增 macOS 默认 Core 服务优先集中到 `App/AppCoreServices.swift`，feature model / view
  通过协议注入接收默认能力；测试继续显式注入 test double。
- 跨 feature content shell 的生产装配由 `App/` 层的轻量 assembly / factory 负责；SwiftUI View
  initializer 只接收显式装配结果，不直接解析 `AppCoreServices` 或 `AppPlatformServices` 默认值。
- `@StateObject` identity 继续由对应 SwiftUI View 持有；assembly 只提供构造闭包，不持有全局 model
  单例，也不改变现有 CoreBridge 实例生命周期。
- Remote provider probe 由共享的 `RemoteProviderProbeService` actor 执行；CoreBridge 先从 Core 获取
  非 secret 的 probe plan，再由平台层使用 Keychain 与受限 URLSession 执行，并只把净化 observation
  回传 Core。不得恢复 shell runtime、进程级环境路径或让 Core 读取 Keychain / 发起网络请求。
- 初始化、导入、DB 修复、同步冲突、iCloud conflict、AI 隐私 / 远程 provider
  等高风险专项路径允许受控保留直接 `CoreBridge()` 默认构造。
- 保留的直接 `CoreBridge()` 默认构造必须有治理测试登记；新增或删除登记项时，要说明风险归属和收口条件。
- 不要为了集中化把高风险写操作伪装成通用服务；先保持边界可见，再按专项收口。

## 渐进治理

- 新功能先判断 feature owner，再写代码；没有 owner 时先补规则或创建 feature 目录。
- `MacOSFeatureOwnershipGovernanceTests` 精确登记每个 Feature 目录的职责、风险边界和验证重点；新增 Feature 目录必须先补 owner inventory。
- 触达旧文件时只做与当前需求相关的归位，不为了目录完整一次性搬迁全仓库。
- 顶层 `Models/`、根 `Views/`、`Views/Main/`、`Views/Onboarding/` 与 `Views/Settings/` 是受控迁移区；
  `MacOSMigrationZoneGovernanceTests` 精确登记当前保留文件、owner 和退出条件。新增业务文件不得进入这些区域。
- 文件拆分按职责边界，不按行数凑数字；超过或接近 500 行时优先寻找 route、state、action、platform adapter、support 的自然边界。
- 手写 Swift 文件达到 450 行后必须进入 `SwiftFileSizeGovernanceTests` 精确清单，登记 owner、保留理由和拆分触发条件；清单文件不得继续增长，500 行仍是硬上限。UniFFI 生成绑定单独治理。
- 只有一个实现、一个调用点、一个场景时，谨慎引入协议、工厂、策略等额外层次。
- 大规模目录迁移必须单独计划、单独验证，不与产品功能混在同一改动里。

## 边界

- SwiftUI 视图只做展示和用户交互，不直接做文件 IO。
- 平台能力放在 Swift 平台层；Core 层仍保持平台无关。新增平台能力不要藏进 SwiftUI View。
- CoreBridge 是 Swift 调用 Core 的唯一入口，后续不得让视图或 feature model 直接调用 UniFFI 生成代码。
- `CoreError`、UniFFI 生成 DTO 和 SQLite 直读只能出现在 Bridge、PlatformServices 或明确记录的受控例外里；UI 层优先消费 App 语义状态。
- `Bridge/Generated/` 是 `.gitignore` 忽略的本地生成产物目录，不手写业务代码。
- `Bridge/UniFFI/` 是当前 Xcode 工程消费的 tracked UniFFI binding，也不要手写业务逻辑；
  UDL 变化后用仓库命令重新生成。

## 本地化

- 新增或修改页面时先列出 application-owned 用户可见文案；按钮、标题、说明、状态、错误、恢复建议、菜单、
  toast 和 accessibility label/value/hint/action/announcement 都必须进入
  `AreaMatrix/Localizations/Localizable.xcstrings`，同时维护 `en` 与 `zh-Hans`。
- 立即使用的普通文本选择 `L10n.string` / `format` / `plural`；需要存入 model、错误、toast 或异步状态的文本
  选择 `L10n.message` / `pluralMessage` / `display`，并在 View 展示边界用 `AppLocalizer.resolve`。
- 用户内容、路径、文件名、品牌和技术标识需要保持原文时使用 `L10n.verbatim` 并写明 `VerbatimReason`；用户可编辑
  默认值只在草稿创建时使用 `L10n.editableDefault`，不得在语言切换后覆盖用户输入。
- L10n key 必须是静态字符串，不得插值或拼接；不得直接构造 `LocalizedMessage`、调用 bundle lookup，或用
  `.id(locale)` 强制重建视图掩盖状态问题。
- SwiftUI 编译器可抽取的字符串仍必须存在于 String Catalog；新代码优先显式使用 L10n API，使即时文本、延迟
  状态和 verbatim 边界可审查。

## 高风险约束

- 不移动、删除、覆盖或重命名用户原文件。
- 不在本目录实现 FSEvents、iCloud、导入、接管或真实 Core 写操作，除非任务明确要求。
- 不用 mock 或静态数据伪装真实闭环验收通过。

## 验证

macOS 改动后优先运行：

```bash
./dev check localization
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
./dev test macos
```

`./dev test macos` 会先执行标准 `xcodebuild test`；只有明确遇到
本地 `testmanagerd` sandbox 通信限制时，才用 `xcrun xctest` 执行同一 XCTest
bundle。普通编译、链接或断言失败仍然算失败。
