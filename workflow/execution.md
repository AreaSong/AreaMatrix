# AreaMatrix Workflow Execution

本文定义 `workflow/versions/<version>/execution/` 的标准职责。它不是产品文档，不定义产品行为；产品源事实仍然是 `docs/`。它也不是未来 AreaFlow 产品规格；AreaFlow 愿景资料见 [`references/areaflow-vision.md`](references/areaflow-vision.md)。

## Position

`execution/` 是 workflow 中从 promotion 进入真实执行闭环的版本内承载层。

标准流转为：

```text
baseline
-> discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion
-> execution
-> projection
-> closeout
```

在 Stage 1 历史实现中，执行层内容放在根目录 `tasks/prompts/**`。标准化后，版本级执行材料应归属到：

```text
workflow/versions/<version>/execution/
```

当前仓库在脚本迁移完成前仍保留 `tasks/prompts/**` 作为历史 live queue 和兼容运行入口；不得在没有硬迁移计划和验证的情况下移动、重写或清空历史队列。

## Responsibilities

`execution/` 负责承载已经通过 promotion 的真实执行材料：

- copy-ready implementation prompts。
- verify-ready read-only acceptance prompts。
- task manifests 和 Expected Paths。
- progress、phase verify、repo gate、checkpoint、run summary。
- copy / verify / repair 日志。
- execution 到 projection 的结果输入。

它不负责：

- 重新讨论产品意图。
- 重新定义 `docs/` 产品语义。
- 替代 `promotion/` 做审批。
- 替代 `projection/` 或 `closeout/` 宣称版本完成。

## Standard Shape

第一轮硬迁移应优先保留现有 `tasks/prompts/**` 内部结构，降低脚本迁移风险：

```text
workflow/versions/<version>/execution/
  _shared/
  phase-0/
  phase-1/
  phase-2/
  phase-3/
  phase-4/
```

迁移完成并验证稳定后，可以在 execution 内进一步标准化运行材料：

```text
workflow/versions/<version>/execution/
  _shared/
  phases/
  logs/
  checkpoints/
  reports/
```

其中：

- `_shared/`：prompt pipeline、manifests、copy-ready、verify-ready、progress、audit rules 等共享执行材料。
- `phase-*` 或 `phases/`：具体任务包，保持可独立执行和验收。
- `logs/`：版本内 copy、verify、repair、runner 日志；日志跟随版本，不归入 `.codex/` 作为 canonical evidence。
- `checkpoints/`：Git branch、changed files、commit、runner resume/stale 状态。
- `reports/`：phase verify、task-scope verify、repo-wide gate 和最终执行报告。

## Validation Layers

execution 的验收必须区分两个层级：

| Layer | Purpose | Blocks |
| --- | --- | --- |
| task-scope verify | 判断当前 task 是否在 Expected Paths 和 manifest 边界内完成 | 当前 task checkpoint |
| repo-wide gate | 判断仓库整体健康度，例如 lint、test、build、release gate | phase / milestone / closeout |

单个 task 的完成状态不应被无关的全仓库历史问题永久阻塞。repo-wide gate 失败必须记录为 phase、milestone 或 closeout 风险，并在 projection 中说明影响范围。

## Failure Routing

execution 失败必须先分类，再决定回到哪里修：

| Failure Type | Meaning | Return To |
| --- | --- | --- |
| prompt boundary fail | manifest、Expected Paths、Forbidden Touches 不一致 | execution prompt package 或 promotion |
| task verify fail | 当前 task 行为未通过 read-only acceptance | 当前 task repair |
| scope drift | 改动越过 manifest 或 Forbidden Touches | 当前 task repair / checkpoint gate |
| environment fail | Xcode、toolchain、model capacity、network、permission 等外部阻塞 | execution report / operator triage |
| checkpoint fail | dirty worktree、commit/push metadata、resume state 不完整 | checkpoint recovery |
| repo-wide gate fail | 仓库级验证失败，但未必属于当前 task | reports / projection / closeout |
| runaway retry | 同一失败指纹重复 repair 且没有新证据 | stop and triage |

不得把所有失败都当成普通 verify fail 无限重试。

## Projection Contract

`projection/` 从 `execution/` 读取结果，但不替代 execution runtime。

execution 至少应能提供：

- task id 和 phase。
- promotion mapping。
- manifest / Expected Paths。
- copy / verify attempt 状态。
- verification evidence。
- changed files。
- checkpoint status。
- commit 或明确的 checkpoint exception。
- unresolved failures 和 triage class。

projection 再把这些结果投影回 change、plan、draft、queue 和 promotion 状态。

## Closeout Contract

`closeout/` 只有在以下证据一致时才能宣称版本完成：

- execution progress 完成。
- task-scope verify 通过或有明确 accepted exception。
- repo-wide gate 已通过，或剩余问题被记录为非阻塞风险。
- projection 与 execution runtime 一致。
- checkpoint、logs、reports 足以回溯。

无法证明通过时，closeout 必须保持 blocked、partial 或 risk-accepted，而不是手写 done。

## Current Migration Boundary

当前文档只定义目标标准，不执行硬迁移。

硬迁移必须另行计划，并至少覆盖：

- `tasks/prompts/**` 到 `workflow/versions/<version>/execution/**` 的路径映射。
- `prompt_pipeline.py`、`./task-loop`、`./dev workflow`、self-check、governance check 的路径更新。
- 历史 progress、logs、checkpoint、run summary 的证据归属。
- README、workflow docs、governance docs、repo-local skills 的口径同步。
- 回滚方式和验证命令。
