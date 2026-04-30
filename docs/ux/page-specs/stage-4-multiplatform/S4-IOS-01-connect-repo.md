# S4-IOS-01 connect-repo - 首次连接资料库

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-01
> 页面类型：iOS onboarding page  
> 页面文件：`S4-IOS-01-connect-repo.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS 移动端。
- **建议目录**：`apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift`。
- **建议组件**：`ConnectRepositoryView`、`RepositoryAccessService`、`ICloudAvailabilityViewModel`。
- **实现边界**：这是 iOS 首次启动的资料库连接页，不实现 macOS 的三栏主窗口，也不在本页做文件导入。

## 页面背景

用户第一次打开 iOS 版 AreaMatrix，需要连接一个已有 AreaMatrix 资料库。Stage 4 的 iOS 目标是与 macOS 共用同一 iCloud 仓库模型，因此本页优先引导用户从 iCloud Drive 中选择已有资料库。

入口：iOS app 首次启动、用户登出当前资料库后重新连接、资料库访问权限失效后重新选择。  
退出：连接成功进入 `S4-IOS-02 mobile-library`；权限不可用进入 `S4-IOS-06 icloud-permission`；空目录进入 `S4-X-04 repository-init-confirm`；非空普通目录进入 `S4-X-05 repository-adopt-confirm`；用户取消则停留在未连接状态。

## 页面功能

- 说明“资料库是一个普通文件夹”，避免用户误以为需要登录服务账号。
- 提供连接 iCloud Drive 资料库的主操作。
- 提供通过系统文件选择器选择其他可访问文件夹的次操作。
- 显示最近连接过的资料库，前提是 iOS 仍有 security scoped 访问凭证。
- 校验所选目录是否包含 `.areamatrix/`，并区分“已有资料库”“空目录”“非空普通目录”。
- 在任何写入发生前，让用户看见将要连接或初始化的路径。

## 布局与内容

整体使用 iOS SwiftUI 原生导航风格，不照搬 macOS 首次启动向导。页面背景使用系统 grouped 背景，内容按卡片分组，但不要做营销式大图。

导航栏：
- 标题：`Connect Repository`
- 右上角可选按钮：`Help`，打开资料库说明。

顶部说明区：
- 主标题：`连接 AreaMatrix 资料库`
- 说明：`选择一个已有的 AreaMatrix 文件夹。AreaMatrix 不会在你确认前移动、删除或覆盖文件。`
- 辅助说明：`推荐使用 iCloud Drive，这样可以和 Mac 共用同一个资料库。`

主操作区：
- 主按钮：`Connect iCloud Repository`
- 按钮图标：使用系统 `icloud` 或文件夹图标。
- 按钮下方短说明：`从 iCloud Drive 中选择包含 .areamatrix 的文件夹。`

次操作区：
- 按钮：`Choose Folder...`
- 说明：`选择 Files app 中可访问的位置。某些第三方云盘可能只提供临时访问。`

最近资料库区：
- 标题：`Recent Repositories`
- 每一行显示：资料库名称、路径简写、上次打开时间、权限状态。
- 权限失效的行显示 `Access expired`，右侧操作为 `Reconnect`。
- 没有最近资料库时隐藏整个列表，不显示空白卡。

底部安全说明：
- 文案：`连接前只读取目录结构；初始化或接管目录会在下一步单独确认。`
- 使用普通 secondary 文本，不使用红色。

## 状态与规则

- 默认状态：未连接 repo 时显示主操作、次操作和最近资料库；没有最近资料库时隐藏最近资料库区。
- 空态：没有最近资料库且尚未选择路径时，不显示空列表，只保留连接说明和两个选择入口。
- 加载态：系统 picker 返回路径后显示 `Checking...`，连接按钮和最近资料库行临时禁用，避免重复校验。
- 错误态：路径不可访问、权限不足、版本不兼容或选择单个文件时，在对应入口下方显示可读错误并保留重新选择路径。
- iCloud 不可用：主按钮仍可见但进入 `S4-IOS-06 icloud-permission`，不要直接禁用到无法恢复。
- 用户选择已有 repo：显示路径校验通过，自动进入移动端资料库浏览。
- 用户选择空目录：进入 `S4-X-04 repository-init-confirm`；本页只负责选择，不创建 `.areamatrix/`。
- 用户选择非空普通目录：必须进入 `S4-X-05 repository-adopt-confirm`，不允许静默写入。
- 用户选择单个文件：显示轻量错误 `请选择资料库文件夹，而不是单个文件。`
- 访问凭证失效：最近列表行保留，但标记需要重新授权。
- 路径在第三方云盘：显示黄色提示，说明同步行为由云盘决定。

## 交互

1. 点击 `Connect iCloud Repository` 打开系统 document picker，默认定位到 iCloud Drive 可用位置。
2. 选择目录后先执行只读校验：是否可访问、是否可写、是否包含 `.areamatrix/`、是否处于 iCloud 占位状态。
3. 校验中在按钮内显示 spinner，并将按钮文案改为 `Checking...`。
4. 校验通过且是已有资料库，保存 security scoped bookmark，进入 `mobile-library`。
5. 校验结果需要用户确认时，空目录跳转 `S4-X-04`，非空目录跳转 `S4-X-05`，不在本页弹复杂对话框。
6. 用户取消系统选择器后回到本页，最近列表和按钮状态不变化。

## 数据与依赖

- iOS `UIDocumentPickerViewController` 或 SwiftUI 文件导入封装。
- security scoped bookmark 保存与恢复。
- iCloud availability 检测。
- Core repo detection：只读检查 `.areamatrix/`、版本、可写性。
- 错误模型需映射到 `PermissionDenied`、`ICloudUnavailable`、`InvalidRepository`、`AccessExpired`。

## 验收清单

- 首次启动能看到连接 iCloud、选择文件夹、最近资料库三类入口。
- 选择已有 AreaMatrix 资料库后进入移动端浏览页。
- 选择空目录或非空普通目录时不会直接写入，会进入 `S4-X-04` 或 `S4-X-05`。
- iCloud 不可用时能进入权限提示页，而不是让用户卡死。
- 最近资料库权限失效时有明确 `Reconnect` 操作。
- 页面所有按钮支持 VoiceOver，且主说明能读出“不会移动、删除或覆盖文件”。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/roadmap/milestones.md` 的 Stage 4 iOS 目标。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-22-s4-ios-01-connect-repo.md`。
- 组合来源：`docs/adr/0006-icloud-support.md`、`docs/ux/first-launch.md`。
- 推导说明：目录初始化和接管跳转依据 Stage 1 首次启动安全流程推导为多端共用确认页。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [空目录初始化确认](S4-X-04-repository-init-confirm.md)
- [非空目录接管确认](S4-X-05-repository-adopt-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
