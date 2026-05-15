# AreaMatrix Backlog Tasks

本目录记录尚未进入 `tasks/prompts/**` live queue 的短期规划任务。

这些任务用于讨论、评估和治理排期，不由 `./task-loop` 自动执行；只有通过 `workflow/` 规划、promotion preview 和人工确认后，才可能拆成正式 prompt task。

当前 live queue 仍然是 `tasks/prompts/**`，进度源事实仍然是 `tasks/prompts/_shared/progress.json`。

## 边界

- `tasks/backlog/**` 不是 live queue，不由 `./task-loop` 扫描、执行、重试或验收。
- backlog prompt 包只能手工复制或经 `workflow/` planning gate 重新拆分；不得直接 promotion 成 `tasks/prompts/**`。
- 本目录不得引入第二套 runner、progress、queue、checkpoint 或 promotion 机制。
- backlog prompt 不得写 `tasks/prompts/**`、`tasks/prompts/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。
- Codex Automations、Cloud、Worktrees、Vibe-Skills、SDK、app-server、remote-control 等外部能力只能作为候选记录；v1 live queue 阶段不得接管 AreaMatrix 主线。
- 外部能力候选必须先通过 [外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md)，才能从候选记录进入 AreaMatrix 规则、skill、workflow 或 live task 边界。

## Backlog Prompt Handoff

- 每个 prompt 包必须拆成 `copy-ready/` 与 `verify-ready/` 两类材料。
- `copy-ready` 写实施范围、精确路径、source of truth、owner / landing、执行顺序、验证命令和 blocked / rollback 口径。
- `verify-ready` 写只读验收范围、必须读取路径、证据检查、验证命令和 PASS / FAIL 输出口径。
- 若缺少精确路径、验证命令、owner、source of truth 或 promotion gate 说明，prompt 包保持 `blocked` / `not-ready`，不能进入 live queue。

## Prompt Packages

- [Codex Native / AreaMatrix / Vibe-Skills 基础治理](prompts/codex-native-area-vibe-optimization/)
- [Vibe-Skills 横向能力吸收](prompts/vibe-skills-absorption/)
