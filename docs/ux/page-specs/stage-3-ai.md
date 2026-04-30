# Stage 3 智能化逐页 UI 开发规格

> Stage 3 目标：在保持本地优先和隐私可控的前提下，引入 AI 分类、自动摘要、自动标签和语义搜索。AI 是可选增强，不是核心功能依赖。
>
> 本规格是当前 Stage 3 macOS 智能化 UI 的实现依据；若后续 AI API、隐私策略或模型能力变化，必须先同步更新本文和对应单页规格。
>
> 阅读时长：约 16 分钟。

---

## 使用方式

本文件只保留阶段级索引、通用约束和验收矩阵。逐页开发时，请打开下方单页文件；每个页面文件都可以独立交给 IDE / agent 实现。

---

## 范围边界

### 当前覆盖

本批 Stage 3 页面规格只覆盖 macOS 智能化 UI：

- AI 设置、本地模型状态、远程模型配置与显式启用。
- AI 分类建议确认、自动摘要编辑 / 清除、自动标签采纳 / 修改。
- 语义搜索结果（语义匹配与普通搜索结果分组展示）、AI 隐私规则、AI 调用日志、AI 失败回退提示。
- AI 调用的默认关闭、本地优先、远程显式启用、隐私规则 gate 和日志追溯。

### 暂不覆盖

以下能力不属于本批 `stage-3-ai` 页面开发范围，不应在实现这些页面时顺手加入必做 UI：

- iOS、Windows、Linux、多端同步、跨设备冲突或平台差异 UI；这些属于 Stage 4。
- PRD P2 中的智能命名、语义相似文件检测、OCR 独立工作流页面。
- 修改 Stage 1/2 已定义的基础导入、普通搜索、标签、分类纠错或设置页范围；Stage 3 只能作为可选增强接入这些入口。

若后续决定实现智能命名、相似检测或 OCR，应先新增对应页面规格或更新本索引，再进入开发。

---

## 页面文件目录

| ID | 页面 | 类型 | 单页规格 |
|---|---|---|---|
| S3-01 | ai-settings - AI 设置总页 | AI 设置 | [S3-01-ai-settings.md](stage-3-ai/S3-01-ai-settings.md) |
| S3-02 | local-model-status - 本地模型状态 | 本地模型 | [S3-02-local-model-status.md](stage-3-ai/S3-02-local-model-status.md) |
| S3-03 | remote-model-enable - 远程模型配置与显式启用 | 远程模型 | [S3-03-remote-model-enable.md](stage-3-ai/S3-03-remote-model-enable.md) |
| S3-04 | ai-classification-suggestion - AI 分类建议确认 | AI 分类 | [S3-04-ai-classification-suggestion.md](stage-3-ai/S3-04-ai-classification-suggestion.md) |
| S3-05 | ai-call-log - AI 调用日志 | AI 日志 | [S3-05-ai-call-log.md](stage-3-ai/S3-05-ai-call-log.md) |
| S3-06 | ai-summary-editor - 自动摘要编辑 / 清除 | 自动摘要 | [S3-06-ai-summary-editor.md](stage-3-ai/S3-06-ai-summary-editor.md) |
| S3-07 | ai-tags-suggestion - 自动标签采纳 / 修改 | 自动标签 | [S3-07-ai-tags-suggestion.md](stage-3-ai/S3-07-ai-tags-suggestion.md) |
| S3-08 | semantic-search-results - 语义搜索结果 | 智能搜索 | [S3-08-semantic-search-results.md](stage-3-ai/S3-08-semantic-search-results.md) |
| S3-09 | ai-privacy-rules - AI 隐私规则 | 隐私规则 | [S3-09-ai-privacy-rules.md](stage-3-ai/S3-09-ai-privacy-rules.md) |
| S3-10 | ai-fallback - AI 失败回退提示 | AI 失败回退 | [S3-10-ai-fallback.md](stage-3-ai/S3-10-ai-fallback.md) |

---

## 通用约束

- Stage 3 仅覆盖 macOS 智能化：AI 分类、自动摘要、自动标签、语义搜索、AI 隐私控制和失败回退。
- Stage 3 不包含 iOS、Windows、Linux、多端同步或跨设备冲突 UI；这些属于 Stage 4。
- AI 默认关闭；本地模型为默认推荐路径。
- 远程模型必须由用户显式配置 key、选择使用范围、测试连接成功并确认数据流向后启用；远程调用还必须通过 `provider_configured`、`provider_verified`、`remote_provider_enabled`、`feature_scope`、`privacy_gate_enabled`、字段规则和调用日志 gate，不得默认上传任何文件内容。
- API key 只允许存入 Keychain，不得写入日志、诊断包、错误文案、崩溃报告或导出日志。
- 远程 AI 可发送的字段类型必须逐项展示，并在调用前经过 S3-09 隐私规则 gate；关闭 `privacy_gate_enabled` 只阻止远程调用，不删除 provider 配置、Keychain key、本地 AI 设置或既有 AI 结果。`note summary` 视为用户 Note 的派生字段，可被隐私规则匹配，不得发送完整用户 Note 原文。
- AI 只在规则分类失败或低置信度时介入；失败时回退到本地规则或 inbox。
- 所有 AI 调用必须可见、可清除；涉及远程调用必须说明数据流向。
- 用户必须能配置“不发送到 AI”的目录或关键词规则。
- 自动摘要、自动标签、AI 分类结果在用户确认前都是建议或草稿，不得写入分类、标签、摘要或文件。
- 隐私规则命中必须在对应 AI 页面显示跳过原因，并在 AI 调用日志中可追溯。
- AI 失败不得自动切换远程 provider；本地模型失败不得自动启用远程 AI。

---

## Stage 3 验收矩阵

- AI 默认关闭，本地优先；远程必须显式启用。
- AI 分类只在规则失败或低置信时介入，并带 confidence。
- 摘要和标签结果可编辑、采纳、清除。
- 语义搜索以 `Semantic matches` / `Normal search matches` 两组展示，不生成不可解释的单一混合分数。
- AI 调用日志可见、可清除，远程调用可识别。
- 隐私规则能阻止目录/关键词发送到 AI，且跳过记录可追溯。
- AI 失败不阻断核心导入、普通搜索和本地分类。
- Stage 3 页面不出现多端必做项或 Stage 4 平台 UI。

---

## 任务来源说明

当前 Stage 3 prompt task 已拆为 Core contract `4-2/task-01` 到 `4-2/task-10`、页面 atomic `4-2/task-11` 到 `4-2/task-20`，以及 `4-2/task-21` 集成验收。页面开发和验收以对应 `S3-*` 单页规格、Stage 3 control map 和页面 atomic task 为准。

---

## Related

- [../../roadmap/milestones.md](../../roadmap/milestones.md)
- [../deep-features.md](../deep-features.md)
- [../search.md](../search.md)
- [../error-messages.md](../error-messages.md)
- [../../product/prd.md](../../product/prd.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-11-s3-01-ai-settings.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-11-s3-01-ai-settings.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-12-s3-02-local-model-status.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-12-s3-02-local-model-status.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-13-s3-03-remote-model-enable.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-13-s3-03-remote-model-enable.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-14-s3-04-ai-classification-suggestion.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-14-s3-04-ai-classification-suggestion.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-15-s3-05-ai-call-log.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-15-s3-05-ai-call-log.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-16-s3-06-ai-summary-editor.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-16-s3-06-ai-summary-editor.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-17-s3-07-ai-tags-suggestion.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-17-s3-07-ai-tags-suggestion.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-18-s3-08-semantic-search-results.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-18-s3-08-semantic-search-results.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-19-s3-09-ai-privacy-rules.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-19-s3-09-ai-privacy-rules.md)
- [../../../tasks/prompts/phase-4/4-2-stage3-ai/task-20-s3-10-ai-fallback.md](../../../tasks/prompts/phase-4/4-2-stage3-ai/task-20-s3-10-ai-fallback.md)
