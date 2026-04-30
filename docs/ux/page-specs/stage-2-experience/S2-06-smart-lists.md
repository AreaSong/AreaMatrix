# S2-06 smart-lists - 智能列表侧边栏与管理

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-06
> 页面类型：智能列表
> 页面文件：`S2-06-smart-lists.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 智能列表。
- **建议目录**：`apps/macos/AreaMatrix/Features/SmartLists/SmartListSection.swift`。
- **建议组件**：`SmartListSection`、`SmartListRow`、`SmartListContextMenu`、`SmartListRenameSheet`。
- **实现说明**：Smart List 是保存搜索在 sidebar 中的固定入口；删除 Smart List 不删除文件。Rename、Duplicate、Delete、Edit query 子 sheet 都归本页规格负责，Stage 2 不再拆新页面。

## 页面背景

用户保存搜索后，需要像 Finder Smart Folder 一样从 sidebar 快速进入。Smart List 不是文件夹，不移动文件，也不拥有文件；它只是查询条件的命名入口。

入口：保存搜索成功、sidebar Smart Lists 分组、设置或命令面板导航到 Smart List。
退出：点击 Smart List 进入搜索结果；右键重命名、复制或删除；清空搜索回到普通列表。

## 页面功能

- 在 sidebar 显示 Smart Lists 分组。
- 显示每个 Smart List 名称、图标和可选结果数量。
- 点击进入对应搜索模式。
- 右键管理：Rename、Duplicate、Delete。
- 管理子流程：Rename、Duplicate、Delete、Edit query 都在本页定义的 sidebar 管理边界内完成。
- Stage 2 使用固定排序：Pinned first，其余按名称 A-Z；不支持拖拽排序。
- 显示规则异常状态，例如查询字段已失效或过滤条件不可解析。

## 布局与内容

Sidebar 分组：

```text
Smart Lists
  最近合同        12
  本周发票        24
  待处理冲突       3
```

行内容：
- 图标。
- 名称。
- 结果数量或状态徽标。
- 依赖异常时显示 warning dot。
- Pin 状态；pinned 项显示在分组顶部。

右键菜单：
- `Open`
- `Rename...`
- `Duplicate...`
- `Edit query...`
- `Delete...`

点击后的搜索 banner：
`Smart List: 最近合同  query="合同"  [Edit] [Clear]`

空态：
- 如果没有 Smart List，分组可隐藏。
- 在搜索页保存后再出现，不需要显示“创建第一个”。

管理确认：
- Rename：就地编辑或 sheet，按钮为 `Cancel`、`Save`。
- Duplicate：默认名称 `原名称 Copy`，默认不 pin，允许编辑，按钮为 `Cancel`、`Create`。
- Delete：确认文案必须包含 `This only removes the Smart List. Files will not be deleted or moved.`，按钮为 `Cancel`、destructive `Delete Smart List`。

Edit query sheet / draft context：
- 入口：sidebar 右键 `Edit query...`、Smart List 搜索 banner 的 `Edit`。
- 标题：`Edit Smart List`
- 只读摘要：当前 Smart List 名称、图标、Pin 状态。
- 字段：`Query` 输入框、`Scope` picker、`Filters summary`、`Sort` picker、`Current results`。
- 错误区：query parse error、filter load error、result count unavailable、save failed。
- 按钮：`Cancel`、`Reset changes`、`Edit filters`、主按钮 `Save changes`。
- `Edit filters` 打开 `S2-02 search-filters` 的 Smart List draft context；S2-02 只更新 draft，不直接保存 Smart List。
- `Save changes` 更新当前 Smart List 的 query/filter/sort/scope，不创建新 Smart List，不修改文件、标签、分类或索引。
- `Cancel` 丢弃 draft 并回到打开前上下文；`Reset changes` 将 draft 恢复为已保存 Smart List 的当前值。
- 保存成功后关闭编辑 sheet，sidebar 仍选中该 Smart List，并刷新搜索结果。

## 状态与规则

- 默认态：sidebar 有 Smart List 时显示分组、名称、图标和可选数量。
- 禁用态：Rename/Duplicate 输入为空、重复或非法时禁用确认按钮；Delete 确认加载中时禁用 destructive 按钮。
- 加载态：数量计算中显示 `...` 或轻量 spinner，行仍可点击。
- 空态：没有 Smart List 时分组可隐藏；从搜索页保存后再出现。
- 错误态：列表读取失败时显示 `Could not load Smart Lists` 和 `Retry`，不影响普通 Tree/List 浏览。
- 恢复态：Rename/Duplicate/Delete 失败时保持原记录和用户输入，显示错误并允许重试。
- 删除 Smart List 需要确认，并说明不会删除文件。
- Rename 名称不能为空且不能重复。
- Duplicate 必须要求新名称或自动生成 `Copy` 并允许编辑。
- Smart List 查询字段失效时，行仍显示，点击后进入可恢复状态，并提供 `Edit query...`。
- 结果数量计算失败时显示 `--`，不隐藏列表。
- Edit query 打开时必须从已保存 Smart List 创建 draft；draft 与已保存记录分离，直到 `Save changes` 成功。
- Edit query 中 query 语法错误时禁用 `Save changes`，并显示 `S2-05 query-error` 同类错误摘要。
- Edit query 中 result count 获取失败不阻止保存有效 query/filter/sort/scope，但必须显示 `Result count unavailable`。
- Edit query 保存失败时保留 draft、错误原因和 `Retry`，不得回滚到静默旧值。
- Edit query 的 `Cancel` 和 `Reset changes` 都不得写 SavedSearchStore。
- 排序规则固定为 pinned first；pinned 内按用户 pin 时间倒序，其余按名称 A-Z。
- Stage 2 不支持拖拽排序，也不暴露手动排序设置。
- Smart List 不应出现在 Stage 1 范围。
- Stage 2 不注册超出普通搜索字段的 Smart List；未来阶段的智能搜索依赖由对应阶段规格处理。
- 本页包含 Smart List sidebar 区域、右键菜单、Rename/Duplicate/Delete 确认和 Edit query sheet；实现时不得再新增未登记的 S2 页面 ID。

## 交互

1. 保存搜索成功后 sidebar 插入新行并选中。
2. 点击 Smart List 更新 `SearchState`，中间列表显示搜索结果。
3. 点击 banner `Edit` 或右键 `Edit query...` 打开 Edit query sheet，并从已保存 Smart List 创建 draft。
4. 右键 Rename 打开就地编辑或 sheet，保存后立即更新 sidebar。
5. 右键 Duplicate 打开创建 sheet，默认名称为 `原名称 Copy`，确认后按固定排序插入。
6. Delete 弹确认，确认后只删除 Smart List 查询记录，不触碰文件、标签、分类或索引条目。
7. 查询字段失效时点击行显示原因和恢复动作。
8. Edit query 中点击 `Edit filters` 打开 S2-02 draft；返回后 Edit query sheet 显示更新后的 filters summary 和 result count。
9. Edit query 中点击 `Save changes` 更新当前 Smart List；保存失败停留 sheet，保存成功刷新当前搜索结果。
10. Edit query 中点击 `Cancel` 丢弃 draft，回到打开前 Smart List 搜索结果或 sidebar 上下文。

## 可访问性

- 键盘：Smart Lists 分组可用方向键浏览，右键菜单动作也必须能通过键盘菜单打开。
- 焦点：Rename/Duplicate/Delete/Edit query 子流程关闭后，焦点回到对应 Smart List 行；删除成功后移到相邻行或分组标题。
- VoiceOver：读出 Smart List 名称、结果数量、pin 状态、选中状态和查询异常。
- 错误关联：管理失败、查询字段失效和结果数量失败必须关联到对应行或子 sheet 表单。
- 状态表达：warning dot、pin 图标和选中状态不能只靠颜色或图标；需要文本或 accessibility value。

## 数据与依赖

- SavedSearchStore。
- SavedSearch update API。
- Smart List draft store。
- SearchState。
- Sidebar tree model。
- Search result count provider。
- Name uniqueness validator。
- Query validator and migration hint。
- Pin state and created/updated timestamp。

## 验收清单

- 保存搜索后 sidebar 出现 Smart List。
- 点击 Smart List 可复现 query、filters、sort。
- Rename/Duplicate/Delete 都有可恢复 UI。
- 删除 Smart List 不删除任何文件。
- Stage 2 排序为 pinned first + 名称 A-Z，不支持拖拽排序。
- 查询字段失效或结果数量失败时用户能看到原因。
- VoiceOver 能读出 Smart List 名称、数量和选中状态。
- Edit query 可以修改 query、scope、filters 和 sort，并通过 `Save changes` 更新现有 Smart List。
- Edit query 的 `Cancel` 和 `Reset changes` 不写入 SavedSearchStore。
- S2-02 在 Smart List draft context 中只改 draft；外层 `Save changes` 成功前不会持久化。
- Edit query 保存失败保留 draft、错误和重试入口。
- Rename/Duplicate/Delete/Edit query 子 sheet 都由本页验收，不需要额外单页规格。
- Stage 2 不出现智能搜索依赖作为必做验收。

## 来源

- `docs/ux/deep-features.md#6-智能列表smart-lists`（直接来源）。
- [docs/ux/search.md#保存搜索（Saved Search / Smart List）](../../search.md#保存搜索saved-search--smart-list)（组合来源）。
- 管理失败恢复规则依据 Stage 2 Smart Lists 体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-01 search-results](S2-01-search-results.md)
- [S2-03 saved-search-sheet](S2-03-saved-search-sheet.md)
- [S2-15 command-palette](S2-15-command-palette.md)
