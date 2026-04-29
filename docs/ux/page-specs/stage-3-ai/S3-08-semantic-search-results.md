# S3-08 semantic-search-results - 语义搜索结果

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-08
> 页面类型：智能搜索  
> 页面文件：`S3-08-semantic-search-results.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS 语义搜索。
- **建议目录**：`apps/macos/AreaMatrix/Features/Search/SemanticSearchResultsView.swift`。
- **建议组件**：`SemanticSearchResultsView`、`SemanticSearchBanner`、`SemanticMatchExplanationView`。
- **实现说明**：语义搜索是普通搜索的增强模式。AI 不可用时必须回退到普通搜索。

## 页面背景

用户输入自然语言查询，例如“上个月的发票”或“客户 A 的合同”，希望跨文件名、笔记、摘要和元数据找到相关资料。语义搜索结果有相关度和解释，但不应让用户误以为结果绝对准确。

入口：搜索框切换 `Semantic` 模式；普通搜索无结果时点击 `Try semantic search`；命令面板搜索语义模式。
退出：切回普通搜索、打开文件详情、保存为依赖语义索引的 Smart List。

## 整体风格

语义搜索是普通搜索增强，不替代普通搜索。页面应保持搜索结果列表的密度和可扫描性，突出 query、模式、索引状态、相关度和为什么匹配。低置信度、索引未就绪、远程不可用和隐私跳过要用明确文字提示，不做“智能答案”式承诺。

## 页面功能

- 显示自然语言 query。
- 展示语义匹配结果。
- 显示相关度、匹配理由和使用字段。
- 支持普通 filters 对语义组和普通搜索组同步过滤。
- 支持低置信度提示。
- AI 不可用时提供普通搜索回退。
- 远程语义搜索必须受远程启用和隐私规则限制。
- 与 Stage 2 普通搜索共享搜索结果容器、filters、保存搜索入口和分页模型，并在语义模式中合并展示 `Semantic matches` 与 `Normal search matches` 两组结果；不把两种来源压成一个不可解释的单一分数。

## 布局与内容

搜索模式 banner：
- `Semantic search: “上个月的发票”`
- `18 results`
- 按钮：`Use normal search`
- 按钮：`Filters`
- 按钮：`Save...`
- 按钮：`Build semantic index`，仅索引未就绪时显示。
- 按钮：`Pause index build`、`Cancel index build`，仅索引构建中显示。
- 状态徽标：`Local` 或 `Remote`。

与普通搜索关系：
- 本页复用 Stage 2 搜索的结果列表外壳、filters popover、保存搜索 sheet 和分页控件。
- 语义模式默认同时请求 semantic search API 和 Stage 2 normal search API，并按来源分组展示。
- 第一组固定为 `Semantic matches`，按 relevance 排序；第二组固定为 `Normal search matches`，沿用 Stage 2 普通搜索排序。
- 不做全局混排，不生成跨来源统一 score；如未来要单一混排排序，必须新增规格说明排序公式和可解释性。
- `Use normal search` 使用同一 query、scope 和可兼容 filters 返回 Stage 2 普通搜索；返回后隐藏 semantic relevance、matched reason、semantic index dependency 和来源分组。
- 普通搜索无结果进入本页时，Back / Cancel 返回原普通搜索无结果状态，不改 query 或 filters。
- 从语义模式进入文件详情再 Back 时，返回当前分组、排序、filters、page 和选中行。

结果表格列：
- `Name`
- `Path`
- `Category`
- `Match source`: Semantic / Normal。
- `Relevance`: 仅语义组显示，普通组显示 `-`。
- `Matched reason`: 语义组显示 AI 匹配解释，普通组显示 Stage 2 命中字段或片段。
- `Modified`

结果分组：
- `Semantic matches`：显示 semantic search 返回的文件、score、matched reason、used fields 和 local/remote 标记。
- `Normal search matches`：显示同一 query 的普通搜索结果，作为 AI 不完整或低置信时的可解释补充。
- 分组标题显示数量：`Semantic matches (12)`、`Normal search matches (8)`。
- 如果同一文件同时出现在两组，默认只在 `Semantic matches` 显示一次，并在行内显示 `Also matched normal search`；普通组数量中仍计入但不重复渲染该行。
- 用户可展开 `Show duplicate normal matches` 查看被折叠的普通搜索重复项；展开只影响当前页面，不改变保存搜索条件。

排序与分页：
- 默认排序：语义组 `relevance desc`，同 relevance 时按 `modified desc` 再按 `name A-Z`；普通组沿用 Stage 2 当前排序。
- 用户可切换语义组排序：`relevance`、`newest modified`、`name A-Z`；普通组排序跟随 Stage 2 搜索排序控件。
- 切换排序不重新生成 embedding，不改变 query，不改变分组来源。
- 分页沿用 Stage 2 page size，但两组分页状态分开保存：`semantic page` 和 `normal page`。
- `Load more semantic` 只请求下一页语义结果；`Load more normal` 只请求下一页普通搜索结果；任一分页失败不清空另一组已加载结果。
- filters 变化时必须同时作用于 semantic search 和 normal search；如需要服务端重新查询，必须保留原 query、scope、filters 和 mode `Semantic`。

结果行示例：
- Semantic：`invoice_0426.pdf | finance/invoices | Semantic | 0.91 | filename and summary match “invoice”`
- Semantic + normal duplicate：`客户A_付款记录.xlsx | finance | Semantic | 0.82 | note mentions last month payment | Also matched normal search`
- Normal：`invoice_notes.txt | finance/invoices | Normal | - | filename contains “invoice”`

详情提示：
- Detail 顶部显示 `From semantic search`。
- 可展开 `Why this matched`，显示字段类型和片段，但避免展示被隐私规则排除的内容。

语义索引构建提示：
- 默认路径：本地 embedding / 本地 semantic index，文件内容不离开本机。
- 远程 embedding / remote semantic index 仅在远程 AI 已显式启用、`Semantic search` scope 允许、测试连接成功且隐私规则通过时可用。
- 构建前显示将处理的文件数、预计跳过数量、provider、是否远程和隐私规则检查结果。
- 隐私命中文件不进入远程索引构建；写入 S3-05 skipped 记录，sent fields 为 none。

Build semantic index 确认 sheet：
- 标题：`Build semantic index?`
- 说明：`AreaMatrix will build a semantic index for searchable files. Local indexing keeps file content on this device. Remote indexing is used only when remote AI is explicitly enabled and allowed for Semantic search.`
- 明细：文件数、预计跳过数、provider、本地/远程、隐私规则检查结果、字段过滤结果和日志 gate 状态。
- 主按钮：`Start index build`
- 次按钮：`Cancel`
- 可选返回按钮：`Back`
- `Cancel` 或 `Back` 返回语义搜索页，不启动构建，不改变 query、filters、scope 或普通搜索结果。
- 如果 gate 检查失败，不显示可点击的 `Start index build`；按失败原因显示恢复动作：`Open AI settings`、`Configure remote AI`、`View privacy rule`、`View call log` 或 `Use normal search`。

Cancel index build 确认 sheet：
- 标题：`Cancel semantic index build?`
- 说明：`AreaMatrix will stop processing remaining files. Already committed local index fragments can still be used; uncommitted temporary index data will be cleaned up. Remote queues will stop and no more content will be sent.`
- 明细：已完成文件数、待处理文件数、远程队列剩余数、将清理的临时索引大小。
- 主按钮：`Cancel index build`
- 次按钮：`Keep building`
- 点击 `Keep building` 返回构建中状态，不改变进度或队列。
- 点击 `Cancel index build` 后显示 `Canceling semantic index build...`，禁用 `Pause index build`、`Cancel index build` 和 `Retry failed items`，保留 `Use normal search`。
- 取消成功后返回语义搜索页，显示 `Semantic index build canceled.`，操作为 `Use normal search`、`Retry index build`、`View call log`。

## 状态与规则

- 搜索中：显示 `Searching semantically...`，保留 query、scope 和 filters，结果表格显示 skeleton。
- 搜索中同时显示两个 group placeholder：`Searching semantic matches...` 和 `Searching normal matches...`；普通搜索已返回但语义仍在加载时，普通组可先展示。
- 无结果：当两组都无结果时显示 `No semantic or normal results for this query.`，主操作 `Clear filters`，次操作 `Use normal search`。
- 仅语义无结果：显示空的 `Semantic matches` 组和说明 `No semantic matches. Normal search results are shown below.`。
- 仅普通无结果：显示空的 `Normal search matches` 组和说明 `No normal matches. Semantic matches are shown above.`。
- AI 总开关关闭：显示 fallback，按钮 `Use normal search` 和 `Open AI settings`。
- 语义索引未建立：显示 `Semantic index is not ready`、`Build semantic index` 和普通搜索回退。
- 语义索引构建中：显示进度 `Building semantic index... 42%`、已处理/跳过/失败数量，结果禁用，允许 `Use normal search`、`Pause index build` 和 `Cancel index build`。
- 暂停索引构建：显示 `Semantic index build paused.`，主操作 `Resume index build`，次操作 `Use normal search`。
- 启动索引构建前必须显示 `Build semantic index?` 确认 sheet；只有 AI 总开关、Semantic search 功能开关、provider、usage scope、隐私规则、字段过滤和日志 gate 全部通过时，`Start index build` 才可点击。
- 启动 gate 失败时不允许点击 `Start index build`；恢复动作必须指向具体阻断来源，不得用 privacy gate 绕过 provider/scope，也不得在本页直接启用远程 provider。
- `Build semantic index?` 的 `Cancel` 或 `Back` 返回语义搜索页，保留 query、filters、scope、普通搜索结果和当前索引状态，不启动构建。
- 取消索引构建：必须先显示确认 sheet；确认后立即停止本地和远程队列的后续处理，远程任务不得继续发送内容。
- 取消索引构建后固定策略：已提交的本地可用索引片段保留；未提交的临时索引、临时 embedding batch 和未完成队列必须清理；远程队列中尚未发送的任务必须撤销。
- 取消中：显示 `Canceling semantic index build...`，禁用构建控制按钮，保留 `Use normal search`。
- 取消成功：显示 `Semantic index build canceled.`，操作为 `Use normal search`、`Retry index build`、`View call log`；返回本页时 query、filters、scope 和普通搜索结果保持不变。
- 取消失败：显示 `Semantic index build could not be canceled.`，操作为 `Retry cancel`、`Use normal search`、`View call log`；失败期间不得继续发送新的远程内容。
- 语义索引构建失败：显示 `Semantic index could not be built.`，操作 `Retry index build`、`Use normal search`、`View call log`。
- 语义索引部分失败：显示可搜索的已完成数量、失败数量和 skipped 数量；提供 `Retry failed items`、`Use normal search`、`View call log`。
- 远程不可用：显示 `Remote semantic search is unavailable.`，不得自动切换 provider，操作 `Use normal search`、`Open AI settings`。
- 隐私规则排除的文件不进入远程语义查询；如本地索引也被规则限制，应显示跳过数量，并提供 `View privacy rule`。
- 相关度低时显示 `Low confidence results` 分组。
- 语义组和普通组分组展示，不做全局混排；如果用户只想看普通搜索，使用 `Use normal search` 切换到 Stage 2 普通搜索。
- normal search 请求失败：普通组显示 `Normal search results could not be loaded.`，操作 `Retry normal search`；语义组保持可用。
- semantic search 请求失败：语义组显示 `Semantic matches could not be loaded.`，操作 `Retry semantic search`、`Use normal search`；普通组保持可用。
- filters 同时过滤两组结果，不改变原始语义 query。
- 分页加载失败：按组显示 `More semantic matches could not be loaded.` 或 `More normal matches could not be loaded.`，操作 `Retry page`，已加载的另一组结果保持可用。
- 保存为 Smart List 时必须标记依赖 Semantic search 和索引状态。
- `Save...` 禁用条件：query 为空、语义搜索仍在加载、语义索引不可用、当前结果来自错误/回退状态，或当前用户没有保存搜索权限。
- `Save...` 打开 `S2-03 saved-search-sheet` 时传入 query、scope、filters、mode `Semantic`、semantic index dependency、provider scope、semantic sort、normal sort、dedupe policy 和分组展示策略；Cancel 后返回当前语义结果页，不改变 query、filters、sort、dedupe 或 page。
- 保存成功后返回当前语义结果页，并在侧边栏 Smart Lists 分组显示新条目；新条目必须标记 `Mode: Semantic`。
- 隐私跳过必须写入 S3-05 调用日志，sent fields 为 none。
- `Build semantic index` 前必须检查 AI 总开关、语义搜索功能开关、provider 状态、远程显式启用状态、usage scope、隐私规则和日志写入能力。
- Retry index build 只重试失败或缺失条目，不自动切换 provider；重试前重新检查隐私规则。

## 交互

1. 用户提交 query 后先检查 AI 和语义索引状态。
2. 状态可用时显示 `Searching semantically...`。
3. 结果返回后显示 `Semantic matches` 和 `Normal search matches` 两组；语义组按 relevance 排序，普通组沿用 Stage 2 排序。
4. 点击 `Use normal search` 用同一 query、scope 和可兼容 filters 回到 Stage 2 普通搜索。
5. 点击 `Why this matched` 展开解释。
6. 修改 filters 后同时刷新语义组和普通组，并显示两个分组的过滤后数量。
7. 点击重复项提示可展开或折叠被 dedupe 的普通搜索重复项。
8. 点击 `Save...` 进入 `S2-03 saved-search-sheet`，摘要中包含 `Mode: Semantic`、index dependency、provider scope、分组展示和 dedupe policy。
9. 在 `S2-03` 点击 Cancel 返回当前语义结果页；保存成功后 Smart List 出现在侧边栏并返回当前结果页。
10. 点击 `Build semantic index` 先打开 `Build semantic index?` 确认 sheet，并显示文件数、预计跳过数、provider、本地/远程、隐私规则检查结果、字段过滤结果和日志 gate 状态。
11. 在确认 sheet 中点击 `Start index build` 后才启动构建；点击 `Cancel` 或 `Back` 返回语义搜索页，不改变 query、filters、scope 或普通搜索结果。
12. 如果 gate 检查失败，`Start index build` 不可点击，用户只能选择对应恢复动作或 `Use normal search`；恢复动作返回后重新读取 gate 状态。
13. 点击 `Pause index build` 暂停本地队列或远程任务队列；点击 `Cancel index build` 弹确认，确认后停止后续处理，保留已提交的本地索引片段并清理未提交临时索引。
14. 点击 `Retry failed items` 只重试失败条目，并再次执行 provider 和隐私规则检查。
15. 点击 `View privacy rule` 打开命中的 S3-09 隐私规则，并定位到规则行。

## 可访问性

- 搜索模式、query、结果数量、相关度、低置信度分组和索引状态必须可被 VoiceOver 读出。
- 结果表格支持键盘选择；展开 `Why this matched` 后焦点进入解释区域，关闭后返回结果行。
- 索引构建进度以可读文本提供，不只依赖进度条；暂停、取消和重试按钮必须有禁用原因。
- 远程/本地、隐私跳过和低置信度不能只靠颜色表达。

## 数据与依赖

- Embedding / semantic index。
- Semantic search API。
- AI settings and provider status。
- Privacy rules gate。
- Search filter state。
- Semantic sort and pagination state。
- Normal search fallback result state。
- Per-group pagination state。
- Dedupe policy between semantic and normal results。
- Smart List persistence with semantic mode flag。
- Saved search route input for `S2-03`。
- Semantic index build status。
- AI call log id for search/skipped entries。
- Privacy rule match id。
- Semantic index build queue with pause/cancel/retry support。
- Provider status and remote semantic scope gate。
- Index build preview and partial failure result。
- Index build confirmation state。

## 验收清单

- 自然语言 query 能进入语义搜索模式。
- 语义模式复用 Stage 2 搜索容器，并以 `Semantic matches` / `Normal search matches` 两组方式合并展示，不做不可解释的单一混合分数。
- 同一文件同时命中语义和普通搜索时默认 dedupe 到语义组，并可展开查看普通搜索重复项。
- AI 不可用、索引未就绪、隐私规则跳过都有明确状态。
- 搜索中、无结果、索引构建中、索引失败、远程不可用都有明确状态。
- 索引构建默认本地；远程 embedding/index 只能在远程 AI 显式启用且 scope 允许后使用。
- 索引构建前显示 provider、文件数、跳过数和隐私 gate 结果。
- 索引构建前必须显示 `Build semantic index?` 确认 sheet，包含文件数、预计跳过数、provider、本地/远程、隐私规则、字段过滤和日志 gate 状态。
- `Start index build` 只在所有 gate 通过时可点击；gate 失败时只显示对应恢复动作和普通搜索回退。
- `Build semantic index?` 的 `Cancel` / `Back` 返回语义搜索页，不启动构建，也不改变 query、filters、scope 或普通搜索结果。
- 索引构建支持暂停、取消、失败重试和部分失败恢复；取消后不会继续发送远程内容。
- `Cancel index build` 的确认 sheet、Keep building、取消中、取消成功和取消失败状态明确可测。
- 取消构建后已提交的本地索引片段保留，未提交临时索引和未完成队列被清理，远程队列停止且不再发送内容。
- 取消构建后返回语义搜索页并显示 `Semantic index build canceled.`，仍可 `Use normal search`、`Retry index build` 和 `View call log`。
- 结果显示相关度和匹配理由。
- 可一键回普通搜索。
- filters 同时作用于语义组和普通组，不改变语义 query。
- 排序、分页、分页失败重试和普通搜索回退关系明确可测。
- 保存 Smart List 时标记语义依赖。
- `Save...` 控件、禁用条件、Cancel 返回、分组展示、dedupe policy 和保存成功路径都明确可测。
- 隐私规则跳过显示跳过数量，可跳转规则详情，并能在调用日志追溯 skipped 记录。
- VoiceOver 能读出模式、相关度和匹配理由。

## 来源

- 组合来源：[语义搜索任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-08-semantic-search.md)、[Stage 3 智能搜索](../../../roadmap/milestones.md#智能搜索)、[搜索 UX](../../search.md)。
- 依据现有文档推导：语义/普通搜索分组展示、dedupe policy、语义索引状态、Smart List semantic dependency 和隐私跳过追溯规则。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S2-03 保存搜索](../stage-2-experience/S2-03-saved-search-sheet.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
