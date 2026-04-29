# S4-IOS-06 icloud-permission - iCloud 权限提示

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-06
> 页面类型：iOS recovery page / sheet  
> 页面文件：`S4-IOS-06-icloud-permission.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS 移动端。
- **建议目录**：`apps/ios/AreaMatrix/Features/Onboarding/ICloudPermissionView.swift`。
- **建议组件**：`ICloudPermissionView`、`ICloudStatusViewModel`、`RepositoryReconnectActions`。
- **实现边界**：这是权限和可用性说明页，不实现系统设置修改，也不承诺可以强制修复 iCloud 状态。

## 页面背景

iOS 端依赖 Files app 和 iCloud Drive 访问资料库。用户可能未登录 iCloud、关闭 iCloud Drive、撤销了目录访问权限，或者选择了尚未下载的占位目录。本页需要解释问题并给出可执行恢复路径。

入口：连接资料库时 iCloud 不可用、打开最近 repo 时权限失效、移动端资料库读取 iCloud 占位符失败。  
退出：用户修复后重试；选择其他文件夹；返回连接页。

## 页面功能

- 显示 iCloud 或目录访问的当前问题。
- 解释 AreaMatrix 为什么需要文件夹访问权限。
- 提供重试、打开系统设置、重新选择资料库三个恢复动作。
- 对占位符下载失败提供 `Try again`，不把它当作永久错误。
- 对权限失效提供 `Reconnect Folder`。
- 保持安全承诺：不会因为权限错误而删除 repo 记录或用户文件。

## 布局与内容

整体是 iOS 原生错误恢复页，可以作为 full-screen 页面或 sheet。

顶部：
- 标题按场景变化：`iCloud Drive is not available`、`Repository access expired`、`File is still in iCloud`。
- 图标：使用系统云或文件夹图标，颜色为黄色或系统 secondary，不使用大面积红色。

说明区：
- iCloud 不可用：`AreaMatrix needs access to the folder that contains your repository. Check that iCloud Drive is enabled for Files.`
- 权限失效：`iOS requires you to reconnect this folder before AreaMatrix can read it again.`
- 占位符未下载：`This file exists in iCloud but is not downloaded on this device yet.`

状态详情：
- `Repository: iCloud Drive / AreaMatrix`
- `Last opened: Apr 29, 2026 11:30`
- `Status: Access expired` 或 `Waiting for iCloud download`

操作区：
- 主按钮：`Try Again` 或 `Reconnect Folder`
- 次按钮：`Choose Another Folder`
- 辅助按钮：`Open Settings`
- 取消：`Back`

## 状态与规则

- 默认状态：按最新错误类型展示对应标题、状态详情和恢复动作。
- 空态：没有最近 repo 或无法确定原路径时，隐藏 repo 详情，只显示 `Choose Another Folder` 和连接说明。
- 未登录 iCloud：显示打开设置和选择其他文件夹。
- iCloud Drive 关闭：显示打开设置。
- security scoped bookmark 失效：显示重新连接文件夹。
- 占位符未下载：显示重试，不建议用户切换资料库。
- 网络不可用：说明可以继续浏览已下载文件，只有占位符受影响。
- 加载态：重试或返回 app 后刷新状态时显示 `Checking...`，恢复按钮临时禁用。
- 错误态：状态探测失败显示 `Could not check iCloud status`，保留 `Choose Another Folder`。
- 多次重试失败：提供诊断导出入口，文案避免责怪用户。

## 交互

1. 页面出现时读取最新 iCloud 状态，不使用过期错误文案。
2. 点击 `Try Again` 触发重新获取权限或下载占位符，按钮显示 `Checking...`。
3. 点击 `Reconnect Folder` 打开 document picker，并校验是否是同一 repo。
4. 点击 `Open Settings` 跳转系统设置可达位置；返回 app 后自动刷新状态。
5. 点击 `Choose Another Folder` 回到 `connect-repo`。
6. 如果修复成功，自动回到原先页面，例如资料库或详情。

## 数据与依赖

- iCloud availability detection。
- security scoped bookmark validation。
- iOS settings deep link 能力。
- Core error mapping：`ICloudUnavailable`、`ICloudPlaceholder`、`PermissionDenied`、`AccessExpired`。
- Diagnostic export 可复用 Stage 1 错误恢复能力。

## 验收清单

- 未登录 iCloud、权限失效、占位符未下载三类文案不同。
- 每类错误至少有一个可执行恢复动作。
- 重试成功后能回到原页面，而不是永远回连接页。
- 页面明确说明不会删除或修改用户文件。
- VoiceOver 能读出问题标题、状态和按钮用途。
- 不承诺 AreaMatrix 能替用户开启系统 iCloud 设置。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/adr/0006-icloud-support.md`。
- 组合来源：`docs/ux/error-messages.md`、`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-08-cloud-permission-state.md`。
- 推导说明：iOS Files app、iCloud Drive 与 security scoped access 的恢复动作依据平台能力推导。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [iOS 首次连接资料库](S4-IOS-01-connect-repo.md)
- [移动端资料库浏览](S4-IOS-02-mobile-library.md)
- [逐页 UI 开发规格索引](../README.md)
