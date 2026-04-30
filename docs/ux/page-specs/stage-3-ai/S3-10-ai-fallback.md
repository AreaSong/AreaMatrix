# S3-10 ai-fallback - AI 失败回退提示

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-10  
> 页面类型：AI 失败回退  
> 页面文件：`S3-10-ai-fallback.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 失败状态。
- **建议目录**：`apps/macos/AreaMatrix/Features/AI/AIFallbackBanner.swift`。
- **建议组件**：`AIFallbackBanner`、`AIFailureDetailSheet`、`FallbackActionButtons`。
- **实现说明**：本页固定实现为 `AIFallbackStatusRegion`。宿主可以把它放在 banner、inline empty state 或详情 sheet 容器内，但 reason、文案、按钮和 retry 规则必须一致。AI 失败不应阻断基础文件管理。

## 页面背景

AI 可能因为本地模型未安装、远程 key 失效、网络失败、隐私规则跳过、模型超时或索引未就绪而不可用。用户需要知道当前功能为何没有 AI 结果，并能继续完成任务。

入口：AI 分类建议、摘要、自动标签、语义搜索失败；AI 设置 provider 状态异常；调用日志中打开失败详情。
退出：重试成功；打开设置修复；使用非 AI 回退；关闭提示。

## 整体风格

失败回退区域要像可操作状态提示，不像致命错误页。核心文件管理、普通搜索和手动编辑入口必须仍然可见。隐私跳过使用中性 `Skipped` 语气；远程、本地、rate limit、timeout 等原因使用 reason badge 和文字说明，不只靠颜色。

## 页面功能

- 显示 AI 失败原因。
- 区分错误、跳过、未配置、不可用。
- 提供重试。
- 提供打开 AI 设置、本地模型状态、远程配置或隐私规则。
- 提供非 AI 回退动作。
- 记录失败到 AI 调用日志。

## 布局与内容

`AIFallbackStatusRegion` 是标准失败/跳过状态区域，包含标题、说明、reason badge、主操作、次操作和日志入口。宿主只决定外层容器，不改变内部动作语义。

Banner 标题示例：
- `AI summary could not be generated`
- `Semantic search is unavailable`
- `Skipped by privacy rule`
- `Local model is not ready`

说明文案：
- 网络/远程：`Remote AI could not be reached. Your files were not changed.`
- 隐私规则：`This file matches a privacy rule, so AI was skipped.`
- 本地模型：`The local model is not installed or still loading.`
- 语义索引：`Semantic index is not ready yet.`

操作按钮：
- `Retry`
- `Use normal search`
- `Classify manually`
- `Edit summary manually`
- `Add tags manually`
- `Open AI settings`
- `Open local model status`
- `Configure remote AI`
- `Build semantic index`
- `View privacy rule`
- `View call log`

Reason 矩阵：

| Reason | 标题 | 主操作 | 次操作 |
|---|---|---|---|
| `local_not_ready` | `Local model is not ready` | `Open local model status` | 宿主级非 AI 回退 |
| `remote_not_configured` | `Remote AI is not configured` | `Configure remote AI` | 宿主级非 AI 回退 |
| `remote_failed` | `Remote AI could not be reached` | `Retry` | `Open AI settings` |
| `privacy_skipped` | `Skipped by privacy rule` | `View privacy rule` | 宿主级非 AI 回退 |
| `semantic_index_not_ready` | `Semantic index is not ready` | `Build semantic index` | `Use normal search` |
| `rate_limited` | `Provider rate limit reached` | `Retry later` | 宿主级非 AI 回退 |
| `timeout` | `AI request timed out` | `Retry` | `View call log` |

宿主级非 AI 回退映射：
- AI 分类宿主：显示 `Classify manually`，进入分类纠错或手动分类流程。
- AI 摘要宿主：显示 `Edit summary manually`，进入可编辑摘要区但不触发 AI。
- AI 标签宿主：显示 `Add tags manually`，进入 Stage 2 标签添加 / 编辑流程。
- 语义搜索宿主：显示 `Use normal search`，用当前 query、scope 和可兼容 filters 返回普通搜索。

实现方必须按宿主功能渲染上表中的具体按钮文案，不得把 `宿主级非 AI 回退` 或 `Use non-AI fallback` 作为用户可见按钮。

## 状态与规则

- 解析中：AI 任务刚返回但 reason 仍在映射时显示 `Resolving AI status...`，所有恢复按钮禁用，最多持续到错误映射完成。
- 隐私规则命中不是错误，文案用 `Skipped`，不要显示红色错误。
- 远程失败不得自动改用另一个 provider。
- 本地失败不得自动启用远程 AI。
- Retry 不应重复发送被隐私规则禁止的内容。
- AI 失败不改变文件、分类、标签或摘要。
- 重试次数过多时建议打开设置或日志，不无限循环。
- Retry 只重试同一 provider、同一 model、同一 feature scope 和同一输入快照；重试前必须再次检查隐私规则。
- `Retry` 禁用条件：reason 仍在解析、隐私规则命中、rate limit 未到建议时间、缺少 provider/input snapshot 或当前功能已被 Pause all AI 阻止。
- `remote_not_configured` 不能把 `Configure remote AI` 作为唯一出口，必须按宿主显示 `Classify manually`、`Edit summary manually`、`Add tags manually` 或 `Use normal search`。
- `privacy_skipped` 必须写入 S3-05 skipped 记录，sent fields 为 none。
- `Build semantic index` 只在 reason 为 `semantic_index_not_ready` 且 AI 总开关、Semantic search 功能开关、provider、usage scope、隐私规则和日志能力检查通过时启用；否则显示对应禁用原因和 `Use normal search`。
- 点击 `Build semantic index` 必须进入 S3-08 的索引构建提示和 gate 检查结果；Cancel 后返回原语义搜索页并保持失败状态。
- `rate_limited` 默认禁用立即重试，显示下次建议时间；无建议时间时显示 `Try again later`。
- 用户关闭区域后，当前页面保留普通文件管理、普通搜索、手动分类、手动摘要或手动标签能力。

## 交互

1. AI 任务失败或跳过时生成标准 `AIFallbackReason`。
2. 页面按 reason 显示对应标题、说明和动作。
3. 点击 Retry 只重试同一 provider 和同一 scope，并再次检查隐私规则。
4. 点击非 AI 回退进入对应手动流程：分类进入手动分类，摘要进入手动编辑，标签进入手动添加标签，语义搜索进入普通搜索。
5. 点击 `View call log` 打开对应调用记录。
6. 用户关闭 banner 后当前页面保留非 AI 内容，不隐藏基础功能。
7. 点击 `View privacy rule` 打开命中的 S3-09 隐私规则并定位规则行。
8. 点击 `Configure remote AI` 进入 S3-03；取消后返回原功能页并保持失败状态。
9. 点击 `Open local model status` 进入 S3-02；返回后刷新本地状态。
10. 点击 `Build semantic index` 进入 S3-08 的索引构建提示；取消或构建失败后返回原语义搜索页并保持可用的普通搜索回退。

## 可访问性

- reason badge、标题、说明、主操作、次操作和日志入口必须形成一个可读状态区域。
- VoiceOver 必须读出失败原因、是否隐私跳过、Retry 禁用原因和可用的非 AI 回退动作。
- Banner、inline empty state 和详情 sheet 三种宿主形态都必须支持键盘关闭和焦点返回。
- 隐私跳过、错误、警告和禁用状态不能只用颜色表达。

## 数据与依赖

- AI error/fallback reason model。
- AI settings navigation。
- Privacy rules navigation。
- AI call log id。
- Manual fallback routes：normal search、classifier correction、summary editor、tag editor。
- Host fallback label mapping：classification -> `Classify manually`、summary -> `Edit summary manually`、tags -> `Add tags manually`、semantic search -> `Use normal search`。
- Semantic index build route。
- Retry policy。
- AIFallbackReason enum and reason-to-action matrix。
- Provider/model/input snapshot for retry。
- Privacy rule match id。
- Retry-after timestamp for rate limit。

## 验收清单

- 本地模型未就绪、远程失败、隐私规则跳过、语义索引未就绪四类状态文案不同。
- reason 解析中有明确加载状态，Retry 禁用条件可见。
- local not ready、remote not configured、remote failed、privacy skipped、semantic index not ready、rate limit、timeout 都有 reason、主操作和次操作。
- 宿主级非 AI 回退必须渲染为明确按钮：分类 `Classify manually`、摘要 `Edit summary manually`、标签 `Add tags manually`、语义搜索 `Use normal search`，不得显示抽象占位文案。
- semantic index not ready 的 `Build semantic index` 动作、禁用条件、Cancel 返回和失败回退路径明确可测。
- AI 失败不阻断普通文件管理。
- Retry 前仍检查隐私规则。
- 不自动启用远程 AI 或切换 provider。
- Retry 只使用同一 provider/model/scope/input snapshot。
- 隐私跳过可跳转规则详情，并在调用日志中以 sent fields none 追溯。
- 用户能从失败提示进入设置或调用日志。
- VoiceOver 能读出失败原因和可用回退动作。

## 来源

- 组合来源：[AI 失败回退任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-20-s3-10-ai-fallback.md)、[错误文案与恢复路径](../../error-messages.md)。
- 依据现有文档推导：`AIFallbackStatusRegion`、reason 矩阵、同 provider/scope 重试、隐私跳过追溯和非 AI 回退规则，遵守 AI 默认关闭与可回退原则。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-01 AI 设置总页](S3-01-ai-settings.md)
- [S3-02 本地模型状态](S3-02-local-model-status.md)
- [S3-03 远程模型配置与显式启用](S3-03-remote-model-enable.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [逐页 UI 开发规格索引](../README.md)
