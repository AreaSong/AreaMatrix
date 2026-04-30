# Stage 3 AI Control Map

> Stage 3 映射 AI 设置、本地模型、远程模型、AI 分类、AI 摘要、AI 标签、语义搜索、隐私规则和失败回退。

## 页面到能力矩阵

| UX | 页面 | Core 能力 | API / 能力意图 | DB / 文件系统 | Prompt |
|---|---|---|---|---|---|
| S3-01 | ai-settings | C3-01 | AI config read/write | ai_config | `4-2/task-11` |
| S3-02 | local-model-status | C3-02 | local model status | model metadata / cache | `4-2/task-12` |
| S3-03 | remote-model-enable | C3-03, C3-09 | provider test/enable | provider metadata, Keychain ref | `4-2/task-13` |
| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 | AI category suggestion | ai_call_log, no write before confirm | `4-2/task-14` |
| S3-05 | ai-call-log | C3-05 | list/clear AI log | ai_call_log | `4-2/task-15` |
| S3-06 | ai-summary-editor | C3-06, C3-09 | generate/save/clear summary | summary metadata, ai_call_log | `4-2/task-16` |
| S3-07 | ai-tags-suggestion | C3-07, C3-09 | suggest/apply tags | tags after confirm, ai_call_log | `4-2/task-17` |
| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 | semantic search / embedding | embedding metadata, ai_call_log | `4-2/task-18` |
| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate | ai_privacy_rules | `4-2/task-19` |
| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log | `4-2/task-20` |

## 验收口径

- AI 默认关闭，本地优先。
- 远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。
- AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。
