# Stage 3 AI Control Map

> Stage 3 映射 AI 设置、本地模型、远程模型、AI 分类、AI 摘要、AI 标签、语义搜索、隐私规则和失败回退。

## 页面到能力矩阵

| UX | 页面 | Core 能力 | API / 能力意图 | DB / 文件系统 | Prompt |
|---|---|---|---|---|---|
| S3-01 | ai-settings | C3-01 | AI config read/write | ai_config | `4-2/task-51` |
| S3-02 | local-model-status | C3-02 | local model status | model metadata / cache | `4-2/task-52` |
| S3-03 | remote-model-enable | C3-03, C3-09 | provider test/enable | provider metadata, Keychain ref | `4-2/task-53`, `4-2/task-54`, `4-2/task-55` |
| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 | AI category suggestion | ai_call_log, no write before confirm | `4-2/task-56`, `4-2/task-57`, `4-2/task-58`, `4-2/task-59` |
| S3-05 | ai-call-log | C3-05 | list/clear AI log | ai_call_log | `4-2/task-60` |
| S3-06 | ai-summary-editor | C3-06, C3-09 | generate/save/clear summary | summary metadata, ai_call_log | `4-2/task-61`, `4-2/task-62`, `4-2/task-63` |
| S3-07 | ai-tags-suggestion | C3-07, C3-09 | suggest/apply tags | tags after confirm, ai_call_log | `4-2/task-64`, `4-2/task-65`, `4-2/task-66` |
| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 | semantic search / embedding | embedding metadata, ai_call_log | `4-2/task-67`, `4-2/task-68`, `4-2/task-69`, `4-2/task-70` |
| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate | ai_privacy_rules | `4-2/task-71`, `4-2/task-72`, `4-2/task-73`, `4-2/task-74` |
| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log | `4-2/task-75`, `4-2/task-76`, `4-2/task-77`, `4-2/task-78` |

## 验收口径

- AI 默认关闭，本地优先。
- 远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。
- AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。
