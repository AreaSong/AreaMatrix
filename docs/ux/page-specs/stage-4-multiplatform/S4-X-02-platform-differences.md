# S4-X-02 platform-differences - 平台能力差异说明

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-02
> 页面类型：多端共用  
> 页面文件：`S4-X-02-platform-differences.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用帮助/设置页，各平台原生呈现。
- **建议目录**：`apps/*/AreaMatrix/Features/Help/PlatformDifferencesView.*`。
- **建议组件**：`PlatformDifferencesView`、`CapabilityMatrixView`、`PlatformStatusRow`。
- **实现边界**：这是平台能力说明页，不是营销页，也不承诺当前平台尚未实现的能力。

## 页面背景

AreaMatrix Stage 4 会复用同一个 Rust core，但平台层能力不同：文件选择、权限、云盘、监听、回收站、分享入口和移动端沙盒都不一样。用户需要能理解为什么某些按钮在当前平台不可用，开发者也需要一张稳定的 UI 能力矩阵。

入口：设置页 `About` 或 `Help`、权限错误页、导入流程中功能不可用说明、同步冲突页。  
退出：关闭说明；点击 `Open repository settings` 进入 `S4-X-08 repository-settings`；点击相关错误入口返回来源页。

## 页面功能

- 展示当前平台名称和 repo 存储位置。
- 展示能力矩阵：Repository access、File import、File watcher、Cloud provider、Trash/Recycle Bin、Share integration、Camera import。
- 对不可用能力给出原因和替代操作。
- 对部分支持能力显示条件，例如 “Only for local folders”。
- 提供平台相关帮助入口。
- 不把未来路线图能力显示为当前可用。

## 布局与内容

页面可以是设置页中的一个 section，也可以是帮助页。不要用营销 hero。

标题：`Platform capabilities`

顶部摘要：
- `Platform: Windows`、`iOS`、`Linux`
- `Repository: iCloud Drive / OneDrive / Local folder / Unknown`
- `Core version: ...`

能力矩阵：
- `Repository access`
  - iOS：Files app + security scoped access。
  - Windows：Folder picker + ACL。
  - Linux：Local folder + POSIX permissions。
- `File watcher`
  - iOS：受沙盒和后台限制，可能使用打开时扫描。
  - Windows：ReadDirectoryChangesW。
  - Linux：inotify。
- `Cloud provider`
  - iOS：iCloud Drive。
  - Windows：OneDrive 提示，不管理同步。
  - Linux：默认本地目录，第三方同步只做风险提示。
- `Trash / Recycle Bin`
  - Windows：Recycle Bin 可用性检测。
  - Linux：freedesktop Trash 可用性检测。
  - iOS：不保证有等价回收站。
- `Import sources`
  - iOS：Files、Camera、Share Sheet。
  - Windows/Linux：file picker、folder picker、drag and drop。

行状态：
- `Available`
- `Limited`
- `Not available`
- `Unknown`

底部操作：
- `Open repository settings`
- `Export diagnostics`
- `Close`

## 状态与规则

- 能力未知时显示 `Unknown`，不显示成可用。
- 不可用能力必须有原因，例如 `Not available on iOS because folders are sandboxed.`
- Limited 状态必须说明限制条件。
- 加载态：读取 capability snapshot 时显示 `Checking platform capabilities...`。
- 错误态：capability snapshot 检测失败、repo 位置分类失败或诊断服务不可用时，对应行显示 `Unknown` 或禁用状态，并展开失败原因。
- 检测失败：对应行显示 `Unknown`，展开后显示失败原因和 `Export diagnostics`。
- 远程云盘状态不可准确检测时，不显示精确同步进度。
- 本页只说明能力，不直接执行危险操作。
- 能力矩阵不替代真实权限检测和操作前 preflight；导入、Replace、rescan、重新连接等操作仍必须在来源流程重新校验。
- 未连接 repo：顶部摘要显示 `Repository: Not connected`；`Open repository settings` 仍可进入 `S4-X-08 repository-settings` 的未连接空态。
- Diagnostics 不可用：`Export diagnostics` 禁用并显示 `Diagnostics are not available on this platform yet.`，不得生成空白诊断包。
- Capability snapshot 加载失败：保留 `Close` 可用，`Open repository settings` 可用，能力行显示 `Unknown` 并展示失败原因；`Export diagnostics` 只有诊断服务可用时启用。
- 禁用条件：诊断服务不可用时禁用 `Export diagnostics`；当前平台无法打开设置时禁用 `Open repository settings` 并说明原因；加载中只禁用依赖 snapshot 的展开动作。
- 不展示 Stage 5 或未定义能力。

## 交互

1. 打开页面时读取当前平台、repo path、Core version 和平台 capability snapshot。
2. 点击某个能力行展开说明和替代操作。
3. 点击 `Open repository settings` 进入 `S4-X-08 repository-settings`。
4. 点击 `Export diagnostics` 生成平台能力诊断，不包含用户文件内容。
5. 错误页跳转过来时，可自动展开相关能力行，例如 Trash 不可用或 watcher 不可用。
6. 如果能力行显示 `Unknown`，用户点击替代操作时仍回到对应真实流程做 preflight，而不是直接执行。

## 数据与依赖

- Platform capability provider。
- Repo location classification。
- Core version/build info。
- Watcher backend status。
- Trash/Recycle Bin availability。
- Cloud provider detection，允许 best effort。

## 验收清单

- iOS、Windows、Linux 至少分别有一份能力矩阵内容。
- `Available`、`Limited`、`Not available`、`Unknown` 都有清楚视觉和文字说明。
- 页面能解释为什么某个平台没有某个按钮。
- 不把尚未实现能力显示成可用。
- 未连接 repo、capability snapshot 失败和 diagnostics 不可用都有明确按钮状态。
- 页面明确提示能力矩阵不能替代实际操作前校验。
- 诊断导出明确不包含用户文件内容。
- 屏幕阅读器能按行读取能力名、状态和说明。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/roadmap/milestones.md` Stage 4 多端扩展。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-40-s4-x-02-platform-differences.md`。
- 组合来源：`docs/adr/0001-tech-stack.md`、`docs/adr/0005-fsevents-listener.md`、`docs/adr/0006-icloud-support.md`。
- 推导说明：平台能力矩阵用于解释按钮可用性，不展示 Android、企业协作、插件市场、账号体系或未定义能力。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [多端资料库设置](S4-X-08-repository-settings.md)
- [iCloud 权限提示](S4-IOS-06-icloud-permission.md)
- [Windows 文件监听状态](S4-WIN-04-watcher-status.md)
- [Linux 文件监听状态](S4-LNX-04-watcher-status.md)
- [逐页 UI 开发规格索引](../README.md)
