# Stage 3 AI Core 能力索引

> Stage 3 目标是在本地优先、隐私可控的前提下加入 AI 分类、摘要、标签和语义搜索。AI 是可选增强，不是核心功能依赖。

## 能力列表

| ID | 能力 | 类型 | 主要消费页面 | Prompt |
|---|---|---|---|---|
| C3-01 | [ai-settings-config](stage-3-ai/C3-01-ai-settings-config.md) | AI Config | S3-01, S3-09 | `4-2/task-01`..`4-2/task-05` |
| C3-02 | [local-model-status](stage-3-ai/C3-02-local-model-status.md) | Local Model | S3-02 | `4-2/task-06`..`4-2/task-10` |
| C3-03 | [remote-provider-config](stage-3-ai/C3-03-remote-provider-config.md) | Remote AI | S3-03, S3-09 | `4-2/task-11`..`4-2/task-15` |
| C3-04 | [ai-classification-suggestion](stage-3-ai/C3-04-ai-classification-suggestion.md) | AI Classify | S3-04, S3-10 | `4-2/task-16`..`4-2/task-20` |
| C3-05 | [ai-call-log](stage-3-ai/C3-05-ai-call-log.md) | Audit | S3-05 | `4-2/task-21`..`4-2/task-25` |
| C3-06 | [ai-summary](stage-3-ai/C3-06-ai-summary.md) | Summary | S3-06 | `4-2/task-26`..`4-2/task-30` |
| C3-07 | [ai-tags-suggestion](stage-3-ai/C3-07-ai-tags-suggestion.md) | Tags | S3-07 | `4-2/task-31`..`4-2/task-35` |
| C3-08 | [semantic-search](stage-3-ai/C3-08-semantic-search.md) | Search | S3-08, S3-10 | `4-2/task-36`..`4-2/task-40` |
| C3-09 | [ai-privacy-rules](stage-3-ai/C3-09-ai-privacy-rules.md) | Privacy | S3-03, S3-04, S3-06, S3-07, S3-08, S3-09 | `4-2/task-41`..`4-2/task-45` |
| C3-10 | [ai-fallback](stage-3-ai/C3-10-ai-fallback.md) | Fallback | S3-04, S3-08, S3-10 | `4-2/task-46`..`4-2/task-50` |

## 切片原则

- AI 默认关闭；远程调用必须显式启用。
- 自动摘要、自动标签、AI 分类结果在用户确认前都是建议，不写最终分类/标签/摘要。
- 所有 AI 调用必须写入可清除、可审计、不会泄露密钥的日志。
