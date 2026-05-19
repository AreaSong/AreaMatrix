# Verify-ready: Automations / Cloud / Worktrees Gate

本次是只读验收，禁止修改文件。

## 验收目标

确认 Automations / Cloud / Worktrees 只形成门禁，不接管主线：

- 没有创建 automation。
- 没有启用 cloud runtime。
- 没有创建 worktree。
- 明确三者不得写 live queue、progress、logs、checkpoint。
- 明确三者必须走 external capability admission。

## 必须读取

1. `.ai-governance/workflows/external-capability-admission.md`
2. `.ai-governance/workflows/prompt-task-runtime.md`
3. `tasks/backlog/README.md`
4. `.codex/references/codex-workflow-and-tools.md`
5. 新增或修改的 advanced gate 文件
6. `tasks/backlog/prompts/codex-advanced-noninvasive-layer/README.md`

## 只读检查

```bash
git diff --name-only
rg -n "Automation|Automations|Cloud|Worktree|worktrees|admission|progress|tasks/prompts|checkpoint|runner|canonical runtime|禁写|门禁" .ai-governance .codex tasks/backlog
git worktree list
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references .codex/skills-src tasks/backlog
```

## 判定

若发现实际创建 automation、cloud run 或 worktree，判定不通过。
若门禁允许这些能力写 live state 或替代 `./task-loop`，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
