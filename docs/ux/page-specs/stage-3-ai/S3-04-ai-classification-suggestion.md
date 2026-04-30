# S3-04 ai-classification-suggestion - AI 分类建议确认

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-04
> 页面类型：AI 分类  
> 页面文件：`S3-04-ai-classification-suggestion.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 分类建议。
- **建议目录**：`apps/macos/AreaMatrix/Features/AIClassification/AIClassificationSuggestionView.swift`。
- **建议组件**：`AIClassificationSuggestionView`、`AISuggestionConfidenceBadge`、`ClassificationApplyControls`。
- **实现说明**：本页固定实现为 `AIClassificationSuggestionPanel`。它可以嵌入 Detail 分类卡、导入结果 row 或批量 review 列表，但结构、字段、按钮和状态语义保持一致。AI 只给建议，用户确认前不移动文件、不改分类。

## 页面背景

Stage 1/2 的规则分类可能无法处理模糊文件。Stage 3 可以基于文件名、路径、摘要或本地模型给出分类建议。AI 分类默认只在规则分类失败或低置信度时介入，不替代已有规则的明确结果。用户需要看到建议来源和置信度，并决定采纳、修改或拒绝。

入口：导入结果中的 `Review AI suggestion`、文件详情分类区域、批量待分类列表。
退出：采纳后更新分类并可选移动文件；修改后进入分类纠错；拒绝后记录反馈。

## 整体风格

作为嵌入式确认 panel，本页要像审阅工具而不是推荐引擎。目标分类、置信度、理由、使用字段和目标路径预览必须同屏可见；低置信度、隐私跳过和失败状态用明确文本表达，避免把 AI 建议视觉上包装成最终决定。

## 页面功能

- 显示文件当前分类和 AI 建议分类。
- 显示置信度和建议理由。
- 显示使用的数据范围：文件名、扩展名、摘要、文本片段等。
- 支持 `Accept`、`Change...`、`Reject`。
- 支持“以后类似文件这样处理”进入规则沉淀。
- 支持查看 AI 调用日志条目。
- 支持用户手动请求 AI 建议，但请求前必须经过 AI 设置、provider 状态和隐私规则 gate。

## 布局与内容

`AIClassificationSuggestionPanel` 是一个可嵌入 panel。宿主只决定外层宽度和返回位置，不改变内部交互。

标题：`AI suggested a category`

文件摘要：
- 文件名。
- 当前分类。
- 当前位置。

建议卡：
- `Suggested category: Finance / Invoices`
- `Confidence: 86%`
- `Reason: filename and extracted text mention invoice and payment.`
- `Used: filename, extension, text excerpt`。

操作：
- `Accept`
- `Change...`
- `Reject`
- `Ask AI for suggestion...`，仅无建议且当前规则结果失败或低置信度时显示。
- checkbox `Create rule from this correction`，默认关闭。
- 链接 `View AI call`
- 链接 `View privacy rule`，仅隐私规则跳过时显示。

目标路径预览：
- `Current path: inbox/contract.pdf`
- `Target path: finance/contracts/contract.pdf`
- `No files will be moved until you confirm.`

移动确认 sheet：
- 标题：`Apply AI category?`
- 说明：`AreaMatrix will update the category and move the file to the target folder. Existing user files will not be overwritten.`
- 主按钮：`Apply category`
- 次按钮：`Cancel`
- 风险说明：显示目标路径、已有同名文件处理方式和失败后保持原位置。

规则沉淀路径：
- 勾选 `Create rule from this correction` 后，用户点击 `Accept` 并完成必要的移动确认后，进入 `S2-17 classifier-save-rule`。
- `S2-17` 的入口上下文必须包含原文件、AI 建议分类、用户最终确认分类、confidence、AI reason 和候选 rule basis。
- 在 `S2-17` 点击 `Preview impact` 进入 `S2-18 classifier-impact-preview`。
- `S2-17` Cancel 返回本 panel，分类采纳结果保持已完成，规则不保存；若用户还未确认移动/分类，则 Cancel 返回本 panel 且不写入任何变更。
- `S2-18` Back 返回 `S2-17` 并保留规则草稿；`S2-18` Cancel 关闭规则沉淀流程并返回本 panel，不撤销已采纳分类。
- `S2-17` 保存成功或 `S2-18` 保存/应用成功后返回本 panel，显示 `Rule saved for future imports`，并保留 `View AI call`。

## 状态与规则

- AI 建议生成门槛：规则分类失败、规则结果进入 inbox、或规则 confidence 低于阈值；高置信度规则结果不自动触发 AI。
- 用户手动点击 `Ask AI for suggestion...` 时，也必须先校验 AI 总开关、功能开关、provider 可用性和隐私规则；不满足时显示 `Open AI settings`、`View local model status` 或非 AI 回退。
- 若远程 provider 是唯一可用 provider，手动请求前必须确认远程 AI 已显式启用；不得从本页直接启用远程 AI。
- 加载中：显示 `Loading AI suggestion...`，`Accept`、`Change...`、`Reject` 禁用，`View AI call` 仅在已有 call id 时可用。
- 无建议：显示 `No AI category suggestion is available.`，主操作 `Classify manually`。
- AI 未启用：显示 `AI classification suggestions are off`，主操作 `Open AI settings`，次操作 `Classify manually`。
- 置信度低于阈值时显示 `Low confidence`，默认不高亮 Accept。
- 隐私规则命中时不显示建议，改为 `Skipped by privacy rule`，提供 `View privacy rule` 和 `View AI call`。
- AI 失败时进入 `S3-10 ai-fallback`。
- Accept 前只显示目标分类和目标路径预览，不修改分类、不移动文件。
- 如果当前分类设置会移动原文件，Accept 后必须先显示移动确认 sheet；用户确认前不写入分类、不移动文件。
- 如果应用设置为 index-only 分类更新，Accept 后仍要显示将更新的分类和 change log 影响，再执行分类更新。
- 移动或分类更新失败时，文件保持原位置和原分类，panel 显示恢复动作 `Retry apply`、`Classify manually`、`View call log`。
- `Accept` 禁用条件：suggestion 仍在加载、缺少目标分类、隐私规则命中、AI 失败、目标路径预览失败或存在未处理同名冲突。
- Reject 不删除文件，不影响现有分类。
- 批量场景中不允许一键采纳低置信度建议，除非用户显式选择。
- AI 建议不得覆盖用户已有规则；勾选 `Create rule from this correction` 后必须进入 `S2-17 classifier-save-rule`，过宽或需预览时再进入 `S2-18 classifier-impact-preview`。

## 交互

1. 页面加载后显示 pending 或已有 suggestion。
2. 若没有 pending suggestion，页面根据规则分类结果决定是否显示 `Ask AI for suggestion...`。
3. 点击 `Ask AI for suggestion...` 后先校验 AI settings、provider status、privacy rules 和 feature scope；通过后才创建 AI 调用。
4. 点击 `Accept` 后先显示目标分类和目标路径预览；若会移动文件，弹移动确认 sheet。
5. 点击 `Change...` 打开分类选择，可修改 AI 建议。
6. 点击 `Reject` 记录反馈并隐藏该建议。
7. 勾选创建规则时，采纳后进入 `S2-17 classifier-save-rule`；用户在 `S2-17` 点击 Preview impact 时进入 `S2-18 classifier-impact-preview`。
8. 点击 `View AI call` 打开调用日志详情，显示本次调用是否本地/远程。
9. 点击 `View privacy rule` 打开命中的 S3-09 隐私规则，并定位到规则行。
10. 移动确认取消后，panel 回到建议状态，不写入任何变更。

## 可访问性

- panel 内部焦点顺序为文件摘要、建议卡、目标路径预览、主/次操作、日志和隐私链接。
- VoiceOver 必须读出建议分类、当前分类、confidence、低置信度提示、禁用原因和目标路径变化。
- `Accept`、`Change...`、`Reject` 可通过键盘触发；移动确认取消后焦点返回 `Accept`。
- 置信度和远程/本地来源不能只用颜色表达，必须有文字或徽标。

## 数据与依赖

- AI classification suggestion API。
- Rule classification result and confidence。
- Confidence threshold setting。
- Privacy rules gate。
- Classification update API。
- Rule suggestion/impact preview。
- S2-17 classifier-save-rule route input。
- S2-18 classifier-impact-preview route input。
- AI call log id。
- Privacy rule match id。
- File move/category apply preview API。
- Non-overwrite conflict policy。

## 验收清单

- 用户确认前不会改分类或移动文件。
- AI 分类建议只在规则失败、inbox 兜底或低置信度时自动生成。
- 手动请求 AI 建议前会校验 AI 设置、provider 状态和隐私规则，不会绕过远程显式启用。
- 加载中、无建议、AI off、隐私跳过、预览失败和写入失败都有明确状态。
- Accept 禁用条件可见，并和对应控件关联。
- Accept 会移动原文件时必须先展示目标路径和确认 sheet。
- 移动或分类更新失败后文件和分类保持原状态，并有恢复动作。
- 建议卡显示分类、置信度、理由和使用字段。
- 隐私规则命中时明确跳过。
- 隐私规则命中可跳转规则详情，并能在调用日志追溯 skipped 记录。
- 低置信度建议不会被视觉上当作强推荐。
- Accept/Change/Reject 都有可验证结果。
- `Create rule from this correction` 的 S2-17/S2-18 跳转、Back、Cancel 和成功返回路径明确可测。
- 远程建议能从日志中追溯到 provider。

## 来源

- 组合来源：[AI 分类建议任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-14-s3-04-ai-classification-suggestion.md)、[分类器调教](../../classifier-calibration.md)。
- 依据现有文档推导：AI 建议确认、目标路径预览、移动确认、隐私跳过追溯和失败恢复规则，遵守“用户确认前不改分类/不移动文件”的高风险边界。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [S2-16 分类纠错](../stage-2-experience/S2-16-classifier-correct.md)
- [S2-17 纠错并沉淀规则](../stage-2-experience/S2-17-classifier-save-rule.md)
- [S2-18 规则影响预览](../stage-2-experience/S2-18-classifier-impact-preview.md)
- [逐页 UI 开发规格索引](../README.md)
