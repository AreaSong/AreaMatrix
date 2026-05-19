# Verify-ready: P1 repo-local 只读 hooks guardrail

本次是只读验收，禁止修改文件。

## 验收目标

确认 hooks 方案满足：

- 只读或通知，不自动修改文件。
- 不启动/停止 task-loop。
- 不提交/推送 Git。
- 明确 hooks 是 guardrail，不是完整验收系统。
- 明确 live runner、dirty worktree、高风险路径和验证缺口的提醒策略。
- 未依赖 under-development plugin hooks 作为关键门禁。

## 只读检查

```bash
git diff --name-only
rg -n "hooks|hook|只读|guardrail|dirty worktree|live runner|checkpoint|plugin_hooks|回滚" .codex .ai-governance tasks/backlog
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex tasks/backlog
```

如果存在 `.codex/hooks.json`，只读查看它，确认没有破坏性命令。

## 判定

若 hook 会自动改文件、启动 runner、提交、推送或绕过人工确认，判定不通过。

