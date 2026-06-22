# Codex Operating Layer Boundary Regression

本记录是 Codex / AreaMatrix 工作层总收口的边界回归证据。它不新增能力，不进入
`workflow/versions/<version>/execution/**` live queue，不写 progress、logs、run summaries、runner lock 或
Git checkpoint 状态。

## 结论

当前 Codex / AreaMatrix 工作层边界回归：**PASS with product-closeout caveat**。

工作层本身未发现 source-of-truth、execution、state 或 skill owner 污染；`tasks/backlog/**`
和 `.codex/references/**` 仍只是 planning / 操作投影层。但 AreaMatrix v1 产品收口仍为
blocked：`workflow/versions/v1-mvp/closeout/closeout.yaml` 记录了 release blocker
和 checkpoint evidence gap；Xcode derived-data dirty state 已单独处置。

当前 backlog prompt package 收口状态：5 个 package 均为 `closed`，`./dev tasks status`
应显示 `backlog open: 0` / `backlog closed: 5`。这些包继续保留为只读浏览和历史候选证据，
不进入 `workflow/versions/<version>/execution/**`，也不代表 v2 或 release 已启动。

## 回归项

| 类型 | 结论 | 证据 | 说明 |
|---|---|---|---|
| Source-of-truth 污染 | PASS | `.ai-governance/README.md`、`tasks/backlog/README.md`、`.codex/references/codex-operating-layer-playbook.md` | 产品语义仍以 `docs/**` 为准，治理语义仍以 `.ai-governance/**` 为准；`.codex/**` 只做 Codex 操作投影。 |
| Execution 污染 | PASS | `tasks/backlog/README.md`、`.ai-governance/workflows/prompt-task-runtime.md` | live execution 仍是 `workflow/versions/<version>/execution/**` + `./dev` + `./task-loop`；backlog 不执行 prompt，不启动第二 runner。 |
| State 污染 | PASS | `tasks/backlog/README.md`、`.ai-governance/workflows/external-capability-admission.md` | backlog、workflow preview、references 和 skills 不写 progress、logs、run summaries、lock、checkpoint 或 promotion state。 |
| Skill owner 污染 | PASS | `.codex/skills-src/README.md`、`.codex/references/index.md` | 现有 7 个 repo-local skills 仍有明确 owner；外部能力需 admission gate，不隐式接入。 |
| v1 产品收口 | BLOCKED | `workflow/versions/v1-mvp/closeout/closeout.yaml` | 这是产品/发布收口 blocker，不是工作层污染。 |

## 当前 Dirty State

审计时发现一个既有脏文件：

```text
apps/macos/.derived-data-log-0CA5RPJ1
```

该文件是 Xcode / SDK / systemVersion 访问日志，属于本机派生环境噪声。已从 Git 跟踪中移除但保留本地文件，并通过 `.gitignore` 忽略 `apps/macos/.derived-data-log-*`，避免后续 Git checkpoint 被同类日志污染。

## 后续判断

1. 工作层治理不需要继续扩张；默认回到 v1 产品收口。
2. 新 live 产品任务前，先处理 release blocker、checkpoint evidence gap 和 dirty worktree。
3. hooks、Automations、Cloud、Worktrees、Vibe-Skills、subagents、Computer Use、Browser / Chrome 仍按 trigger / admission gate 使用，不进入默认主线。

## 验证

最小验证：

```bash
./dev check skills
./dev check governance
python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog .codex/references .ai-governance
```
