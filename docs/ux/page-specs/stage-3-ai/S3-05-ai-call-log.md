# S3-05 ai-call-log - AI 调用日志

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-05
> 页面类型：AI 日志  
> 页面文件：`S3-05-ai-call-log.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 调用日志。
- **建议目录**：`apps/macos/AreaMatrix/Features/AI/AICallLogView.swift`。
- **建议组件**：`AICallLogView`、`AICallLogTable`、`AICallDetailView`、`RedactedLogExportSheet`。
- **实现说明**：日志用于透明可控，默认不展示敏感全文。远程调用必须可识别。

## 页面背景

用户启用 AI 后，需要知道 AreaMatrix 何时调用了 AI、调用了哪个模型、是否远程、发送了哪些字段类型、结果如何。这个页面既是隐私透明工具，也是排查失败的诊断入口。

入口：AI 设置页 `View AI call log`；AI 建议卡 `View AI call`；AI 失败提示 `Open call details`。
退出：关闭日志、打开某条记录详情、导出脱敏日志、清除日志。

## 整体风格

本页是隐私透明和诊断页面，采用可扫描的表格和详情分栏。默认只显示字段类型、状态和脱敏摘要，不展示完整 prompt、完整输出、API key 或文件正文。远程、失败、跳过状态必须使用文字徽标和列值表达，颜色只作辅助。

## 页面功能

- 列出 AI 调用记录。
- 按功能、本地/远程、provider、状态、日期过滤。
- 显示调用详情。
- 标记远程调用和隐私规则跳过记录。
- 支持导出脱敏日志。
- 支持清除日志或删除选中记录。
- 提供从记录跳转到相关文件的入口。

## 布局与内容

标题：`AI Call Log`

过滤器栏：
- `Feature`: All / Classification / Summary / Tags / Semantic Search / Provider Test。
- `Provider`: All / Local / Remote。
- `Status`: Success / Failed / Skipped。
- `Date range`。
- 搜索框：按文件名、provider、错误码搜索。

表格列：
- `Time`
- `Feature`
- `Provider`
- `Remote` 标记。
- `Scope`
- `Status`
- `Duration`
- `Result`

详情区：
- `File or batch`: 文件名、批次 ID；Provider Test 记录固定显示 `None`。
- `Provider`: Local model / Remote provider。
- `Model`: 模型名。
- `Sent fields`: filename, repo-relative path, extension, extracted text excerpt, AI summary, note summary, tag/category context；Provider Test 记录固定显示 `none`。
- `note summary` 是用户 Note 的派生摘要，只记录字段类型，不显示完整 Note 原文。
- `Privacy rules checked`: yes/no，命中时显示规则名。
- `Privacy match`: rule id/name、pattern、applies to、matched field type。
- `Result summary`: 分类、摘要、标签、搜索索引结果或 provider verification 结果。
- `Error`: 错误码和可读说明。
- `Raw prompt`: 默认隐藏；如提供查看必须脱敏并二次确认。

Provider Test 详情语义：
- `Feature`: `Provider Test`
- `Scope`: `Provider verification`
- `File or batch`: `None`
- `Sent fields`: `none`
- `Privacy rules checked`: `no user content`
- `Result summary`: `Connection verified`、`Connection failed` 或 provider 可用性检查的脱敏摘要。
- 不显示 `Raw prompt` 入口；连接测试不是文件级 AI 调用，不存在可查看 prompt。

操作按钮：
- `Export redacted log...`
- `Clear log...`
- `Delete selected`
- `Reveal file`，相关文件仍存在时显示。

Export redacted log 确认：
- 标题：`Export redacted AI call log?`
- 说明：`The export helps diagnose AI behavior without including API keys, full file contents, full prompts, full outputs, or full notes.`
- 将包含：调用时间、feature、local/remote、provider 名称、model 名称、status、duration、错误码、sent field types、privacy rule id/name、matched field type、skipped reason、脱敏 result summary。
- 不包含：API key、完整文件正文、完整 prompt、完整模型输出、完整用户 Note、绝对路径用户名、Keychain 引用值。
- 选项：`Include selected rows only`，仅有选中记录时可用，默认关闭。
- 主按钮：`Export redacted log`
- 次按钮：`Cancel`
- Cancel 后返回日志页，不改变过滤器、选中行或日志内容。
- 导出成功后显示 toast：`Redacted AI call log exported.`

Clear log 确认：
- 标题：`Clear AI call log?`
- 说明：`This deletes all AI call log entries on this Mac. It will not delete files, AI results, tags, summaries, notes, AI settings, or API keys.`
- 危险按钮：`Clear log`
- 次按钮：`Cancel`
- 清除后显示空态和 toast：`AI call log cleared.`

Delete selected 确认：
- 选择 1 条记录时标题：`Delete this AI call log entry?`
- 选择多条记录时标题：`Delete selected AI call log entries?`
- 说明：`This only deletes log entries. It will not delete files, AI results, tags, summaries, notes, or AI settings.`
- 危险按钮：`Delete log entries`
- 次按钮：`Cancel`
- 删除后显示 toast：`AI log entries deleted.`

## 状态与规则

- 加载中：显示 `Loading AI call log...`，表格保持 skeleton，不显示旧过滤结果。
- 无日志：显示 `No AI calls yet`，并说明 AI 默认关闭或尚未使用。
- 读取失败：显示 `AI call log could not be loaded.`，主操作 `Retry`，次操作 `Open diagnostics`。
- 过滤无结果：显示 `No AI calls match these filters.`，操作 `Clear filters`。
- 远程记录必须有明显 `Remote` 标记。
- 隐私规则跳过必须记录为 `Skipped`，用于解释为什么没有结果。
- 隐私跳过记录字段固定为：rule id/name、feature、file/batch、provider gate、status `Skipped`、sent fields `none`、result `No AI call was made`。
- Provider Test 记录用于 S3-03 的 `Test connection`；它不是文件级 AI 调用，必须固定为 feature `Provider Test`、scope `Provider verification`、file/batch `None`、sent fields `none`。
- Provider Test 记录不得包含 API key、key 片段、Keychain 引用值、用户文件名、repo-relative path、摘要、提取文本、标签、Note、prompt、完整 provider 请求体或原始响应体。
- Provider Test 失败只能记录脱敏错误码和可读说明，例如 key rejected、network failed 或 endpoint unavailable；不得回显 provider 返回的敏感 header/body。
- Clear log 需要确认，并说明不删除文件、AI 结果、标签、摘要、Note、AI 设置或 API key。
- Delete selected 需要确认，并说明只删除日志条目，不删除文件、AI 结果、标签、摘要、Note 或设置。
- 没有选中记录时 `Delete selected` 禁用，禁用原因显示 `Select log entries to delete`。
- 导出日志必须脱敏，不包含 API key、完整文件内容、完整 prompt 或完整输出。
- 无日志时 `Export redacted log...` 禁用，禁用原因显示 `No AI call log entries to export`。
- 日志仍在加载或读取失败时 `Export redacted log...` 禁用；读取失败恢复后才可导出。
- 导出准备中显示 `Preparing redacted export...`，表格可浏览但 Clear/Delete/Export 按钮禁用。
- 导出失败显示 `Redacted AI call log could not be exported.`，操作为 `Retry export`、`Cancel`；不得生成半截未脱敏文件。
- 脱敏失败必须阻止导出，显示 `Export stopped because redaction failed.`，操作为 `Retry export`、`Open diagnostics`、`Cancel`。
- 默认本地日志保留 90 天；用户可手动清除。过期自动清理时在空态或日志页脚显示 `Logs older than 90 days are automatically removed.`
- 删除选中记录只删除日志记录，不删除 AI 结果、文件、标签、摘要、Note 或设置。
- 隐私规则命中 note summary、提取文本或其他字段时，日志必须记录 skipped，sent fields 为 none，并保留 matched field type 供追溯。

## 交互

1. 打开页面时加载最近日志，默认按时间倒序。
2. 用户改变过滤器后表格即时刷新。
3. 点击表格行显示详情，不自动打开文件。
4. 点击 `Export redacted log...` 打开导出确认，显示将包含/不包含的内容；点击 Cancel 返回日志页且不创建导出文件。
5. 在导出确认中点击 `Export redacted log` 后先执行 redaction，再打开系统保存位置选择；用户取消保存位置选择时返回日志页并显示 `Export canceled.`。
6. 保存成功后显示完成 toast；保存失败或 redaction 失败时保留日志页状态并允许重试。
7. 点击 `Clear log...` 弹确认，确认后清空日志并显示完成状态。
8. 点击 `Delete selected` 弹确认，确认后删除选中日志条目，当前过滤器保持不变。
9. 从 AI 建议卡进入时，自动选中对应调用记录。
10. 从隐私跳过状态进入时，自动过滤并选中对应 skipped 记录。
11. 从 S3-03 连接测试进入或筛选 Provider Test 时，自动显示最近 provider verification 记录，且 `Reveal file` 不显示。
12. 点击 `Reveal file` 仅定位文件；文件不存在时按钮禁用并显示 `File no longer exists`。

## 可访问性

- 表格列、排序状态、过滤器值和远程/跳过徽标必须可被 VoiceOver 读出。
- 键盘用户可在过滤器、表格、详情区和操作按钮之间顺序移动；表格行选中后详情区变化需可感知。
- Clear/Delete 确认 sheet 默认焦点在 `Cancel`，危险按钮需读出影响范围。
- Raw prompt 查看若存在二次确认，焦点必须进入确认 sheet，关闭后回到触发控件。
- Export 确认 sheet 默认焦点在 `Cancel`；VoiceOver 必须读出将包含和不会包含的内容。

## 数据与依赖

- AI call log store。
- Redaction utility。
- Provider/model metadata。
- Privacy rule match snapshot。
- File reveal/navigation。
- Log retention settings。
- Privacy rule id/name snapshot。
- Redacted export schema。
- Redacted export confirmation state。
- Redacted export save/cancel/error state。
- Clear/delete confirmation state。
- Provider Test log schema。
- Provider Test redaction rule。

## 验收清单

- 用户能看到 AI 调用时间、功能、provider、状态和是否远程。
- 远程调用和隐私跳过记录可区分。
- 隐私跳过记录包含 rule id/name、feature、file/batch、provider gate，且 sent fields 为 none。
- S3-03 `Test connection` 记录以 `Provider Test` feature 展示，scope 为 `Provider verification`，file/batch 为 `None`，sent fields 为 `none`。
- Provider Test 记录和导出日志不包含 API key、key 片段、用户文件名、路径、摘要、提取文本、标签、Note、prompt 或 provider 原始响应体。
- 详情只显示发送字段类型，不默认展示敏感全文。
- note summary 只作为 Note 派生字段类型显示；命中隐私规则时远程调用 skipped 且 sent fields 为 none。
- 导出日志不含 API key、完整文件内容和明文敏感 prompt。
- 导出确认清楚列出包含/不包含内容，Cancel、保存位置取消、导出成功、导出失败和脱敏失败路径明确可测。
- 无日志、加载中或读取失败时导出按钮禁用且原因可读。
- 清除日志需要确认，且不影响文件、AI 结果、标签、摘要、Note、AI 设置或 API key。
- 删除选中日志需要确认，且不影响文件、AI 结果、标签、摘要、Note 或设置。
- 加载中、无日志、读取失败、过滤无结果都有明确 UI。
- 默认保留策略显示为 90 天，可手动清除。
- VoiceOver 能读出表格列、远程标记和状态。

## 来源

- 组合来源：[AI 调用日志任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-15-s3-05-ai-call-log.md)、[Stage 3 隐私与可控](../../../roadmap/milestones.md#隐私与可控)。
- 依据现有文档推导：日志脱敏、90 天默认本地保留、隐私跳过记录字段和导出确认规则，遵守项目隐私不变量。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-01 AI 设置总页](S3-01-ai-settings.md)
- [S3-03 远程模型配置与显式启用](S3-03-remote-model-enable.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
