# S2-04 search-empty - 搜索无结果

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-04
> 页面类型：搜索
> 页面文件：`S2-04-search-empty.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 搜索体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Search/SearchEmptyState.swift`。
- **建议组件**：`SearchEmptyStateView`、`RelaxFilterSuggestions`、`SearchEmptyActions`。
- **实现说明**：本页只处理搜索无结果，不处理资料库整体空态；整体空库仍由 Stage 1 主窗口空态负责。

## 页面背景

用户执行搜索后没有匹配文件。无结果不一定是错误，可能是关键词拼写、过滤条件过严、索引未完成或搜索范围太窄。页面要帮助用户快速调整，而不是只显示“没有结果”。

入口：搜索结果页返回 0 条。
退出：用户继续在搜索框输入或修改过滤器后重新查询，命中后返回 `S2-01 search-results`；`Clear search` 清空 query 并回到当前资料库列表；`Clear filters` 保留 query 并重新查询；搜索框聚焦时按 `Esc` 等同于 `Clear search`，但打开子 popover 时只关闭 popover；Back 返回进入搜索前的列表、Smart List 或 sidebar 上下文；保存空搜索时进入 `S2-03 saved-search-sheet`。

## 页面功能

- 显示当前搜索没有结果。
- 展示导致无结果的关键词和过滤器摘要。
- 提供放宽过滤器的快捷动作。
- 提供清空搜索、清空过滤器、检查拼写。
- 在普通关键词搜索中展示模糊匹配和拼音首字母匹配建议。
- 在索引未完成时说明结果可能不完整。
- 允许保存当前空结果搜索，适合未来自动收集匹配项。

## 布局与内容

主区域居中，但不要做大面积插画。使用轻量搜索图标即可。

标题：`No files found`

说明根据场景变化：
- 只有关键词：`No files match “invoice 2026”.`
- 有过滤器：`No files match this query and 3 active filters.`
- 索引中：`Search is still indexing. Results may appear in a moment.`

条件摘要：
- `Query: invoice 2026`
- `Filters: PDF, tag:finance, modified:this month`

建议动作：
- `Clear search`
- `Clear filters`
- `Remove date filter`
- `Search all file types`
- `Try fuzzy match suggestion`，例如 `invoicee` -> `invoice`
- `Try pinyin initials`，例如 `ht` -> `合同`
- `Save empty Smart List`，弱化显示。

按钮语义：
- 首要动作根据原因切换：过滤器导致无结果时 `Clear filters` 为主按钮；仅关键词无结果时 `Clear search` 为主按钮。
- `Remove ... filter` 和 `Search all file types` 是快捷次按钮，只修改对应过滤条件。
- `Save empty Smart List` 是弱次按钮，不应使用强调样式。
- `Esc` 是键盘退出动作；无子 popover 时执行 `Clear search`，不会清空 filters，除非用户显式点击 `Clear filters`。
- 本页没有危险按钮，不删除、不移动、不修改任何文件或标签。

底部辅助：
- `Last indexed: Apr 29, 2026 11:30`
- 索引状态异常时显示 `Open indexing status`。

## 状态与规则

- 默认态：搜索成功且结果为 0，显示当前 query/filter 摘要和调整建议。
- 禁用态：索引异常时禁用 `Save empty Smart List`，直到 query/filter 状态可被持久化。
- 加载态：索引仍在建立时优先显示 `Indexing...`，不立即建议用户删除过滤器。
- 空态：资料库整体为空时跳转或内嵌 Stage 1 空库提示，不显示搜索建议。
- 错误态：Search API 失败不进入本页，应由 `S2-01 search-results` 显示错误态。
- 恢复态：索引异常时显示 `Open indexing status`；用户仍可 Clear search 或 Clear filters。
- 没有关键词但过滤器导致无结果：标题仍为 `No files found`，首要动作是 `Clear filters`。
- 高级查询语法错误不进入本页，应进入 `S2-05 query-error`。
- 索引未完成时不建议用户立刻删除过滤器，优先显示 `Indexing...`。
- 当前资料库为空时跳转或内嵌 Stage 1 空库提示，不显示搜索建议。
- 保存空搜索允许，但文案必须说明“未来匹配文件会出现在这里”。
- 有 fuzzy 或 pinyin 建议时优先展示建议 chip；点击建议只替换普通关键词，不改变 filters、scope 或 sort。
- Back / 返回上下文不保存空搜索、不修改 filters，也不删除 Smart List；仅恢复进入搜索前的导航焦点。

## 交互

1. 点击 `Clear search` 清空关键词，保留过滤器。
2. 点击 `Clear filters` 移除所有 filters，保留关键词。
3. 点击某个 `Remove ... filter` 只移除对应过滤器并立即重新搜索。
4. 点击 `Search all file types` 移除 type filter。
5. 点击 fuzzy 或 pinyin 建议替换 query 并立即重新搜索。
6. 索引中状态每隔合理时间刷新一次，不闪烁重排。
7. 点击 `Save empty Smart List` 打开保存搜索 sheet，并携带当前 query/filter。
8. 继续在搜索框输入时本页就地更新条件；有结果后返回 S2-01，仍保留 scope、sort 和未清除的 filters。
9. 按 `Esc` 时，如无打开的 popover，执行 `Clear search` 并回到进入搜索前上下文；如果 query 已为空，仅恢复焦点。

## 可访问性

- 键盘：建议动作按主次顺序可 Tab 到达，fuzzy / pinyin 建议 chip 可用方向键或 Tab 选择。
- 焦点：Clear search、Esc 或 Back 后焦点回到进入搜索前位置；Clear filters 后焦点留在搜索框以便继续输入。
- VoiceOver：读出无结果原因、query、filters 摘要、索引状态和每个建议动作的效果。
- 错误关联：索引异常和 backend error 不应被读成普通空态，必须有关联到状态说明的可读错误。
- 状态表达：空态、索引中、资料库空和错误态不能只靠图标或颜色区分。

## 数据与依赖

- 当前 search query 和 filters。
- Search result count。
- Indexing status。
- Smart List save entry。
- Filter mutation actions。
- Fuzzy / pinyin suggestion provider。

## 验收清单

- 关键词无结果、过滤器无结果、索引中、资料库空四种场景文案不同。
- 用户能一键清空搜索或过滤器。
- 高级查询错误不会被误显示为空结果。
- 保存空 Smart List 的含义清楚。
- 页面不会遮挡搜索输入框，用户可直接继续输入。
- VoiceOver 能读出当前条件摘要和建议动作。
- no result、indexing、empty repo、backend error 四类状态不会混淆。
- fuzzy 和 pinyin 建议只修改 query，不改 filters、scope 或 sort。
- Clear search、Clear filters、Esc、Back 和继续输入的返回路径可区分。

## 来源

- `docs/ux/search.md#空结果no-results规范`（直接来源）。
- `docs/ux/ui-states.md`（组合来源）。
- Smart List 空结果行为依据 Stage 2 搜索体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-01 search-results](S2-01-search-results.md)
- [S2-02 search-filters](S2-02-search-filters.md)
- [S2-03 saved-search-sheet](S2-03-saved-search-sheet.md)
- [S2-05 query-error](S2-05-query-error.md)
