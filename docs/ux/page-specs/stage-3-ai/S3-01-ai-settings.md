# S3-01 ai-settings - AI 设置总页

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-01  
> 页面类型：AI 设置  
> 页面文件：`S3-01-ai-settings.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 设置。
- **建议目录**：`apps/macos/AreaMatrix/Features/AI/AISettingsView.swift`。
- **建议组件**：`AISettingsView`、`AIProviderStatusCard`、`AIFeatureToggleList`、`AIPrivacySummaryCard`。
- **实现说明**：AI 是可选增强。新安装、升级后默认关闭，不得自动调用本地或远程模型。

## 页面背景

用户进入设置想了解并控制 AreaMatrix 的 AI 能力。Stage 3 的 AI 包括本地分类、摘要、自动标签、语义搜索，以及用户显式启用的远程模型。这个页面必须先讲清状态和开关，不把 AI 功能藏在其他页面自动执行。

入口：Settings > AI；首次点击 AI 功能时的 `Configure AI`；AI 失败提示中的 `Open AI settings`。
退出：保存设置后回到 Settings；进入本地模型状态、远程配置、隐私规则或调用日志。

## 整体风格

采用 macOS 设置页风格，信息密度偏高但保持分组清楚。AI 状态、安全边界和数据流向要比营销性描述更醒目；不要使用宣传式 hero、插画或自动化承诺。远程能力使用明确文字、状态徽标和禁用原因表达，颜色只能作为辅助提示。

## 页面功能

- 显示 AI 总开关。
- 显示本地模型状态和远程 AI 状态。
- 分功能开关：分类建议、摘要、自动标签、语义搜索。
- 显示远程 AI 是否启用，以及数据是否可能离开本机。
- 显示隐私规则摘要。
- 提供进入调用日志的入口。
- 提供一键暂停 AI 的安全动作。
- 提供清除未采纳 AI 建议和草稿的安全动作。

## 布局与内容

页面位于 Settings 主窗口的 `AI` tab。不要做引导式营销页，采用偏专业的设置面板。

顶部状态卡：
- 标题：`AI features`
- 总开关：`Enable AI features`
- 状态文案：
  - 关闭：`AI is off. AreaMatrix will not call local or remote models.`
  - 本地：`Local AI is enabled. Files stay on this device.`
  - 远程：`Remote AI is enabled for selected features.`

Provider 卡片：
- `Local model: Ready / Not installed / Loading / Error`
- `Remote model: Off / Configured / Needs attention`
- 操作：`Local model status`、`Configure remote AI`

功能开关列表：
每行必须显示功能名、当前开关状态、provider 要求、远程 scope 状态和禁用原因。

| 功能 | Provider 标签 | 远程使用条件 | 默认禁用原因示例 |
|---|---|---|---|
| `Classification suggestions` | `Local preferred` | 仅在 S3-03 的 Classification scope 显式启用后可用；本地模型可用时优先本地。 | `AI is off`、`Local model is not ready`、`Remote Classification scope is not allowed`、`AI call log is not available` |
| `Auto summaries` | `Local or remote` | 远程需 Summary scope、`privacy_gate_enabled`、字段/规则通过和日志 gate。 | `AI is off`、`No provider is ready`、`Remote Summary scope is not allowed`、`Remote AI blocked by privacy gate`、`AI call log is not available` |
| `Auto tags` | `Local or remote` | 远程需 Tags scope、`privacy_gate_enabled`、字段/规则通过和日志 gate。 | `AI is off`、`No provider is ready`、`Remote Tags scope is not allowed`、`Remote AI blocked by privacy gate`、`AI call log is not available` |
| `Semantic search` | `Local index by default` | 远程 embedding / index 仅在 Semantic search scope 显式启用、provider verified 且隐私规则通过后可用。 | `AI is off`、`Semantic index is not ready`、`Remote Semantic search scope is not allowed`、`Remote AI blocked by privacy gate`、`AI call log is not available` |

隐私卡：
- `Privacy rules: 3 active`
- `Remote AI blocked for: finance/private, *.key, confidential`
- 按钮：`Manage privacy rules`

日志入口：
- `View AI call log`
- 副文本：`See when AI was used and whether it was local or remote.`

底部安全动作：
- `Pause all AI`
- `Clear AI generated suggestions...`
- 二次确认标题：`Clear AI generated suggestions?`
- 二次确认说明：`This clears pending AI suggestions and draft summaries. Accepted tags, saved summaries, user notes, original files, and call logs will not be deleted.`
- 危险按钮：`Clear suggestions`
- 次按钮：`Cancel`

## 状态与规则

- 加载中：顶部状态卡显示 `Loading AI settings...`，所有开关禁用，导航按钮保持可点击但进入页也显示加载态。
- 空配置：新安装或升级后显示总开关关闭、本地模型 `Not installed`、远程模型 `Off`、功能开关全部关闭。
- 读取失败：显示 inline error `AI settings could not be loaded.`，主操作 `Retry`，次操作 `View AI call log`。
- 总开关关闭时，所有功能行禁用，但仍显示当前配置状态。
- 本地模型未就绪时，本地-only 功能不能启用，禁用原因显示 `Local model is not ready`，恢复入口为 `Local model status`。
- 远程 AI 未显式配置时，任何远程功能不能启用，禁用原因显示 `Remote AI is not configured`，恢复入口为 `Configure remote AI`。
- 功能行禁用原因必须逐项计算并显示：AI 总开关关闭、本地模型未就绪、远程 provider 未配置或未验证、对应 `feature_scope` 未允许、`privacy_gate_enabled` 阻断、字段/规则阻断或 S3-05 调用日志不可写。
- 如果某功能有本地和远程两条路径，禁用原因必须说明当前阻断的是全部路径还是仅远程路径；例如 `Local model is not ready. Remote Summary scope is not allowed.`。
- 开启远程能力必须跳转 `S3-03 remote-model-enable`，不能在本页一个 toggle 完成。
- 隐私规则命中时，功能开关仍可开启，但调用前必须跳过命中文件。
- Pause all AI 立即阻止后续调用，不删除已有结果。
- Clear AI generated suggestions 只清理未采纳建议和草稿摘要，不清除已保存摘要、已采纳标签、用户 Note、原文件或调用日志。
- 设置保存失败：显示 inline error `AI settings could not be saved.`，保持用户刚切换的控件为 pending 状态，操作为 `Retry save` 和 `Revert changes`。
- Pause all AI 失败：顶部状态显示 `AI could not be paused.`，保留上一次成功保存的开关状态，操作为 `Retry pause` 和 `View AI call log`。
- Clear AI generated suggestions 失败：显示 `AI generated suggestions could not be cleared.`，未清除的建议和草稿必须保留，操作为 `Retry clear`、`View AI call log`、`Cancel`。
- Clear AI generated suggestions 部分成功时显示已清除数量和失败数量；失败项保留，提供 `Retry clear failed items`。

## 交互

1. 打开页面时读取 AI settings、provider status、privacy rule summary。
2. 切换总开关时立即保存，但如果会启用远程能力，必须先走远程确认。
3. 点击功能开关时校验依赖 provider；缺少依赖则显示 inline recovery action。
4. 点击 `Configure remote AI` 进入远程模型配置 sheet。
5. 点击 `Manage privacy rules` 进入隐私规则页。
6. 点击 `View AI call log` 进入调用日志页。
7. 点击 `Pause all AI` 后保存设置；成功时顶部状态变为 off 并显示完成 toast，失败时恢复到上一次成功保存状态并显示恢复动作。
8. 点击 `Clear AI generated suggestions...` 弹确认；确认后清除 pending suggestions / draft summaries，并显示清除数量；失败时保留未清除内容并允许重试。

## 可访问性

- 所有开关、按钮和链接必须可通过键盘访问，焦点顺序为顶部状态、provider、功能开关、隐私、日志、安全动作。
- VoiceOver 必须读出每个开关的功能名、当前状态、provider 要求和禁用原因。
- 从子页面或确认 sheet 返回后，焦点回到触发按钮；危险确认取消后焦点回到原危险按钮。
- 远程、本地、错误、禁用状态不能只依赖颜色，必须配合文本或状态徽标。

## 数据与依赖

- AI settings store。
- Local model status provider。
- Remote model configuration status。
- Privacy rules summary。
- AI call log count/status。
- Feature capability flags。
- Pending AI suggestions count。
- Draft summary count。
- AI settings save mutation result。
- Clear generated suggestions mutation result。

## 验收清单

- 默认状态下 AI 总开关关闭，且不会自动调用模型。
- 远程 AI 不能通过本页普通 toggle 直接开启。
- 用户能看到哪些功能需要本地模型，哪些可能使用远程。
- 每个功能的 provider 要求、远程 scope 状态和禁用原因逐项可见，不需要实现方再推断映射关系。
- Pause all AI 后后续 AI 调用被阻止。
- 隐私规则摘要可进入管理页。
- Clear AI generated suggestions 需要二次确认，且不影响用户文件、Note、已采纳标签、已保存摘要或调用日志。
- 设置保存失败、Pause all AI 失败、Clear suggestions 失败都有明确错误态、重试和回退动作。
- 加载中、空配置、读取失败和依赖缺失都有明确状态和禁用原因。
- VoiceOver 能读出每个开关状态、provider 要求和禁用原因。

## 来源

- 组合来源：[Stage 3 智能化](../../../roadmap/milestones.md#stage-3智能化约-4-个月)、[AI 设置配置任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-11-s3-01-ai-settings.md)。
- 依据现有文档推导：AI 默认关闭、远程显式启用、Pause all AI、清除未采纳 AI 建议的确认规则，遵守 [逐页 UI 开发规格索引](../README.md#来源标注规则) 和项目隐私不变量。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-02 本地模型状态](S3-02-local-model-status.md)
- [S3-03 远程模型配置与显式启用](S3-03-remote-model-enable.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
