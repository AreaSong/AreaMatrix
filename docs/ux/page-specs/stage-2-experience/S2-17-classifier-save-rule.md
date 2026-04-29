# S2-17 classifier-save-rule - 纠错并沉淀规则

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-17
> 页面类型：自定义分类
> 页面文件：`S2-17-classifier-save-rule.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 分类规则 UI。
- **建议目录**：`apps/macos/AreaMatrix/Features/Classifier/SaveClassifierRuleSheet.swift`。
- **建议组件**：`SaveClassifierRuleSheet`、`RuleBasisPicker`、`RulePreviewCard`。
- **实现说明**：从快速纠错进入，用来把“这一次改对”沉淀成未来规则；保存前必须校验规则是否过宽或重复。

## 页面背景

用户不仅想改当前文件，还希望以后类似文件自动归入正确分类。规则沉淀如果过宽，会影响大量导入或重分类，因此页面要让用户看懂规则依据，并主动引导到影响预览。

入口：`S2-16 classifier-correct` 勾选 `Remember this correction as a rule`；导入结果中点击 `Always classify like this`。
退出：保存规则后返回来源页面；预览影响进入 `S2-18`; 取消不保存规则。

## 页面功能

- 显示当前文件、当前分类和目标分类。
- 选择规则依据：扩展名、文件名关键词。
- 显示规则自然语言预览。
- 校验规则是否重复、过宽或无效。
- 保存到分类规则配置。
- 提供影响预览。

## 布局与内容

Sheet 标题：`Remember this classification rule?`

文件摘要：
- `File: 合同.pdf`
- `Correct category: finance/contracts`
- `Source: ~/Downloads/客户A/合同.pdf`

规则依据：
- checkbox `File name contains: 合同`
- checkbox `Extension is: .pdf`
- checkbox `File name contains: 客户A`

候选来源说明：
- 关键词候选可以从文件名、相对路径和来源目录中提取，但保存到 `classifier.yaml` 时只能写入 `keywords`。
- 来源目录和路径片段只作为“为什么推荐这个关键词”的解释，不作为 `path` 或 `source_folder` 规则写入。
- 扩展名 UI 可显示 `.pdf`，写入 `classifier.yaml` 时必须保存为无点小写 `pdf`。
- Priority 字段默认 `0`，范围 `-1000..1000`，越大越优先。

规则预览：
`When file name contains “合同” and extension is “pdf”, classify as finance/contracts with priority 0.`

风险提示：
- 只选 `.pdf` 时：`This rule may affect many documents.`
- 重复规则：`A similar rule already exists.`

底部按钮：
- `Cancel`
- `Preview impact`
- 主按钮 `Save rule`

## 状态与规则

- 默认态：显示候选规则依据、规则预览、风险提示和 Save/Preview 操作。
- 禁用态：未选依据、重复规则、校验失败或过宽但未预览时禁用 Save。
- 加载态：生成候选依据或检测重复规则时显示 `Preparing rule...`。
- 空态：无法从当前文件提取候选依据时显示 `No safe rule suggestion`，用户可进入规则编辑器手动创建。
- 错误态：规则校验或写入失败时显示字段级错误，不写配置。
- 恢复态：保存失败保留当前选择；Preview Back 后恢复草稿。
- 未选择任何规则依据时禁用 Save。
- 规则过宽时显示 warning；只选扩展名或 dry-run 影响超过阈值时，必须先进入 `S2-18 classifier-impact-preview` 后才能 Save。
- 重复规则默认禁用 Save，提供 `Open existing rule`。
- classifier 配置校验失败时不写入，显示错误。
- 保存规则只影响未来分类；是否重分类现有文件由影响预览页决定。
- 保存失败必须保留用户当前选择。
- 阈值默认：影响超过 25 个现有文件或超过当前资料库 10% 时视为过宽；实现可配置但 UI 必须显示实际影响数量。
- 只选扩展名规则默认不允许直接 Save；用户必须 Preview impact 并确认 `Save rule only` 或 `Save and apply`。
- Preview impact 返回后保留规则草稿和 warning 状态。
- 本页不得引入 `path`、`source_folder` 或独立 rule `enabled` 字段；写入内容必须能映射到当前 `classifier.yaml` 的 `extensions`、`keywords`、`priority` 和目标 category。
- UI 中扩展名包含点仅用于可读性；保存、校验和重复检测都按无点小写值处理。
- 多个关键词保存为目标分类的 `keywords` 列表追加项；多个扩展名保存为目标分类的 `extensions` 列表追加项。

## 交互

1. 打开 sheet 时根据当前文件生成候选依据：extension 和若干 keyword 候选。
2. 用户勾选/取消依据时实时更新规则预览和风险提示。
3. 点击 `Preview impact` 进入影响预览，并携带当前规则草稿。
4. 点击 `Save rule` 只保存规则，不重分类现有文件。
5. 保存成功后显示 toast `Classification rule saved`。
6. 如果保存失败，定位到失败字段或配置错误。
7. 点击 Cancel 不写 classifier 配置，不影响当前文件分类。

## 数据与依赖

- Current file classification evidence。
- Rule draft generator。
- Rule validator。
- Duplicate/similar rule detector。
- classifier.yaml writer or rules store。
- Rule impact dry-run entry。
- classifier.yaml schema fields：extensions、keywords、priority、category slug。

## 验收清单

- 可以从纠错生成规则草稿。
- 用户能看到规则依据和自然语言预览。
- 规则依据只保存为 classifier.yaml 支持的 extensions、keywords、priority 和目标 category。
- UI 扩展名 `.pdf` 保存为 `pdf`，不会写入带点扩展名。
- 来源目录和路径只作为关键词候选解释，不写入 path/source_folder 字段。
- Priority 默认 0，范围 -1000..1000。
- 过宽规则有 warning，重复规则不能误保存。
- Save rule 不重分类现有文件。
- Preview impact 能带入当前草稿。
- 保存失败可恢复上次有效配置。
- VoiceOver 能读出每个规则依据的选中状态和 warning。
- 扩展名规则和超过阈值的规则必须先预览影响。

## 来源

- `docs/ux/classifier-calibration.md#核心交互-2纠错并沉淀规则以后都这样`（直接来源）。
- `docs/ux/settings-panel.md#tab分类规则classifier`（组合来源）。
- 过宽阈值策略依据 Stage 2 安全边界推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-16 classifier-correct](S2-16-classifier-correct.md)
- [S2-18 classifier-impact-preview](S2-18-classifier-impact-preview.md)
- [S2-19 classifier-rule-editor](S2-19-classifier-rule-editor.md)
