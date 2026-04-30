# S2-03 saved-search-sheet - 保存搜索

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-03
> 页面类型：搜索
> 页面文件：`S2-03-saved-search-sheet.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 搜索体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Search/SavedSearchSheet.swift`。
- **建议组件**：`SavedSearchSheet`、`SavedSearchPreview`、`SmartListNameField`。
- **实现说明**：保存搜索会在 Smart Lists 中生成入口，不改变当前文件分类、标签或索引内容。

## 页面背景

用户在搜索结果页调好关键词、过滤器、排序和高级查询后，希望保存为一个可重复访问的 Smart List。本页是一个 sheet，不是独立设置页。用户应该清楚“保存的是查询条件，不是复制文件”。

入口：搜索结果页点击 `Save...`；搜索无结果页点击 `Save empty Smart List`；搜索过滤器面板点击 `Save as Smart List`，该动作会先关闭过滤器 popover。
退出：保存成功后关闭 sheet，并在侧边栏选中新建 Smart List；Cancel 关闭 sheet 并回到打开前上下文，当前搜索条件不丢失；保存失败停留在 sheet 内，不回退上下文。

Cancel 返回规则：
- 从 `S2-01 search-results` 进入：回到搜索结果页。
- 从 `S2-04 search-empty` 进入：回到搜索无结果页，保留空结果 query/filter。
- 从 `S2-02 search-filters` 进入：回到搜索结果页，并保留普通搜索已即时应用的条件；Smart List draft 场景由外层编辑流程决定是否保存或回滚 draft。

## 页面功能

- 给当前搜索命名。
- 显示将被保存的查询摘要。
- 显示当前结果数量，用于确认条件是否合理。
- 允许选择 Smart List 图标或颜色标记。
- 允许选择是否固定到 sidebar 顶部。
- 校验名称为空、重复、过长。
- 保存后生成 Smart List 记录。

## 布局与内容

Sheet 标题：`Save Search`

顶部说明：
`Save the current query as a Smart List. Files are not moved or duplicated.`

表单字段：
- `Name`：文本框，默认根据关键词生成，例如 `Reports from 2026`。
- `Icon`：小图标选择，默认 magnifying glass。
- `Pin to sidebar`：checkbox，默认开启。

查询摘要卡：
- `Query: invoice OR receipt`
- `Filters: type:PDF, modified:this year, tag:finance`
- `Sort: Modified date, newest first`
- `Current results: 24 files`
- 次动作：`Edit filters`

`Edit filters` 语义：
- 关闭当前保存 sheet。
- 打开 `S2-02 search-filters`，并带入当前 query、filters、sort 和 scope。
- 不创建 Smart List，不修改现有 Smart List。
- 未保存的 Name、Icon、Pin to sidebar 选择不保留；搜索条件本身保留。

冲突/校验文案：
- 名称为空：`Name is required.`
- 名称重复：`A Smart List named “Finance” already exists.`
- 查询无效：`Fix the query before saving this search.`

底部按钮：
- `Cancel`
- 主按钮 `Save`

## 状态与规则

- 默认态：打开时显示默认名称、查询摘要、当前结果数量和 `Save`。
- 禁用态：名称为空、名称重复、名称超过 64 字符或当前查询语法错误时禁用 `Save`；保存进行中禁用全部表单控件、`Edit filters` 和 `Save`，保留 `Cancel` 但点击需二次提示正在保存。
- 空态：当前结果为 0 时允许保存，但显示 `This Smart List is currently empty.`。
- 当前查询为空但存在过滤器时允许保存，名称默认从过滤器生成。
- 当前查询语法错误时禁用 `Save`，并显示来自 `S2-05 query-error` 的错误摘要。
- 当前结果为 0 时允许保存，但显示黄色提示 `This Smart List is currently empty.`。
- 名称重复时禁用 `Save`，不自动覆盖旧 Smart List。
- 保存失败时保持 sheet 打开，用户输入不丢失。
- Cancel 始终关闭 sheet 并返回打开前上下文；从 S2-04 进入时必须回到 S2-04 的无结果状态，不强制跳到 S2-01。
- 保存内容只包含 query/filter/sort，不保存当前选中文件列表。
- 加载态：打开 sheet 后 result count 仍在计算时显示 `Counting results...`，Save 仍按 query 有效性和名称校验决定是否可用。
- 错误态：result count 获取失败时显示 `Result count unavailable`，允许保存有效查询。
- 恢复态：保存失败时表单顶部显示错误和 `Retry`，名称、图标、Pin 选择和查询条件不丢失。

## 交互

1. 打开 sheet 时从搜索状态生成默认名称和查询摘要；若从 Filters 进入，保留当前 query、filters、sort 和 scope。
2. 用户修改名称时即时校验重复和长度。
3. 点击查询摘要里的 `Edit filters` 关闭 sheet 并打开 `S2-02 search-filters` 的 Smart List draft context；未保存的名称、图标和 Pin 选择不保留，当前搜索条件不丢失。
4. 点击 `Save` 后按钮显示 `Saving...`，表单禁用。
5. 保存成功后关闭 sheet，sidebar 中出现新 Smart List 并自动选中。
6. 保存失败时在表单顶部显示错误，并恢复按钮。
7. 点击 `Cancel` 关闭 sheet，按打开来源返回 S2-01、S2-04 或过滤器入口后的搜索上下文；不创建 Smart List，不修改现有 Smart List。

## 可访问性

- 键盘：sheet 打开后焦点落在 `Name` 字段，`Tab` 顺序经过图标、Pin、查询摘要、Cancel、Save。
- 焦点：Cancel 或保存成功后焦点回到打开 sheet 的 Save 入口；`Edit filters` 跳转后返回时保留搜索上下文。
- VoiceOver：读出名称字段校验、查询摘要、Pin 状态、Save 禁用原因和保存结果。
- 错误关联：重名、空名称、查询无效和保存失败必须关联到字段或表单顶部错误区。
- 状态表达：图标和 Pin 不能作为唯一含义；必须有文本 label 或 accessibility value。

## 数据与依赖

- 当前 `SearchQuery`、filter state、sort state。
- Smart List persistence API。
- Smart List name uniqueness check。
- Search result count provider。
- Sidebar selection/navigation API。

## 验收清单

- 保存前能看到查询条件和当前结果数量。
- 名称为空、重复、查询错误时不能保存。
- 0 结果搜索可以保存，但有明确提示。
- 保存成功后 Smart List 出现在 sidebar 并可点击复现查询。
- 保存失败不会丢失用户填写的名称。
- VoiceOver 能读出查询摘要、错误和 Save 按钮禁用原因。
- Edit filters 回到过滤器 draft，不直接保存 Smart List。
- result count 失败不阻止保存有效查询。
- 从 Filters 入口打开时，popover 已关闭且当前搜索条件完整带入本 sheet。

## 来源

- [docs/ux/search.md#保存搜索（Saved Search / Smart List）](../../search.md#保存搜索saved-search--smart-list)（直接来源）。
- `docs/ux/deep-features.md#6-智能列表smart-lists`（组合来源）。
- 本页图标、固定到 sidebar 等字段依据 Stage 2 Smart Lists 目标推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-01 search-results](S2-01-search-results.md)
- [S2-02 search-filters](S2-02-search-filters.md)
- [S2-06 smart-lists](S2-06-smart-lists.md)
