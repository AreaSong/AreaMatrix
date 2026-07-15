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
| `v1-rl-002` | `blocked-external` | iCloud smoke record 已结构化；仍需要真实 iCloud placeholder 环境，且只读 metadata helper 不能替代手工 Download & retry、DB row 和用户文件不变量。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-rl-003` | `blocked-external` | 分发签名 / 公证 record 已结构化；仍需要 Apple Developer Program、Developer ID、notarytool accepted log、stapled DMG、spctl assess 和 clean Mac。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-rl-004` | `blocked-decision` | final tag record 已结构化；正式 tag 仍依赖 release gates 全部关闭、release candidate commit、annotated `v0.1.0` tag 创建和 push 决策。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-rl-006` | `blocked-decision` | Alpha feedback issue template 和 route evidence 已存在，且 `closes_residual: false`；可信测试者名单、tester invitation side effect、正式公告 / Discussion 链接、反馈分流和 triage owner 仍需要 release decision。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-ref-003-1-task-05` | `deferred` | release-gate review record 已结构化，当前 `closes_residual: false`；走 fresh release evidence review，不补造 task-loop verify evidence。 | [v1 release residuals](../../workflow/versions/v1-mvp/residuals/release-evidence.md) |
| `v1-ex-001` | `accepted-exception` | 已接受 checkpoint gaps，不补造历史。 | [accepted exceptions](../../workflow/versions/v1-mvp/residuals/accepted-exceptions.md) |
| `global-product-restore-file-contract` | `closed` | 公开 `restore_file` 合同已移除；受支持的恢复继续使用 Undo/Redo，不是 active task。 | [Core API](../../docs/api/core-api.md) |
| `global-product-metadata-reader-write-flags` | `closed` | Metadata reader 已收紧为只读打开，不创建 sidecar，也不修改 `index.db` 或 WAL，不是 active task。 | [metadata reader](../../apps/macos/AreaMatrix/Bridge/CoreBridgeUnavailableState.swift) |
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
