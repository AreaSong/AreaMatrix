# S3-06 ai-summary-editor - 自动摘要编辑 / 清除

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-06  
> 页面类型：AI 摘要
> 页面文件：`S3-06-ai-summary-editor.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 摘要。
- **建议目录**：`apps/macos/AreaMatrix/Features/AISummary/AISummaryEditor.swift`。
- **建议组件**：`AISummaryEditor`、`SummaryProvenanceBadge`、`SummaryRegenerateControls`。
- **实现说明**：自动摘要是可编辑的派生内容。生成结果默认先进入草稿态，用户点击 `Save` 前不写入正式摘要；不得覆盖用户 Note，也不得写入用户原文件。

## 页面背景

用户希望 AreaMatrix 为文件生成简短摘要，方便浏览和搜索。但 AI 摘要可能不准确，用户必须能看到来源、编辑、重新生成或清除。摘要不能替代用户笔记，也不能污染原文件。

入口：文件详情 Summary 区、AI 设置启用摘要后首次生成、语义搜索结果详情。
退出：保存摘要、清除摘要、重新生成、返回详情。

## 整体风格

本页是文件详情中的派生内容编辑区，视觉上必须和用户 Note 明确分开。摘要来源、草稿状态和远程/本地标记要紧贴编辑区显示；不要把 AI 摘要呈现为不可质疑的最终描述，也不要把重新生成做成无确认的快捷动作。

## 页面功能

- 显示当前 AI 摘要。
- 显示摘要来源：本地/远程、生成时间、模型。
- 支持编辑摘要。
- 支持重新生成。
- 支持清除摘要。
- 显示隐私规则跳过状态。
- 显示摘要保存状态。

## 布局与内容

在文件详情中作为 `Summary` 卡片或 tab。

标题：`AI Summary`

状态徽标：
- `Draft`
- `Generated locally`
- `Generated remotely`
- `Edited by you`
- `Unsaved changes`
- `Skipped by privacy rule`

摘要编辑区：
- 多行文本框。
- 占位：`No AI summary yet.`
- 字数/长度提示：`436 characters`

来源信息：
- `Generated: Apr 29, 2026 11:30`
- `Model: Local classifier v1` 或远程 provider。
- `Used fields: extracted text, filename`

按钮：
- `Generate summary`
- `Regenerate...`
- `Cancel generation`，仅生成中显示。
- `Save`
- `Discard changes`
- `Clear summary...`
- `View AI call`
- `View privacy rule`，仅隐私规则跳过时显示。

Clear summary 确认 sheet：
- 标题：`Clear AI summary?`
- 说明：`This clears the AI-derived summary for this file. It will not delete your note, original file, extracted text, tags, or AI call log.`
- 危险按钮：`Clear summary`
- 次按钮：`Cancel`
- 清除成功后编辑区回到 `No AI summary yet.`，来源信息隐藏。

Regenerate 确认 sheet：
- 标题：`Regenerate AI summary?`
- 说明：`This replaces the current draft or unsaved edits with a new AI-generated draft. Saved notes and the original file will not be changed.`
- 主按钮：`Regenerate`
- 次按钮：`Cancel`
- 确认前不发起新 AI 调用；取消后保留当前草稿或未保存编辑。

## 状态与规则

- AI 未启用：显示 `AI summaries are off` 和 `Open AI settings`。
- 加载中：显示 `Loading summary...`，编辑区禁用，保留返回详情入口。
- 无摘要：显示占位 `No AI summary yet.`，主按钮 `Generate summary`。
- 生成摘要前必须校验 AI 总开关、`Auto summaries` 功能开关、provider 状态、远程显式启用、usage scope、隐私规则和调用日志写入能力。
- 如果唯一可用 provider 是远程 provider，本页不得直接启用远程 AI；必须引导到 S3-03，取消后返回本页并保持未生成状态。
- 隐私规则命中前不得发起远程摘要调用；命中后写入 S3-05 skipped 记录，sent fields 为 none。
- `Generate summary` 禁用条件：AI 总开关关闭、Auto summaries 关闭、provider 不可用、远程 scope 未允许、隐私规则命中、缺少可用输入字段或调用日志不可写。
- `Regenerate...` 在确认前也必须执行同一组 gate 检查；确认后如 gate 失败，不得丢弃当前草稿或已保存摘要。
- 生成中：显示 `Generating...`，`Save` 禁用，`Cancel generation` 可停止任务且不写入摘要。
- 取消生成：停止当前生成任务，不写入正式摘要；若已有已保存摘要则恢复已保存内容，若仅有空草稿则回到无摘要状态。
- 生成失败：进入 `S3-10 ai-fallback`，并保留手动编辑入口。
- 隐私规则命中：显示跳过说明，不提供远程生成；提供 `View privacy rule` 和 `View AI call`。本地是否允许按规则配置显示为明确 allow/skip。
- 生成完成后状态为 `Draft`，摘要填入编辑框但不写入正式摘要；用户点击 `Save` 后才保存。
- 用户编辑后状态变为 dirty，离开前必须提示 `Save changes`、`Discard changes`、`Cancel`。
- `Save` 禁用条件：没有草稿或未保存改动、正在加载、正在生成、正在保存、摘要内容为空且当前没有可清除摘要。
- 保存中：显示 `Saving summary...`，编辑区和 `Regenerate...`、`Clear summary...` 禁用，保留 `Cancel` 返回提示但不丢草稿。
- 保存失败：显示 inline error `Summary could not be saved.`，草稿内容必须保留，操作为 `Retry save`、`Discard changes`、`Back to detail`。
- Regenerate 会覆盖当前草稿或已编辑摘要，需要确认；确认前不发起新调用，取消后不得丢失当前草稿。
- Clear summary 需要确认，只清除摘要，不清除用户 Note 或原文件。
- 清除中：显示 `Clearing summary...`，编辑区和生成按钮禁用。
- 清除失败：显示 `Summary could not be cleared.`，保留原已保存摘要和来源信息，操作为 `Retry clear`、`Cancel`。
- 远程生成必须经过远程 AI 显式启用和隐私规则 gate。
- 清除摘要只删除 AI 派生摘要，不删除 Note、原文件、提取文本、标签或调用日志。

## 交互

1. 打开详情时加载摘要 metadata 和内容。
2. 点击 `Generate summary` 先执行 AI settings、provider、feature scope、privacy gate 和日志能力检查；通过后才触发 AI 任务并显示 `Generating...`。
3. 生成完成后摘要填入编辑框，状态为 `Draft`；用户点击 `Save` 前不写入正式摘要。
4. 用户编辑内容后 `Save` 启用。
5. 点击 `Save` 进入保存中；成功后状态从 `Draft` 或 `Unsaved changes` 变为已保存，失败时保留草稿并显示重试。
6. 点击 `Cancel generation` 停止当前生成任务，不写入摘要，并恢复生成前内容。
7. 点击 `Regenerate...` 弹确认；确认后再次执行 gate 检查，通过后才重新调用 AI。
8. 点击 `Clear summary...` 弹确认并清除派生摘要；失败时保留原摘要。
9. 点击 `Discard changes` 放弃当前草稿或未保存编辑，恢复为上一次已保存摘要。
10. 点击 `View privacy rule` 打开命中的 S3-09 隐私规则，并定位到规则行。
11. 离开详情或切换文件时如果 dirty，必须显示保存/放弃/取消提示。

## 可访问性

- 编辑区、状态徽标、来源信息和保存状态必须有可读 label；`Draft`、`Unsaved changes`、`Generated remotely` 不能只靠颜色表达。
- 键盘用户可完成生成、编辑、保存、放弃、清除和查看日志/隐私规则。
- 离开 dirty 状态确认、Regenerate 确认和 Clear 确认默认焦点在安全的 `Cancel`。
- 生成、保存、清除中的状态变化要向辅助技术公告，但不能重复朗读完整摘要内容。

## 数据与依赖

- Summary store，位于 AreaMatrix metadata，不写入原文件。
- AI summary generation API。
- Privacy rules gate。
- AI call log id。
- Dirty state and save API。
- File extracted text availability。
- Privacy rule match id。
- Draft summary buffer。
- Cancellable generation task。
- Summary save/clear mutation result。
- Regenerate confirmation state。
- Provider status and feature scope gate。

## 验收清单

- 摘要与用户 Note 明确分开。
- 生成结果默认是草稿，点击 Save 前不写入正式摘要。
- 清除摘要不会删除 Note 或原文件。
- 清除摘要不会删除提取文本、标签或调用日志。
- 保存中、保存失败、清除中、清除失败都有明确 UI 和恢复动作。
- 保存失败时草稿不丢失；清除失败时原已保存摘要不丢失。
- 取消生成不会写入正式摘要。
- Generate / Regenerate 前会校验 AI 总开关、功能开关、provider、远程显式启用、usage scope、隐私规则和调用日志写入能力。
- 编辑后离开有保存/放弃提示。
- Regenerate 覆盖草稿或用户编辑内容前需要确认；取消后草稿不丢失且不发起调用。
- 隐私规则命中可跳转规则详情，并能在调用日志追溯 skipped 记录。
- 远程摘要显示远程标记并可追溯到调用日志。
- VoiceOver 能读出摘要状态、来源和保存状态。

## 来源

- 组合来源：[AI 摘要任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-16-s3-06-ai-summary-editor.md)、[Stage 1 Detail Note 规格](../stage-1-mvp/S1-14-detail-note.md)。
- 依据现有文档推导：摘要草稿、保存确认、清除摘要和隐私跳过追溯规则，遵守 AI 派生内容不覆盖用户 Note 或原文件的边界。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
