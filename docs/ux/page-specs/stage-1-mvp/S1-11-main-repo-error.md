# S1-11 main-repo-error - 主窗口资料库错误

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-11
> 页面类型：主窗口
> 页面文件：`S1-11-main-repo-error.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口错误态。
- **建议目录**：`apps/macos/AreaMatrix/Features/Library/RepositoryErrorView.swift`。
- **建议组件**：`RepositoryErrorView`、`RepositoryRecoveryActions`、`DiagnosticsExportButton`。
- **实现说明**：这是 repo 打开或刷新失败时的主窗口错误页，不负责具体错误修复执行，只提供恢复路径。

## 页面背景

用户已经选择过资料库，但打开主窗口时 repo 可能不可用：路径不存在、权限丢失、数据库损坏、schema 不兼容、iCloud 占位符未下载、磁盘空间不足等。主窗口不能只显示技术异常，要保留用户信心并给出下一步。

入口：App 启动恢复 repo 发生 critical 错误、主窗口刷新 repo 发生 critical 错误、文件监听回流发现 repo 不一致且无法局部恢复。
退出：恢复成功回到正常列表；选择其他资料库；导出诊断；DB corrupted 进入 `S1-37 db-repair-confirm`。

## 页面功能

- 显示可读错误标题和简短说明。
- 显示当前 repo 路径。
- 显示错误类型和最近一次成功打开时间。
- 提供针对错误的主恢复动作。
- 提供选择其他资料库和导出诊断。
- 避免用户误以为文件已被删除。

## 布局与内容

主窗口内容区显示错误面板，sidebar 可以保留但禁用列表选择。

标题示例：
- `Repository could not be opened`
- `Folder is missing`
- `iCloud file is not downloaded`
- `Repository metadata needs repair`

路径区：
- `Repository: ~/Documents/AreaMatrix`
- `Last opened: Apr 29, 2026 11:30`

说明文案：
- 路径缺失：`AreaMatrix cannot find this folder. It may have been moved, renamed, or disconnected.`
- 权限：`AreaMatrix no longer has permission to read this folder.`
- 数据库损坏：`The repository metadata needs repair. Your files remain in the folder.`

操作按钮：
- 主按钮随错误变化：`Retry`、`Reconnect folder`、`Download and retry`、`Open repair`。
- 次按钮：`Choose another repository`
- 辅助按钮：`Export diagnostics`
- 链接：`Reveal last known folder`，路径存在时显示。

## 状态与规则

- 默认状态：根据 Core error 选择一个主恢复动作；技术详情折叠。
- 错误页不得自动删除 repo 配置。
- 错误页不得移动、重命名或删除用户文件。
- DB locked 不进入本整页错误态；应由 `S1-32 error-recovery` 的 inline error 在 List/Detail 中呈现，并保持 Tree 可用。
- 数据库损坏时引导到 `S1-37 db-repair-confirm`，说明用户文件仍在文件夹中。
- iCloud 占位符错误提供下载重试，不建议用户立即重建 repo。
- 导出诊断必须说明不包含用户文件内容。
- 禁用条件：恢复动作执行中禁用重复点击；错误类型不支持的动作不显示。
- 空态不适用：repo error 页必须展示错误摘要、repo path 和至少一个恢复动作或诊断入口。
- 加载态：Retry / Download & retry / Export diagnostics 执行中显示进行中文案，保留 Cancel 或 Close。

## 交互

1. 打开错误页时根据 Core error 映射标题、说明和主动作。
2. 点击 `Retry` 重新打开 repo，按钮显示 `Retrying...`。
3. 点击 `Reconnect folder` 打开路径选择器，并校验是否同一 repo。
4. 点击 `Choose another repository` 回到选择路径流程。
5. 点击 `Export diagnostics` 生成本地诊断包；确认文案必须说明不包含用户文件内容、不自动上传、路径和用户名会脱敏。
6. 恢复成功后清除错误状态，回到 `S1-09 main-list`。
7. DB corrupted 的 `Open repair` 打开 `S1-37 db-repair-confirm`，不在本页直接修复。

## 可访问性

- 错误标题、用户可读说明和技术详情需要分层。
- 技术详情默认折叠，但可通过键盘展开和复制。
- 恢复按钮的禁用原因需要文本说明；critical 状态不能只靠红色表达。

## 数据与依赖

- Core repo open error。
- Last known repo path and last successful open time。
- Recovery route mapping。
- iCloud placeholder handler。
- Diagnostics export。
- File reveal platform service。

## 验收清单

- 路径缺失、权限、iCloud 占位符、schema 不兼容、数据库损坏都有不同文案和动作。
- 页面明确说明错误不代表用户文件已丢失。
- Retry 执行中有进度状态且防重复点击。
- 选择其他资料库不会删除当前 repo 配置，除非用户后续确认。
- 诊断导出不包含用户文件内容。
- VoiceOver 能读出错误标题、路径和主恢复动作。
- DB locked 场景不会进入本页，而是在主窗口局部错误中可 Retry。

## 来源

- `docs/ux/ui-states.md#全局状态机repo-级`（直接）。
- `docs/ux/error-messages.md#2-coreerrordb数据库错误`（组合）。
- `docs/ux/first-launch.md` 的错误恢复原则（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-10 main-loading](S1-10-main-loading.md)
- [S1-32 error-recovery](S1-32-error-recovery.md)
- [S1-37 db-repair-confirm](S1-37-db-repair-confirm.md)
