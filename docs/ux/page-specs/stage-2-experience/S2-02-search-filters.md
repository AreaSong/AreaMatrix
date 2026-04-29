# S2-02 search-filters - 搜索过滤器 Popover

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-02
> 页面类型：搜索
> 页面文件：`S2-02-search-filters.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 搜索体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Search/SearchFiltersPopover.swift`。
- **建议组件**：`SearchFiltersPopover`、`CategoryFilterPicker`、`DateFilterPicker`、`TagFilterPicker`、`FilterChipsBar`。
- **实现说明**：Popover 内过滤条件即时生效，不需要 Apply 按钮；Reset 只清空 filters，不清空 query。

## 页面背景

用户搜索结果太多，需要按分类、文件类型、日期和标签缩小范围。过滤器必须和搜索框、Smart List、无结果页保持同一套状态，不做独立临时筛选。普通搜索中条件即时生效；Smart List 编辑场景中只更新 draft，由外层保存动作提交。

入口：搜索工具栏 `Filters` 按钮、搜索 banner 的 filter chip、Smart List 编辑中的过滤器入口。
退出：点击外部、Esc、关闭 popover；条件变化后结果页即时刷新。

## 页面功能

- 设置 category 过滤。
- 设置 file type 过滤。
- 设置 modified date 过滤。
- 设置 tags 过滤。
- 显示 active filters 数量。
- 一键重置过滤器。
- 支持自定义日期范围校验。
- 将过滤条件显示为 chips。

## 布局与内容

Popover 从 toolbar `Filters` 按钮弹出，宽约 360。字段纵向排列，避免表格式拥挤。

字段：
- `Category`: All / Documents / Images / Custom...
- `Type`: All / PDF / Images / Spreadsheets / Other
- `Modified`: Any / Last 7 days / Last 30 days / This year / Custom...
- `Tags`: Any / All selected tags / Choose tags...

Custom date 展开区：
- `From` date picker。
- `To` date picker。
- 错误：`End date must be after start date.`

底部：
- `Reset filters`
- `Save as Smart List`
- 状态文本：`3 filters active`

按钮语义：
- `Reset filters` 是次按钮，只清空 filters，不清空 query，不关闭 popover。
- `Save as Smart List` 是主入口动作；仅在 query/filter/sort 至少一项有效且查询语法正确时启用，点击后关闭 popover 并打开 `S2-03 saved-search-sheet`。
- `Close` / `Esc` 是退出动作；普通搜索保留已即时应用条件，Smart List 编辑场景由外层 Cancel 回滚 draft。
- 本页没有危险按钮；不会创建、删除、移动、重命名文件，也不会修改标签定义。

Popover 外部：
- 搜索 banner 显示 chips：`PDF ×`、`Last 30 days ×`、`tag:finance ×`。

## 状态与规则

- 默认态：打开 popover 后读取当前 `SearchState` 或 Smart List draft。
- 禁用态：query/filter/sort 均为空、当前查询语法错误或 Smart List draft 已由外层保存流程接管时，`Save as Smart List` 禁用并显示原因。
- 加载态：category/type/tag 聚合加载中时对应行显示 skeleton 或 `Loading...`，其他已加载字段仍可用。
- 空态：没有任何可选标签时 Tags 行 disabled，并显示 `No tags yet`。
- 错误态：聚合加载失败时对应行显示 `Could not load filters` 和 `Retry`，不影响 query 输入。
- 恢复态：Retry 成功后恢复字段；Retry 失败保留当前已应用条件。
- 过滤变化立即刷新搜索结果。
- Tags 不存在时 Tags 行显示 disabled，并说明 `No tags yet`。
- Custom date 非法时不关闭 popover，不刷新到非法状态。
- Reset filters 保留 query，只清空 filters。
- Smart List 编辑场景中，filter 变化更新编辑草稿，不立即保存 Smart List。
- `Save as Smart List` 只创建新的 Smart List，不覆盖正在编辑的 Smart List。
- 过滤器无结果时进入 `S2-04 search-empty`，不是错误态。

## 交互

1. 点击 `Filters` 打开 popover，焦点落在第一个字段。
2. 选择 category/type/date 后立即更新 `SearchState`。
3. 选择 Tags 打开 `S2-08 tags-filter`；普通搜索即时应用，Smart List 编辑只更新 draft。
4. 点击 chip 的 `×` 移除单个过滤器。
5. 点击 `Reset filters` 清空所有 filters 并刷新结果。
6. 点击 `Save as Smart List` 关闭 popover，并打开 `S2-03 saved-search-sheet`，携带当前 query、filters、sort 和 scope。
7. 按 Esc 关闭 popover，已应用的即时修改保留。

## 数据与依赖

- Category list。
- File type aggregation。
- Tag list and selected tags。
- Date range parser/validator。
- SearchState。
- Smart List draft state。
- Saved search entry gate。

## 验收清单

- category/type/date/tag 可以组合使用。
- Reset filters 不清空 query。
- 自定义日期错误能提示且不污染结果状态。
- Tags 不存在时有禁用原因。
- Filter chips 能单独移除条件。
- VoiceOver 能读出每个 filter 当前值和 active count。
- 普通搜索和 Smart List 编辑场景的提交语义不同且可测试。
- 聚合加载失败时可重试，且不丢已有 query/filter。
- `Save as Smart List` 入口可打开 S2-03；语法错误或空条件时禁用。
- Reset、Save、Close/Esc 的主次动作和无危险行为可测试。

## 来源

- `docs/ux/search.md#filters过滤器`（直接来源）。
- [docs/ux/search.md#保存搜索（Saved Search / Smart List）](../../search.md#保存搜索saved-search--smart-list)（组合来源）。
- 标签筛选 draft 规则依据 Stage 2 Smart List 体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-01 search-results](S2-01-search-results.md)
- [S2-04 search-empty](S2-04-search-empty.md)
- [S2-08 tags-filter](S2-08-tags-filter.md)
