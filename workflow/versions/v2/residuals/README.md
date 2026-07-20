# v2 Residuals

`v2` 治理遗留项索引：记录独立复核、execution authorization 与 remote merge controls 的 durable 状态。

阅读时长：约 2 分钟。

---

## 当前结论

| ID | 状态 | 类型 | 当前影响 |
|---|---|---|---|
| `v2-risk-001` | `open` | `governance-risk` | 缺少合格独立复核者时，L3/L4、High 和 Mission-Critical 变更保持 blocked。 |
| `v2-dep-003` | `deferred` | `governance-dependency` | v2 promotion apply、live execution 和 task-loop writes 未获授权。 |
| `v2-dep-004` | `deferred` | `governance-dependency` | remote CI 与 branch protection 证据仍是 merge readiness 的外部条件。 |

三项权威来源统一为
[`docs/governance/governance-register.yaml`](../../../../docs/governance/governance-register.yaml)。
本目录只提供版本索引，不替代治理登记册，也不把任何条目转成 live task 或 execution authorization。

## 执行边界

- 三项均为 `executable_task: false`，不得自动创建 `tasks/active/**`。
- `v2-dep-003` 关闭前不得执行 promotion apply、写 `execution/**` 或启动 runner 写路径。
- `v2-dep-004` 的本地检查不能冒充 remote CI 或 branch protection evidence。
- `v2-risk-001` 不能由同一维护者自我复核关闭。

机器可读索引见 [residuals.yaml](residuals.yaml)。

## Related

- [v2 workflow](../README.md)
- [global residual ledger](../../../residuals/)
- [enterprise governance baseline](../../../../docs/governance/enterprise-workflow-baseline.md)
