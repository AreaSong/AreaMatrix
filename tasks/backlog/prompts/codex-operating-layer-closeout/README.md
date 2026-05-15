# Codex Operating Layer Closeout Prompt Package

本目录保存第四批“Codex / AreaMatrix 工作层总收口”可复制提示词。它不是 `tasks/prompts/**` live queue，不由 `./task-loop` 自动执行。

本批不继续新增能力，而是把前三批优化和已实现的 `./dev backlog` 工具做一次基线验收：确认 source of truth、execution、state、skill owner 和外部能力边界没有被污染，并给出下一阶段是否回到产品主线的判断。

这里的“污染”指边界污染，不是普通代码脏：

- Source-of-truth 污染：`.codex/**`、Vibe-Skills 或 backlog 文档替代 `docs/**` / `.ai-governance/**` 成为产品或治理源事实。
- Execution 污染：外部 runtime、automation、hooks 或第二套 runner 接管 `./dev + ./task-loop + tasks/prompts/**`。
- State 污染：backlog、workflow preview、subagent 或工具写 live queue、progress、logs、run summaries、runner lock、checkpoint。
- Skill 污染：重复 skill、外部 skill 或专业领域 skill 绕过 AreaMatrix repo-local skill owner 和 external capability admission gate。

建议按顺序执行：

| 顺序 | Copy-ready | Verify-ready | 目的 |
|---|---|---|---|
| 1 | `copy-ready/task-01-operating-layer-inventory.md` | `verify-ready/task-01-operating-layer-inventory.md` | 盘点规则、runbook、skills、backlog 包和 `./dev backlog` |
| 2 | `copy-ready/task-02-boundary-regression.md` | `verify-ready/task-02-boundary-regression.md` | 回归核对 source-of-truth / execution / state / skill 边界 |
| 3 | `copy-ready/task-03-operator-playbook.md` | `verify-ready/task-03-operator-playbook.md` | 生成短操作手册，说明日常如何使用这套工作层 |
| 4 | `copy-ready/task-04-next-roadmap.md` | `verify-ready/task-04-next-roadmap.md` | 给出下一阶段路线：回产品主线或继续高级治理 |

通用边界：

- 不修改 `tasks/prompts/**` live queue。
- 不写 `tasks/prompts/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。
- 不启动第二个 `./task-loop`。
- 不安装或启用 Vibe-Skills 全量仓库。
- 不让 hooks、Automations、Cloud、Worktrees、subagents 或 backlog 工具接管 AreaMatrix 主线。
- 不把 `.codex/**`、`tasks/backlog/**` 或 workflow preview 当作产品语义源事实。
