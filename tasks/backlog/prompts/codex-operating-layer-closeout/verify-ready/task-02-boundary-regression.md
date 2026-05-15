# Verify-ready: Boundary Regression

本次是只读验收，禁止修改文件。

## 验收目标

确认边界回归结论可信：

- Source-of-truth 污染检查有证据。
- Execution 污染检查有证据。
- State 污染检查有证据。
- Skill 污染检查有证据。
- 未修改 `tasks/prompts/**`、progress、runner state 或 checkpoint。

## 必须读取

1. `AGENTS.md`
2. `tasks/prompts/README.md`
3. `tasks/backlog/README.md`
4. `workflow/AGENTS.md`
5. `.ai-governance/workflows/prompt-task-runtime.md`
6. `.ai-governance/workflows/external-capability-admission.md`
7. `.ai-governance/workflows/subagent-boundaries.md`
8. `.codex/skills-src/README.md`
9. `scripts/dev_tools/backlog.py`
10. `scripts/dev_tools/test_backlog_tools.py`

## 只读检查

```bash
git diff --name-only
git diff --cached --name-only
git diff --stat -- tasks/prompts tasks/prompts/_shared/progress.json .codex/task-loop-logs .codex/task-loop-runs
rg -n "Vibe|Automations|Cloud|Worktrees|hooks|subagent|progress|tasks/prompts|checkpoint|runner|source of truth|源事实" .ai-governance .codex tasks/backlog scripts/dev_tools scripts/task_loop
./dev backlog list
./dev backlog show dev-backlog-tooling --task 1 --mode verify
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- .ai-governance .codex tasks/backlog scripts/dev_tools scripts/task_loop
```

## 判定

若任一污染类型没有明确证据，判定不通过。
若发现 backlog 或 dev tooling 写 live state，判定不通过。
若 `tasks/prompts/**` 因本轮工作被修改，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
