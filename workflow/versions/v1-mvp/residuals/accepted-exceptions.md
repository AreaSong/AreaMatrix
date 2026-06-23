# v1-mvp Accepted Exceptions

已接受例外索引：这些条目不是当前待执行任务，不应补造历史证据。

阅读时长：约 3 分钟。

---

## Checkpoint gaps

| ID | 状态 | 源文件 | 结论 |
|---|---|---|---|
| `v1-ex-001` | `accepted-exception` | [checkpoint-accepted-exceptions.md](../closeout/checkpoint-accepted-exceptions.md) | 35 个历史 task-loop checkpoint gaps 已作为 closeout exceptions 接受。 |

## 约束

- 不回填 `workflow/versions/v1-mvp/execution/_shared/progress.json`。
- 不重写 task-loop logs、run summaries 或 Git history。
- 不把未跟踪 copy / verify logs 描述成 committed checkpoint evidence。
- `3-1/task-05` 不属于 checkpoint accepted exception；它走 release evidence review。

## Related

- [checkpoint-gaps.md](../closeout/checkpoint-gaps.md)
- [checkpoint-evidence-index.md](../closeout/checkpoint-evidence-index.md)
- [release-evidence.md](release-evidence.md)
