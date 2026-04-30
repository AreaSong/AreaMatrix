# S2-01 search-results - 搜索结果页

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-01
> 页面类型：搜索
> 页面文件：`S2-01-search-results.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 搜索体验
- **建议目录**：`apps/macos/AreaMatrix/Features/Search/`
- **建议组件**：`SearchField`、`SearchResultsView`、`SearchBannerView`、`SearchScopePicker`
- **实现说明**：这是主窗口搜索模式，不是独立搜索窗口。仍复用 File List 和 Detail。

## 页面背景

用户在 toolbar 搜索框输入关键词后，主窗口进入搜索模式。用户需要知道正在搜什么、在哪个范围搜、找到了多少结果。

入口：Toolbar 搜索框输入、Cmd+F 聚焦搜索后输入、Smart List 选择后进入同一搜索结果布局、Cmd+K 执行搜索相关命令。
退出：点击 `Clear` 清空 query 并返回普通文件列表；搜索框聚焦时按 `Esc` 等同于 `Clear`，但若有打开的 popover 先关闭 popover；选择结果行进入 Detail 但仍保留搜索上下文；从 Smart List 进入时 Back / Clear 返回打开前的 sidebar 或普通列表上下文，不删除 Smart List；`Save...` 打开 `S2-03 saved-search-sheet`；0 结果进入 `S2-04 search-empty`；高级查询错误进入 `S2-05 query-error`；Search API 失败停留本页错误态。

## 页面功能

- 聚焦并显示搜索 query。
- 切换搜索范围 All / Current。
- 展示搜索 banner、结果数量、清除和保存入口。
- 使用文件列表表格展示结果。
- 高亮命中片段，笔记命中时显示摘要。
- 支持关键词大小写不敏感、模糊匹配和中文拼音首字母匹配。

## 布局与内容

Toolbar：

- repo 下拉：`AreaMatrix ▾`
- 搜索框内容：`合同`
- scope 下拉：`All` / `Current`
- `Filters`
- `Import...`
- Settings

scope 默认值：
- 从 Smart List 进入：使用该 Smart List 保存的 scope，不重新推断。
- 从分类节点、Tree 当前节点或侧边栏分类内开始搜索：默认 `Current`。
- 从全局 toolbar、普通列表空焦点或 `Cmd+F` 直接开始搜索：默认 `All`。
- 用户手动切换 scope 后，本次搜索会话保持用户选择；Clear search 后回到普通列表，下次搜索重新按入口推断。

List 顶部 banner：

```text
搜索：“合同”  范围：全库  结果：42  [Clear] [Save...]
```

结果表格列：

- Name
- Path
- Category
- Modified
- Imported
- Status

示例行：

- `2026Q1_合同_客户A.pdf | docs/contracts | docs | Apr 28, 2026 | Apr 28, 2026 | OK`
- `合同模板.md | docs/templates | docs | Apr 12, 2026 | Apr 12, 2026 | OK`
- `客户B_合同扫描件.png | media/scans | media | Apr 9, 2026 | Apr 9, 2026 | OK`

Note 命中摘要：

```text
Note: ...等待客户回签合同扫描件...
```

匹配说明：
- 精确命中显示普通高亮。
- 模糊命中显示 `Fuzzy match` 轻量标记，并高亮最接近的片段。
- 拼音首字母命中显示 `Pinyin initials` 轻量标记，例如输入 `ht` 可匹配 `合同`。

排序控件：`Sort: Newest imported ▾`。

按钮语义：
- `Clear` 是次按钮，清空 query 并退出搜索模式。
- `Esc` 在搜索框聚焦且没有子 popover 时执行与 `Clear` 相同的退出语义；在 filter / help popover 打开时只关闭最上层 popover。
- `Save...` 是次按钮，只有查询有效时启用，打开保存搜索 sheet。
- `Retry` 只在错误态出现，是恢复动作，不改变 query、filters 或 sort。
- 本页没有危险按钮；删除、移动、批量操作必须跳转到对应确认页。

## 状态与规则

- 默认态：query 非空且解析成功时进入搜索模式，List 顶部显示 banner。
- 禁用态：查询解析错误时禁用 `Save...`；搜索请求进行中不禁用 Clear 和 Filters。
- 加载态：query、scope、filters 或 sort 变化后显示 `Searching...`，保留上一批结果直到新结果返回，避免空白闪烁。
- 空态：搜索返回 0 条进入 `S2-04 search-empty`。
- 错误态：Search API 失败时在 List 区显示 `Search failed`，提供 `Retry` 和 `Clear search`，不清空用户输入。
- 恢复态：索引不可用或损坏时显示 `Search index unavailable`，提供 `Open indexing status` 和 `Retry`。
- 默认排序：`imported_at desc`。
- 支持排序：Relevance、Newest imported、Newest modified、Name A-Z。
- scope 切换不清空 query。
- Back / 返回上下文不修改 query/filter/sort；仅恢复打开搜索前的导航焦点。Smart List 入口返回时不得删除或改写保存的查询记录。
- scope 初始值必须按入口推断：Smart List 使用保存值，分类上下文默认 Current，全局入口默认 All。
- query 输入 debounce 更新结果。
- 模糊匹配和拼音首字母匹配只用于普通关键词；高级查询字段和值仍按 `S2-05 query-error` 的语法规则解析。
- Relevance 排序必须把精确命中排在模糊和拼音命中之前；同类命中再按 imported_at desc 稳定排序。
- 高级语法错误进入 `S2-05 query-error`。
- 0 结果进入 `S2-04 search-empty`。

## 交互

- `⌘F` 聚焦搜索框。
- `Clear` 清空 query 并返回普通列表；从 Smart List 进入时只退出搜索模式或恢复打开前焦点，不删除 Smart List。
- 搜索框内按 `Esc`：若 query 非空则清空并退出搜索模式；若 query 已空则仅让搜索框失焦并恢复打开前焦点。
- `Save...` 打开 `S2-03 saved-search-sheet`。
- `Filters` 打开 `S2-02 search-filters`。
- 点击结果行更新右侧 Detail。
- 结果行进入 Detail 后保留搜索 banner、query、filters 和当前选中结果，Back 返回同一搜索结果列表。

## 可访问性

- 键盘：`⌘F` 聚焦搜索框，`Tab` 顺序为搜索框、scope、Filters、结果表格、Detail；结果表格支持方向键移动和回车打开。
- 焦点：Clear、Esc 或 Back 退出搜索后，焦点回到进入搜索前的 toolbar、sidebar 或列表位置。
- VoiceOver：搜索 banner 读出 query、scope、结果数量、加载/错误状态和当前选中行摘要。
- 错误关联：Search API 失败、索引不可用和查询解析错误必须关联到搜索框或结果区域，不能只显示独立 toast。
- 状态表达：命中高亮、Fuzzy match、Pinyin initials 和错误状态不能只依赖颜色；必须有文字或可读标签。

## 数据与依赖

- Search API：name、path、note content、category、change_log。
- Search matcher：case-insensitive keyword、fuzzy keyword、Chinese pinyin initials。
- Search state：query、scope、filters、sort。
- Saved search store。

## 验收清单

- `⌘F` 后可输入并实时刷新结果。
- All / Current 切换生效且不清空 query。
- 从 Smart List、分类节点和全局 Cmd+F 进入时，默认 scope 符合入口规则。
- 搜索结果仍能打开 Detail。
- 搜索 banner 显示 query、scope、count。
- 加载中、0 结果、查询错误、Search API 失败、索引不可用五类状态可区分。
- Retry 不清空 query、filters 或 sort。
- 普通关键词支持大小写不敏感、模糊匹配和中文拼音首字母匹配。
- 高级查询语法不会被模糊匹配误纠正；字段拼错进入 S2-05。
- Clear、Esc、结果行进入 Detail、Smart List 入口返回的行为都可测试且不改写 Smart List。

## 来源

- `docs/ux/search.md#结果列表呈现`（直接来源）。
- `docs/ux/search.md#搜索对象与字段stage-2`（直接来源）。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-02 search-filters](S2-02-search-filters.md)
- [S2-03 saved-search-sheet](S2-03-saved-search-sheet.md)
- [S2-04 search-empty](S2-04-search-empty.md)
- [S2-05 query-error](S2-05-query-error.md)
