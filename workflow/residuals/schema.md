# Residual Ledger Schema

Residual ledger 的字段约定，用于人读 Markdown 与机器可读 `residuals.yaml` 保持一致。

阅读时长：约 4 分钟。

---

## 状态枚举

| 状态 | 含义 |
|---|---|
| `open` | 真实待处理，当前没有外部阻断。 |
| `blocked-external` | 被外部环境、账号、设备、证书、服务或人工条件阻断。 |
| `blocked-decision` | 等待明确产品、发布、治理或架构决策。 |
| `deferred` | 明确延期，不阻断当前主线。 |
| `reference-only` | 历史参考或愿景材料，不是当前任务。 |
| `template-only` | 模板或示例语义，不是真版本状态。 |
| `accepted-exception` | 已正式接受为例外，不应补造历史证据。 |
| `closed` | 已关闭。 |

## 类型枚举

| 类型 | 含义 |
|---|---|
| `release-evidence` | 发布证据或发布门禁遗留项。 |
| `closeout-exception` | closeout 接受例外。 |
| `historical-reference` | 历史参考、愿景或迁移记录。 |
| `template-reference` | 模板实例、示例队列或 preview-only artifact。 |
| `backlog-reference` | closed backlog、候选包或治理记录。 |
| `product-doc-marker` | 产品文档里的状态词或验收表达，属于产品结构而非任务。 |
| `task-index` | 可转任务视角的索引项。 |

## 必填字段

```yaml
id: v1-rl-002
status: blocked-external
type: release-evidence
title: iCloud placeholder real-environment smoke
source: workflow/versions/v1-mvp/evidence/release-checklist.md
owner: release
current_impact: formal-alpha-blocked
executable_task: false
promotion_required: false
close_condition: Real iCloud placeholder smoke evidence is recorded.
```

## 关键约束

- `source` 必须指向权威源文件；residual ledger 不替代源文件。
- `executable_task: false` 的条目不得自动创建 `tasks/active/**`。
- `accepted-exception` 条目不得通过重写 `progress.json`、Git history、logs 或 summary 关闭。
- `reference-only` 和 `template-only` 条目不得进入 `./task-loop`。
- `close_condition` 必须是可验证条件，不写“以后处理”这类空话。

## ID 规则

| 前缀 | 用途 |
|---|---|
| `global-ref-*` | 跨版本历史参考或非当前材料。 |
| `global-template-*` | 跨版本模板参考项。 |
| `v1-rl-*` | v1 release blocker / release evidence。 |
| `v1-ex-*` | v1 accepted exception。 |
| `v1-ref-*` | v1 historical reference 或特殊 release gate review。 |
| `task-idx-*` | task 视角索引项。 |

## Related

- [residuals overview](README.md)
- [v1-mvp residuals](../versions/v1-mvp/residuals/)
