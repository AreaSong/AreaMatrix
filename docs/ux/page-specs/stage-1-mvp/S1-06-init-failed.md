# S1-06 init-failed - 初始化失败

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-06
> 页面类型：首次启动
> 页面文件：`S1-06-init-failed.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/`
- **建议组件**：`InitFailedStepView`、`DiagnosticsExportButton`
- **实现说明**：失败页负责恢复入口，不执行隐式修复；诊断导出需要脱敏。

## 页面背景

初始化或接管未完成。用户需要知道原始文件是安全的，并能选择重试、换路径、导出诊断或退出。

入口：`S1-05 initializing` fatal error；用户在 `S1-05` Cancel 后下次启动检测到 interrupted / staging recovery；App 启动时发现上次初始化未完成。
退出：Retry 回到 `S1-05 initializing`；Change Path 回到 `S1-02 choose-path`；Collect Diagnostics 留在本页；Quit 退出并保留可恢复状态。

## 页面功能

- 显示失败摘要和错误代码。
- 明确说明原始文件未被移动、重命名、删除或覆盖。
- 给出恢复建议。
- 提供诊断导出。

## 布局与内容

标题：`初始化未完成`

主说明：

```text
AreaMatrix 没能完成资料库初始化。你的原始文件没有被移动、重命名、删除或覆盖。
```

错误摘要卡：

- 发生了什么，例如 `无法写入 .areamatrix/index.db`。
- 路径：repoPath。
- 错误代码：如 `PermissionDenied`、`StorageInitFailed`。
- `Show details` disclosure 展开技术信息。

恢复建议卡：

- 检查文件夹是否可写。
- 更换资料库位置。
- 释放磁盘空间后重试。
- iCloud 路径等待同步后重试。

底部按钮：`Change Path`、`Retry`、`Collect Diagnostics...`、`Quit`。

## 状态与规则

- 默认状态：`Retry` 为主按钮，技术详情折叠。
- 有 staging 残留时显示：`检测到上次未完成的临时状态。AreaMatrix 可以在重试时自动清理或继续恢复。`
- Retry / Change Path / Collect Diagnostics 执行中禁用重复点击，并显示进行中文案。
- `Collect Diagnostics...` 不改变 repo 内容，不包含用户文件内容，不自动上传，路径和用户名会脱敏。
- 空态不适用：本页必须有错误摘要或 interrupted recovery 摘要；缺失摘要时显示 `Unknown initialization error` 和诊断入口。
- 加载态：读取 recovery 状态时显示 `Checking previous setup state...`，禁用 Retry / Change Path，保留 Quit。
- 错误态：recovery 状态读取失败时仍显示本页，提供 Change Path、Collect Diagnostics 和 Quit，不自动删除 `.areamatrix/`。

## 交互

- `Retry` 回到 `S1-05 initializing`。
- `Change Path` 回到 `S1-02 choose-path`。
- `Collect Diagnostics...` 弹出隐私说明后导出本地诊断包。
- `Quit` 退出，下次启动继续向导或恢复。

## 可访问性

- 错误摘要、错误代码和恢复建议需要分区标题。
- `Show details` 默认折叠，但必须可通过键盘展开。
- Retry / Change Path / Diagnostics / Quit 的焦点顺序必须稳定；错误严重程度不能只靠颜色表达。

## 数据与依赖

- CoreError 映射。
- staging recovery 状态。
- 本地日志和诊断包收集。

## 验收清单

- 失败页必须说明用户原文件安全。
- Retry / Change Path / Diagnostics 都可用。
- 技术详情默认折叠。
- 诊断导出不包含用户文件内容。

## 来源

- `docs/ux/first-launch.md#6-initfailed初始化失败`（直接）。
- `docs/ux/error-messages.md`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-02 choose-path](S1-02-choose-path.md)
- [S1-05 initializing](S1-05-initializing.md)
