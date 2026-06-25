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
- `Features/<FeatureName>/`：按业务域收拢 View / Model / State / Actions / Support。候选 feature 包括 `MainList`、`Import`、`Settings`、`Onboarding`、`AI`、`Search`、`SyncConflicts`、`FileActions`。
- `Models/`：尚未收拢到 feature 的 UI state、presentation state、routing state 和轻量 view model。新增复杂 model 优先放到对应 `Features/<FeatureName>/`，不要继续扩大顶层 `Models/`。
- `Views/`：现有跨 feature 的 SwiftUI 入口和渐进迁移区。新增业务视图优先放入 `Features/<FeatureName>/`；`Views/DesignSystem/` 只放通用 UI 组件、主题、效果和可复用控件。
- `Resources/`：静态资源。
- `AreaMatrixTests/Support` 或 feature-local test support：后续新增 fixture、mock bridge、临时 repo 构造、重复断言 helper 优先收敛到明确支撑目录；不要继续散落成大号测试工具文件。

## 渐进治理

- 新功能先判断 feature owner，再写代码；没有 owner 时先补规则或创建 feature 目录。
- 触达旧文件时只做与当前需求相关的归位，不为了目录完整一次性搬迁全仓库。
- 文件拆分按职责边界，不按行数凑数字；超过或接近 500 行时优先寻找 route、state、action、platform adapter、support 的自然边界。
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

## 高风险约束

- 不移动、删除、覆盖或重命名用户原文件。
- 不在本目录实现 FSEvents、iCloud、导入、接管或真实 Core 写操作，除非任务明确要求。
- 不用 mock 或静态数据伪装真实闭环验收通过。

## 验证

macOS 改动后优先运行：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
./dev test macos
```

`./dev test macos` 会先执行标准 `xcodebuild test`；只有明确遇到
本地 `testmanagerd` sandbox 通信限制时，才用 `xcrun xctest` 执行同一 XCTest
bundle。普通编译、链接或断言失败仍然算失败。
