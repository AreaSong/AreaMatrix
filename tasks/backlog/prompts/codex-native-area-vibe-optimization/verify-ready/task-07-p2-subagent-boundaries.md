# Verify-ready: P2 Subagent 使用边界

本次是只读验收，禁止修改文件。

## 验收目标

确认 subagent 规则已经说明：

- 只读审计可并行，但要问题明确。
- 写入实现必须拆分 disjoint write set。
- 不允许多个 writer 同时碰同一 live task 或同一文件 ownership。
- subagent 不得直接推进 task-loop progress 或 checkpoint。
- 主 agent 仍需整合、复核、验证和最终结论。

## 只读检查

```bash
git diff --name-only
rg -n "subagent|agent|并行|只读|write set|owner|ownership|task-loop|checkpoint|progress" .ai-governance .codex/references tasks/backlog
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

## 判定

若规则允许 subagent 绕过主线、验证或文件 ownership，判定不通过。

