# v1-mvp Residuals

`v1-mvp` 遗留问题索引：技术队列已完成，正式 Stage 1 alpha 仍由 release evidence 阻断。

阅读时长：约 4 分钟。

---

## 当前结论

| 维度 | 状态 | 权威来源 |
|---|---|---|
| 技术队列 | complete (`637/637`) | [execution README](../execution/README.md) |
| closeout decision | recorded | [closeout-decision.md](../closeout/closeout-decision.md) |
| checkpoint gaps | accepted exceptions | [accepted-exceptions.md](accepted-exceptions.md) |
| formal Stage 1 alpha | blocked | [release-evidence.md](release-evidence.md) |

本目录是版本遗留项索引，不替代 `evidence/` 或 `closeout/` 的权威记录。

## 遗留项总览

| ID | 状态 | 类型 | 标题 | 影响 |
|---|---|---|---|---|
| `v1-rl-002` | `blocked-external` | `release-evidence` | iCloud placeholder 真实环境冒烟 | formal alpha blocked |
| `v1-rl-003` | `blocked-external` | `release-evidence` | Developer ID signing / notarization / formal DMG / clean Mac | formal alpha blocked |
| `v1-rl-004` | `blocked-decision` | `release-evidence` | final `v0.1.0` tag | formal alpha blocked |
| `v1-rl-006` | `blocked-decision` | `release-evidence` | alpha tester feedback channel | formal alpha blocked |
| `v1-ex-001` | `accepted-exception` | `closeout-exception` | 35 historical checkpoint gaps | no active task |
| `v1-ref-003-1-task-05` | `deferred` | `release-evidence` | release-gate review item without task-loop verify evidence | handled by release evidence |

机器可读索引见 [residuals.yaml](residuals.yaml)。

## 不属于当前任务的内容

- `workflow/versions/v1-mvp/execution/**` 中静态 prompt 的 `TODO`、`blocked`、`open` 等历史词汇不代表当前 live queue 未完成。
- `source-docs/**` 中的 Stage 2/3/4 是 Stage 1 MVP 历史内部分段资料，不代表未来 `v2` / `v3` / `v4` 已启动。
- 已接受的 checkpoint gaps 不应通过回填 `progress.json`、Git history、logs 或 summary 解决。

## Related

- [release-evidence.md](release-evidence.md)
- [accepted-exceptions.md](accepted-exceptions.md)
- [source-doc-markers.md](source-doc-markers.md)
- [global residual ledger](../../../residuals/)
