# Task-facing Residual Index

从 lightweight task 视角查看 residual ledger：当前没有 active lightweight task，只有可读遗留项索引。

阅读时长：约 3 分钟。

---

## 当前任务状态

| 来源 | 当前状态 |
|---|---|
| `tasks/active/**` | 0 |
| `tasks/done/**` | 1 |
| `tasks/backlog/prompts/**` | 5 closed / 0 open |
| `workflow/versions/v1-mvp/execution/**` | 637 / 637 complete |

## 全量 residual task 视角

| ID | 状态 | 原因 | 来源 |
|---|---|---|---|
| `v1-rl-002` | `blocked-external` | 需要真实 iCloud placeholder 环境。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-rl-003` | `blocked-external` | 需要 Apple Developer Program、Developer ID、notarization、clean Mac。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-rl-004` | `blocked-decision` | 正式 tag 依赖 release decision。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-rl-006` | `blocked-decision` | 可信测试者名单、反馈入口和反馈路径需要 release decision。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-ref-003-1-task-05` | `deferred` | 走分发证据 review，不补造 task-loop verify evidence。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-ex-001` | `accepted-exception` | 已接受 checkpoint gaps，不补造历史。 | [accepted exceptions](../../workflow/versions/v1-mvp/residuals/accepted-exceptions.md) |
| `global-ref-areaflow` | `reference-only` | 历史愿景，不是 AreaMatrix 当前任务。 | [non-current references](../../workflow/residuals/non-current-references.md) |
| `global-template-vtemplate` | `template-only` | 模板参考实例，blocked-by-design。 | [non-current references](../../workflow/residuals/non-current-references.md) |
| `global-ref-closed-backlog-packages` | `reference-only` | 5 个 backlog prompt package 均 closed。 | [tasks backlog](../backlog/README.md) |
| `global-marker-product-doc-status-words` | `reference-only` | 产品文档状态词是产品行为/API 状态，不是 task state。 | [non-current references](../../workflow/residuals/non-current-references.md) |

宽泛查询“还有什么问题没有解决”时，不允许只输出当前阻塞项；必须同时列出本表里的非当前待办项，并明确它们不是 active task。

## 转成 task 的条件

只有满足以下条件，才允许人工创建 `tasks/active/<number>.<slug>/`：

1. residual 条目明确 `executable_task: true`，或维护者明确决定新增 lightweight task。
2. 有 owner、scope、source of truth、validation、close condition。
3. 不需要 workflow discussion / promotion 才能执行。
4. 不会触碰 `workflow/versions/<version>/execution/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。

## Related

- [workflow residuals](../../workflow/residuals/)
- [v1-mvp residuals](../../workflow/versions/v1-mvp/residuals/)
- [tasks README](../README.md)
