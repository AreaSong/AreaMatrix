# S2-05 query-error - 高级查询错误

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-05
> 页面类型：搜索
> 页面文件：`S2-05-query-error.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 搜索体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Search/QueryErrorView.swift`。
- **建议组件**：`QueryErrorInlineView`、`QuerySyntaxHintPopover`、`QueryTokenHighlighter`。
- **实现说明**：查询错误显示在搜索输入下方或结果区顶部，不以系统 alert 打断输入。

## 页面背景

用户输入高级查询语法时可能出现未闭合引号、未知字段、非法日期、括号不匹配等错误。AreaMatrix 要说明哪里错、如何修，不应把错误伪装成“没有结果”。

入口：搜索解析器返回 query parse error。
退出：用户修正语法后进入搜索结果；点击清空回到普通列表；点击帮助打开查询语法说明。

## 页面功能

- 显示具体语法错误。
- 高亮错误 token 或错误位置。
- 给出可执行修复建议。
- 提供查询语法帮助入口。
- 允许用户清空查询。
- 阻止保存错误查询为 Smart List。

## 布局与内容

错误区域位于搜索框下方，结果列表区域显示更完整的错误说明。

Inline 错误：
- `Unclosed quote after “invoice”`
- `Unknown field “kindd”. Did you mean “kind”?`
- `Invalid date “2026-15-40”. Use YYYY-MM-DD.`

结果区标题：`Query could not be parsed`

结果区说明：
`Fix the highlighted part of your query to continue searching.`

错误详情卡：
- `Query: kindd:pdf tag:finance`
- `Problem: Unknown field “kindd”`
- `Suggestion: Use kind:pdf`

辅助动作：
- `Apply suggestion`
- `Clear query`
- `Open query help`

按钮语义：
- `Apply suggestion` 是主按钮，但仅在 parser 提供安全替换建议时显示。
- `Clear query` 是次按钮，清空 query 并回到普通列表。
- `Open query help` 是帮助入口，不改变搜索状态。
- 本页没有危险按钮；错误查询不能保存或执行搜索。

## 状态与规则

- 默认态：解析失败时保留原 query、光标和搜索框焦点。
- 禁用态：`Save...`、保存 Smart List 和执行搜索请求均禁用。
- 空态：没有可用修复建议时隐藏 `Apply suggestion`，仍显示 `Clear query` 和 `Open query help`。
- 加载态：帮助内容加载中时 `Open query help` popover 显示 `Loading help...`，不阻塞用户继续编辑 query。
- 错误态：`Apply suggestion` 失败时显示 `Could not apply suggestion`，保留原 query，并允许手动编辑。
- 恢复态：用户修正 query 后自动清除错误；点击 `Clear query` 回普通列表。
- 解析错误时不执行搜索请求。
- 错误查询不能保存为 Smart List。
- 字段名可纠正时显示 `Apply suggestion`。
- 无法定位错误位置时显示通用错误，但仍保留原查询。
- 普通关键词中出现冒号但未启用高级语法时，按搜索语法定义处理，不随意报错。
- 错误提示不能覆盖搜索输入，用户应能直接继续编辑。
- 模糊匹配和拼音首字母匹配不用于修正高级查询字段；例如 `kindd:pdf` 必须显示未知字段错误，而不是模糊执行。

## 交互

1. 用户输入后 debounce 解析。
2. 解析失败时保持光标在搜索框，显示 inline 错误和结果区错误页。
3. 点击 `Apply suggestion` 修改对应 token，并立即重新解析。
4. 点击 `Clear query` 清空搜索框和错误状态。
5. 点击 `Open query help` 打开 popover，展示支持字段示例；Esc 或点击外部关闭 help，不清空 query。
6. 用户手动修正后错误自动消失并显示搜索结果。

## 数据与依赖

- Query parser error type：unknown field、invalid operator、invalid date、unclosed quote、unbalanced parentheses。
- Token range/highlight information。
- Search field registry。
- Help content from search docs。
- Smart List save gate。

## 验收清单

- 未闭合引号、未知字段、非法日期、括号不匹配都有明确文案。
- 错误位置能在搜索框或查询预览中被高亮。
- 错误查询不能保存。
- 用户修正后自动回到结果页。
- `Apply suggestion` 不会破坏用户 query 的其他部分。
- VoiceOver 能读出错误并关联到搜索输入框。
- `Apply suggestion` 失败可恢复，且不丢原 query。
- 打开和关闭 query help 不改变搜索状态。
- 高级查询字段拼错不会被 fuzzy/pinyin 静默改写。

## 来源

- `docs/ux/search.md#高级查询语法可选`（直接来源）。
- `docs/ux/error-messages.md` 的可恢复错误表达原则（组合来源）。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-01 search-results](S2-01-search-results.md)
- [S2-03 saved-search-sheet](S2-03-saved-search-sheet.md)
- [S2-04 search-empty](S2-04-search-empty.md)
