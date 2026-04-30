# S1-21 import-result - 导入结果摘要

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-21
> 页面类型：导入
> 页面文件：`S1-21-import-result.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入流程
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/`
- **建议组件**：`ImportResultSheet`、`ImportResultTable`、`ImportErrorDetailView`
- **实现说明**：导入完成后用于解释成功、跳过和失败项；不是必须每次自动弹出，无失败时可用 toast。

## 页面背景

批量导入结束后，用户需要确认哪些文件成功、哪些跳过、哪些失败，以及失败原因。

入口：`S1-20 import-progress` 完成后存在失败、跳过、取消项，或用户从完成 toast 点击 `View details`。
退出：Done 返回来源主窗口并保持导入后的列表刷新；Retry Failed 回到 `S1-20 import-progress` 只处理失败项；Show existing file 定位到已有条目。

## 页面功能

- 显示成功、跳过、失败数量。
- 按状态筛选结果。
- 展示每项原因。
- 支持重试失败项或跳转已有文件。

## 布局与内容

标题：`导入结果`

摘要：`成功 19 · 跳过 2 · 失败 1`

筛选：All / Imported / Skipped / Failed。

表格列：

- 文件名
- 目标分类
- 状态
- 原因

示例：

- `2026Q1_合同.pdf | docs | Imported | -`
- `报告.pdf | docs | Skipped | 内容重复`
- `客户资料.zip | inbox | Failed | 无读取权限`

失败详情显示来源路径、错误和建议。

按钮：`Done`、`Retry Failed`、`Export Details...`。

## 状态与规则

- 无失败且无跳过时可只显示成功 toast。
- 重复跳过项提供 `Show existing file`。
- Retry Failed 只重试失败项。
- Export Details 只导出导入结果、错误码和脱敏路径，不包含用户文件内容，不自动上传。
- 无失败项时隐藏 `Retry Failed`。
- Retry Failed 执行中禁用 Done 以外的二次重试按钮，避免重复提交同一失败项。
- 所有路径展示默认脱敏，展开详情时仍不包含用户文件内容。
- 空态不适用：本页只在存在结果摘要时出现；完全成功且无需详情时用 toast，不打开空结果页。

## 交互

- 点击表格行显示详情。
- Done 关闭结果页，返回来源主窗口；如果导入目标在当前列表中，列表滚动到最近成功项。
- Retry Failed 进入 `S1-20 import-progress`，只用失败项重新组成队列；完成后刷新本结果页或显示新的结果页。
- Export Details 导出本地排查信息，导出前显示隐私说明。

## 可访问性

- 成功、跳过、失败数量需要作为摘要文本读出。
- 结果表格每行要读出状态、原因和可用动作。
- Done、Retry Failed、Export Details、Show existing file 都必须支持键盘访问。

## 数据与依赖

- import result summary。
- error mapping。
- retry import API。
- source route and selected category restore state。

## 验收清单

- 用户能知道每个跳过/失败原因。
- 成功项已经出现在列表中。
- Retry Failed 不重复导入成功项。
- Export Details 不包含用户文件内容。
- Done 后主窗口状态稳定，成功项可见或可通过 Show existing file 定位。

## 来源

- [docs/ux/drag-import-flow.md](../../drag-import-flow.md) 的“导入完成后的反馈（总结 + 下一步）”章节（组合）。
- `docs/ux/dedup-conflict.md#批量结果摘要`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-20 import-progress](S1-20-import-progress.md)
