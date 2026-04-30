# S2-08 tags-filter - 标签筛选

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-08
> 页面类型：标签
> 页面文件：`S2-08-tags-filter.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 标签与搜索。
- **建议目录**：`apps/macos/AreaMatrix/Features/Tags/TagFilterPopover.swift`。
- **建议组件**：`TagFilterPopover`、`SelectedTagChips`、`TagMatchModeControl`。
- **实现说明**：标签筛选是搜索过滤器的一部分，不能改变文件标签本身。

## 页面背景

用户希望通过标签快速筛选文件。标签可以来自手动添加或批量添加；未来阶段的自动标签也只会复用同一套筛选机制。本页只负责筛选，不负责生成标签。筛选应能组合多个标签，并清楚表达 Any/All 逻辑。

入口：搜索过滤器栏点击 `Tags` filter；侧边栏标签入口；Smart List 编辑器中添加标签条件。
退出：选择标签后更新搜索结果；清空标签筛选；保存为 Smart List。

## 页面功能

- 搜索并选择已有标签。
- 显示已选择标签 chips。
- 选择匹配模式：Any 或 All。
- 显示每个标签的大致文件数量。
- 支持移除单个标签或清空全部。
- 没有标签时提示如何添加标签。
- 标签数量很多时支持键盘搜索。

## 布局与内容

Popover 标题：`Filter by tags`

顶部搜索框：
- 占位：`Search tags`
- Stage 2 必须支持大小写不敏感匹配。
- Stage 2 标签筛选不要求拼音匹配；拼音首字母匹配只作为文件搜索能力定义在 `S2-01 search-results`。

匹配模式 segmented control：
- `Any`：文件包含任一选中标签即可。
- `All`：文件必须包含全部选中标签。

已选区：
- chips：`finance ×`、`tax ×`
- 按钮：`Clear all`

标签列表：
- 行内容：标签名、颜色点、文件数量。
- 已选标签显示 checkmark。
- 示例：`finance  24 files`

底部：
- 普通搜索场景不显示 `Apply`；选择变化即时刷新结果。
- Smart List 编辑场景显示状态文本 `Draft changes`，由外层 Smart List 保存按钮提交。
- `Clear all`
- `Close`

## 状态与规则

- 默认态：打开后读取当前 tag filter；普通搜索即时应用。
- 禁用态：没有标签或标签列表加载失败时禁用标签行选择；`Clear all` 在未选择标签时禁用。
- 加载态：标签列表加载中显示 `Loading tags...`，已选 chips 仍显示。
- 空态：没有任何标签时显示 `No tags yet` 和 `Add tags from file detail or batch actions.`。
- 错误态：标签列表加载失败时显示 `Could not load tags` 和 `Retry`；tag count 加载失败时 count 显示 `--`。
- 恢复态：Retry 成功后恢复列表；关闭 popover 不删除已选过滤条件。
- 没有选中标签时，筛选条件不生效。
- Any/All 只有选中两个及以上标签时才有明显差异；一个标签时仍可显示但说明一致。
- 没有任何标签：显示空态 `No tags yet` 和 `Add tags from file detail or batch actions.`。
- 搜索标签无结果：显示 `No matching tags`，不在本页创建新标签。
- 删除标签筛选不删除标签本身。
- Smart List 中打开时，选择变化只更新 Smart List draft，不立即保存。
- 标签搜索无论大小写都匹配同一标签；例如 `Finance`、`finance`、`FINANCE` 返回同一结果。

## 交互

1. 点击标签 filter 打开 popover 并聚焦搜索框。
2. 输入关键词过滤标签列表。
3. 点击标签行切换选中状态，已选 chips 立即更新。
4. 切换 Any/All 后普通搜索结果立即刷新；Smart List 编辑只更新 draft preview。
5. 点击 chip 上的 `×` 移除单个标签。
6. 按 Escape 关闭 popover；普通搜索保留已应用条件，Smart List draft 由外层 Cancel 回滚。

## 可访问性

- 键盘：搜索框、Any/All、tag rows、chips、Clear all 和 Close 均可 Tab 到达；列表支持方向键选择。
- 焦点：关闭后焦点回到 Tags filter 入口；Smart List draft 场景返回外层编辑 sheet。
- VoiceOver：读出标签名、文件数量、选中状态、Any/All 当前模式和禁用原因。
- 错误关联：标签加载失败和 count 获取失败必须关联到列表或对应标签行。
- 状态表达：颜色点、checkmark 和 chip 不能作为唯一状态；必须提供文本或 accessibility label。

## 数据与依赖

- Tag registry/list API。
- Tag count by current search scope。
- Search filter state。
- Smart List condition editor。
- Accessibility labels for chips and match mode。

## 验收清单

- 可选择多个标签并清楚显示 Any/All 模式。
- 移除筛选不会删除标签。
- 无标签和标签搜索无结果是两种不同空态。
- 标签筛选能与其他搜索过滤器组合。
- Smart List 编辑场景不会绕过外层保存确认。
- VoiceOver 能读出标签名、选中状态和文件数量。
- 标签列表失败和 count 失败是不同状态。
- 本页不能创建、删除或重命名标签。
- 标签搜索大小写不敏感；拼音匹配不作为本页 Stage 2 必做能力。

## 来源

- `docs/ux/search.md#filters过滤器`（组合来源）。
- `docs/ux/deep-features.md#2-标签系统tags`（直接来源）。
- 本页 Any/All 筛选细节依据 Stage 2 标签体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-02 search-filters](S2-02-search-filters.md)
- [S2-03 saved-search-sheet](S2-03-saved-search-sheet.md)
- [S2-07 tags-add](S2-07-tags-add.md)
