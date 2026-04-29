# S2-12 batch-change-category - 批量改分类

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-12
> 页面类型：批量
> 页面文件：`S2-12-batch-change-category.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 批量操作。
- **建议目录**：`apps/macos/AreaMatrix/Features/BatchActions/BatchChangeCategorySheet.swift`。
- **建议组件**：`BatchChangeCategorySheet`、`CategoryPicker`、`BatchMovePreview`。
- **实现说明**：批量改分类可以只改元数据，也可以选择移动文件；移动文件是高风险动作，必须预览影响。

## 页面背景

用户多选文件后希望统一改到同一分类。部分文件可能是 repo-managed，部分是 Index-only，部分缺失或只读。页面必须清楚说明“改分类”和“移动文件到分类目录”的差别。

入口：多选后批量操作栏 `Change category`、右键菜单、命令面板。
退出：应用成功后返回主窗口并显示 Undo toast；取消不改变文件。

## 页面功能

- 显示选中文件数量和示例。
- 选择目标分类。
- 显示当前分类分布。
- 选择是否移动文件到目标分类目录。
- 预览会移动、只更新记录、无法处理的数量。
- 应用后写入 change log 并接入 Undo。

## 布局与内容

Sheet 标题：`Change category for 12 files`

摘要区：
- `Selected: 12 files`
- `Current categories: Reports (5), Invoices (4), Other (3)`
- 示例文件最多 5 个。

目标区：
- `New category` picker，支持搜索。
- `Create new category...`，如果 Stage 2 自定义分类启用。

选项：
- checkbox `Move files into the category folder`。
- 说明：`When off, only AreaMatrix metadata changes. Files stay in their current locations.`

影响预览：
- `8 files will move`
- `3 index-only records will update only`
- `1 missing file cannot move`

底部按钮：
- `Cancel`
- `Preview`
- 主按钮 `Apply`

按钮语义：
- `Preview` 是次按钮，用于刷新并展开完整 dry-run 结果，不写任何数据。
- `Apply` 是确认动作；只有当前 dry-run 成功、目标分类有效且无路径冲突或不可处理项时启用。
- `Cancel` 不改变分类、文件路径或 change_log。
- 本页没有 destructive 按钮；只有勾选移动选项时才会移动 repo-managed 文件，且必须先通过预览。

## 状态与规则

- 默认态：打开 sheet 后显示选中数量、当前分类分布、目标分类 picker 和影响预览。
- 禁用态：未选择目标分类、所有文件无变化、dry-run 存在冲突或不可移动项时禁用 Apply。
- 加载态：计算分类分布或移动 dry-run 时显示 `Previewing changes...`。
- 空态：多选为空时显示 `No files selected`，只提供 `Close`。
- 错误态：dry-run 或分类树加载失败时显示错误和 `Retry`，不执行任何写入。
- 恢复态：失败后保留用户目标分类和移动选项，允许重试或 Cancel。
- 未选择目标分类时禁用 Apply。
- 所有文件已在目标分类且不移动时禁用 Apply。
- 移动选项开启时必须检查目标目录可写和冲突。
- Index-only 文件不能移动源文件，只更新记录。
- 缺失文件默认列为 skipped；用户可关闭移动选项后只更新分类记录。
- 移动选项开启且存在目标路径冲突、权限不足或只读文件时禁用 Apply；用户必须关闭移动选项或先处理冲突。
- Apply 必须绑定最近一次 dry-run 结果；用户修改目标分类、移动选项或选择集后，旧 dry-run 失效并禁用 Apply，直到重新预览完成。
- 应用成功后必须提供 Undo。
- 部分失败时成功项保留，失败项显示原因；可撤销项进入 Undo stack。

## 交互

1. 打开 sheet 时计算当前分类分布。
2. 选择目标分类后刷新影响预览。
3. 勾选移动文件后执行 dry-run，显示冲突和不可处理项。
4. 点击 Preview 展开完整影响表。
5. 点击 Apply 执行批量分类更新和可选移动。
6. 部分失败时显示结果摘要和失败原因。
7. 点击 Cancel 不改变分类、文件路径或 change_log。

## 数据与依赖

- Current selection model。
- Category tree。
- Batch category update API。
- Batch move dry-run。
- Conflict detection。
- Undo stack。
- Change log。

## 验收清单

- 用户能区分只改分类和移动文件。
- Index-only 和缺失文件不会被误移动。
- 目标目录不可写或冲突时阻止移动。
- 应用前能看到影响数量。
- Apply 是确认动作，且必须基于最新 dry-run 结果。
- 成功后有 Undo toast 和 change log。
- VoiceOver 能读出目标分类、移动选项和影响摘要。
- 缺失文件、Index-only、只读文件和路径冲突有确定处理规则。

## 来源

- `docs/ux/deep-features.md#3-批量操作batch-actions`（直接来源）。
- `docs/ux/classifier-calibration.md`（组合来源）。
- Stage 2 批量和分类纠错页面规格（依据现有文档推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突）。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
