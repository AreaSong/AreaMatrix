# S3-07 ai-tags-suggestion - 自动标签采纳 / 修改

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-07  
> 页面类型：AI 标签
> 页面文件：`S3-07-ai-tags-suggestion.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 标签。
- **建议目录**：`apps/macos/AreaMatrix/Features/AITags/AITagSuggestionView.swift`。
- **建议组件**：`AITagSuggestionView`、`SuggestedTagChip`、`TagSuggestionReviewSheet`。
- **实现说明**：本页固定实现为 `AITagSuggestionReviewSheet`，支持 single mode 和 batch mode。AI 自动标签默认是建议状态，用户采纳前不写入文件标签集合。

## 页面背景

AI 可以根据文件名、摘要、提取文本或现有标签建议新标签。用户需要逐个或批量采纳，也要能改名、合并到已有标签、拒绝建议。标签影响搜索和 Smart Lists，因此不能默默写入。

入口：文件详情 Tags 区、导入结果建议、批量 AI tags review。
退出：采纳后写入标签；修改后写入修正标签；拒绝后隐藏建议。

## 整体风格

本页是标签建议 review sheet，应该强调“先审阅、再写入”。single mode 保持轻量，batch mode 强调影响汇总和可回退的失败项。AI 来源、置信度、低置信度排除和远程/隐私状态必须以文字说明和徽标表达，避免只靠颜色或 chip 样式传达。

## 页面功能

- 显示 AI 建议标签 chips。
- 显示每个标签的置信度或理由。
- 支持采纳单个/全部高置信度标签。
- 支持编辑标签名。
- 支持合并到已有标签。
- 支持拒绝建议。
- 支持查看 AI 调用日志。

## 布局与内容

Sheet 标题：
- single mode：`Review suggested tags`
- batch mode：`Review suggested tags for 12 files`

顶部摘要：
- `Review before adding tags. AI suggestions are not applied until you accept them.`
- `Confidence threshold: 80%`
- 状态徽标：`Local` 或 `Remote`。

文件区域：
- single mode：显示文件名、当前位置、现有标签。
- batch mode：左侧文件列表，包含每个文件的建议数量和 pending/accepted/rejected 状态。

建议 chip：
- 标签名：`finance`
- 状态：`86%` 或 `Suggested`
- 操作：`+` 采纳、`×` 拒绝。

展开详情：
- `Reason: filename and summary mention invoice and payment.`
- `Matches existing tag: finance`
- `Used fields: filename, summary`

底部操作：
- `Accept high confidence`
- `Accept selected`
- `Reject selected`
- `Cancel`
- `View AI call`
- `View privacy rule`，仅隐私规则跳过时显示。

AI off 状态操作：
- 标题：`AI tag suggestions are off`
- 主按钮：`Open AI settings`
- 次按钮：`Close`
- 不显示可提交的 suggestion chips；如果已有已加载但未提交的本地 pending buffer，仅以只读摘要显示，`Accept high confidence`、`Accept selected`、`Reject selected` 和 `Apply tags` 全部禁用。

批量提交前影响汇总：
- `3 files will receive 8 tags.`
- `Low confidence tags are excluded.`
- `Existing tags will not be duplicated.`

Batch apply 确认 sheet：
- 标题：`Apply suggested tags to 3 files?`
- 说明：`AreaMatrix will add 8 reviewed tags. Low confidence tags are excluded, and existing tags will not be duplicated.`
- 明细：文件数、将新增的 tag 数、被排除的低置信标签数、重复标签数。
- 主按钮：`Apply tags`
- 次按钮：`Cancel`
- 确认前不写入任何 batch tag；取消后返回 review sheet 并保留 pending selection。

采纳语义：
- single mode：点击 `+`、`Accept selected` 或 `Accept high confidence` 会立即写入当前文件正式 Tags 区；成功后 chip 状态变为 `Accepted`。
- batch mode：点击 `+`、`Reject selected` 或编辑标签只更新待提交选择，不写入正式标签；必须在批量影响汇总中确认后才写入。
- `Cancel` 只丢弃尚未提交的 pending 选择；已经在 single mode 或 batch 确认中成功写入的标签不回滚。

## 状态与规则

- AI 未启用：固定显示 `AI tag suggestions are off`，主操作 `Open AI settings`，次操作 `Close`；不读取、不生成 AI 标签建议，不显示可交互 suggestion chips。
- AI 未启用但存在已加载且未提交的本地 pending buffer：只显示 pending 数量和文件范围的只读摘要，不允许提交、拒绝、编辑或批量应用；用户只能 `Open AI settings` 或 `Close`。
- 加载中：显示 `Loading suggested tags...`，底部提交按钮禁用。
- 无建议：显示 `No tag suggestions for this file.`，可关闭 sheet。
- 生成建议前必须校验 AI 总开关、`Auto tags` 功能开关、provider 状态、远程显式启用、usage scope、隐私规则和调用日志写入能力。
- 如果唯一可用 provider 是远程 provider，本页不得直接启用远程 AI；必须引导到 S3-03，取消后返回本页并保持未生成状态。
- 隐私规则命中前不得发起远程标签调用；命中后写入 S3-05 skipped 记录，sent fields 为 none。
- 隐私规则命中：显示 `Skipped by privacy rule`，提供 `View privacy rule` 和 `View AI call`。
- 生成失败：进入 `S3-10 ai-fallback`，保留手动加标签入口。
- 标签已存在于文件：显示为 already applied，不重复写入。
- 建议标签与现有标签大小写或拼写相近：优先提示合并到已有标签。
- 编辑标签名必须复用 Stage 2 tag registry 命名校验；空值、非法字符、超过长度限制或保留名称时显示 inline error，并禁用 `Accept selected` / `Apply tags`。
- 与已有标签完全相同但尚未应用到文件时，显示 `Will use existing tag`；已经应用到文件时显示 `Already applied`，不重复写入。
- 与已有标签相近时，默认显示 `Merge with existing tag` 建议；用户选择新建相近标签前必须显式确认，避免制造重复标签。
- batch mode 中存在无效标签名或未处理合并冲突时，批量确认 sheet 不可提交，并在影响汇总中列出阻塞项。
- 低置信度标签默认不包含在 `Accept high confidence` 中。
- 拒绝建议不删除已有标签，只隐藏该建议并记录反馈。
- `Accept high confidence` 只采纳当前 confidence threshold 及以上的标签；阈值来自设置，当前页面只读显示。
- single mode 中 `Accept selected` 在点击后立即写入选中标签；写入中按钮禁用并显示 `Applying tags...`。
- batch mode 中 `Accept selected` 必须先显示影响汇总确认；确认前不写入任何文件标签。
- 写入失败时显示 `Tags could not be applied.`，已成功写入的标签保持，失败项保留 pending 并提供 `Retry apply`。
- batch mode 部分失败时，结果区必须列出成功文件数、失败文件数、无效标签数、重复标签数和失败原因；成功写入不回滚，失败项保留 pending。
- Cancel 关闭 sheet，不写入 pending 建议；已经成功写入的标签不回滚。

## 交互

1. 打开 sheet 时先读取 AI settings 和 `Auto tags` 功能开关；如果 AI 未启用或 `Auto tags` 关闭，进入 AI off 状态，不读取或生成新建议。
2. AI off 状态只可使用已在内存中的本地 pending buffer 显示只读摘要；点击 `Open AI settings` 进入 S3-01，点击 `Close` 关闭 sheet，二者都不写入 pending 标签。
3. AI 已启用时读取已有 pending suggestion；如果需要生成新建议，先执行 provider、feature scope、privacy gate 和日志能力检查。
4. 建议生成后以 chips 显示，不自动写入。
5. single mode 中点击 `+` 采纳单个标签，并立即出现在正式 Tags 区。
6. batch mode 中点击 `+` 只把该标签加入 pending selection，并更新批量影响汇总。
7. 点击标签文字进入编辑，可改名或选择已有标签；single mode 编辑后采纳才写入，batch mode 编辑后仍停留在 pending selection。
8. 点击 `Accept high confidence` 只采纳超过阈值的标签；single mode 立即写入，batch mode 进入批量影响确认。
9. 点击 `View AI call` 打开日志详情。
10. 批量 review 中切换文件时保留已做选择，提交前汇总影响数量。
11. 点击 `Accept selected` 时，single mode 立即写入选中标签；batch mode 先显示批量影响确认 sheet，确认后才写入正式标签。
12. 点击 `View privacy rule` 打开命中的 S3-09 隐私规则，并定位到规则行。
13. 点击 `Cancel` 或 AI off 状态的 `Close` 丢弃未提交选择；已提交的标签不回滚，不写入 pending 标签。

## 可访问性

- chip 必须提供标签名、置信度、状态和采纳/拒绝动作的可读 label；`+` 和 `×` 不能是唯一可读名称。
- single/batch 模式、远程/本地来源、低置信度排除和隐私跳过必须用文字或徽标表达。
- batch 文件列表和建议区支持键盘切换，切换文件后焦点落到当前文件的第一个 pending suggestion。
- 批量确认和部分失败结果必须可被 VoiceOver 读出，取消确认后焦点回到 `Accept selected`。

## 数据与依赖

- AI tag suggestion API。
- Tag registry and merge suggestions。
- Tag write API。
- Confidence threshold。
- Privacy rules gate。
- AI call log id。
- Privacy rule match id。
- Batch apply preview and result model。
- Pending tag selection buffer。
- Provider status and feature scope gate。
- Batch apply confirmation state。
- Tag name validation and conflict resolver。

## 验收清单

- 建议标签在用户采纳前不写入正式标签。
- single mode 的采纳动作会立即写入当前文件标签；batch mode 在影响汇总确认前不会写入。
- Cancel 只丢弃 pending 选择，不回滚已经成功写入的标签。
- AI off 状态固定显示 `AI tag suggestions are off`、`Open AI settings` 和 `Close`；不会读取或生成新建议，也不会提交 pending 标签。
- 生成建议前会校验 AI 总开关、功能开关、provider、远程显式启用和隐私规则。
- 已存在标签不会重复添加。
- 低置信度标签不会被 Accept high confidence 默认采纳。
- 用户能编辑标签名或合并到已有标签。
- 标签命名校验、重复标签、相近标签合并和批量阻塞项都有明确 UI。
- 隐私规则命中时明确跳过。
- 隐私规则命中可跳转规则详情，并能在调用日志追溯 skipped 记录。
- 加载、无建议、AI off、隐私跳过、写入失败和批量提交前汇总都有明确 UI。
- 批量模式提交前展示影响文件数和标签数，并通过确认 sheet 才写入；部分失败有成功/失败数量和重试入口。
- VoiceOver 能读出建议、置信度、采纳/拒绝按钮。

## 来源

- 组合来源：[AI 标签建议任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-07-ai-tags-suggestion.md)、[Stage 3 自动标签](../../../roadmap/milestones.md#自动标签)、[Stage 2 标签规格](../stage-2-experience/S2-07-tags-add.md)。
- 依据现有文档推导：`AITagSuggestionReviewSheet` 的 single/batch mode、confidence threshold、批量影响汇总和隐私跳过追溯规则。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [S2-07 添加标签](../stage-2-experience/S2-07-tags-add.md)
- [逐页 UI 开发规格索引](../README.md)
