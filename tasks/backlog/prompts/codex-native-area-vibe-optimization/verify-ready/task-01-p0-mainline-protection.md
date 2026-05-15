# Verify-ready: P0 主线保护

本次是只读验收，禁止修改文件。

## 验收目标

确认执行结果是否已经明确：

- `./dev + ./task-loop + tasks/prompts/**` 是唯一 live execution 主线。
- `workflow/` 是规划层，不直接写 live queue。
- `tasks/backlog/**` 是规划记录，不由 `./task-loop` 自动执行。
- Vibe-Skills、Codex Automations、Cloud、Worktrees、SDK、app-server、remote-control 没有被接入主线。
- 没有修改 `tasks/prompts/**` 任务定义或 manifest。

## 只读检查

读取：

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `workflow/AGENTS.md`
4. `tasks/prompts/README.md`
5. `.codex/references/codex-workflow-and-tools.md`
6. `tasks/backlog/README.md`
7. `tasks/backlog/codex-native-area-vibe-optimization.md`

运行：

```bash
git diff --stat
git diff --name-only
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

## 判定

- 若发现 `tasks/prompts/**` 被改动用于本任务，判定不通过。
- 若主线边界仍含糊，判定不通过。
- 若验证命令无法运行，说明原因并判定为 blocked。

