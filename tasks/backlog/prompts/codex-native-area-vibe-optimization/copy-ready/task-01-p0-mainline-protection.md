# Copy-ready: P0 主线保护

你在 `.` 工作。本任务是系统治理文档优化，不是 live queue 任务。

## 目标

固化当前共识：AreaMatrix 的唯一 live execution 主线是：

```text
AGENTS.md / .ai-governance
-> workflow/ planning gate
-> tasks/prompts/** live queue
-> ./dev / ./task-loop
-> repo-local skills
```

Codex Automations、Cloud、Worktrees、Vibe-Skills、SDK、app-server、remote-control 都不能在 v1 live queue 阶段接管主线。

## 先读

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `workflow/AGENTS.md`
4. `tasks/prompts/README.md`
5. `.codex/references/codex-workflow-and-tools.md`
6. `tasks/backlog/codex-native-area-vibe-optimization.md`

## 允许修改

- `.ai-governance/**`
- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `docs/api/core-api.md`
- 任何 task-loop progress 或 run summary

## 执行要求

1. 检查现有文档是否已经明确 live 主线和非目标。
2. 如有缺口，补充一个简洁的主线保护段落或表格。
3. 明确 `tasks/backlog/**` 是规划记录，不进入 `./task-loop`。
4. 不创建第二套 runner、progress、queue 或 promotion 机制。

## 验证

至少运行：

```bash
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

汇报时说明改了什么、为什么、验证结果和未触碰 `tasks/prompts/**`。

