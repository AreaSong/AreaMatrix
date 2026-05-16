# Verify-ready: Hooks Warn-only / Read-only Gate

本次是只读验收，禁止修改文件。

## 验收目标

确认 hooks 方案没有污染主线：

- 只允许 warn-only / read-only guardrail。
- 未启用 plugin hooks。
- 未新增自动改文件、启动/停止 runner、commit、push、reset、clean、stash 的 hook。
- hooks 没有被写成完整验收系统。
- rollback / disable 方式清楚。

## 必须读取

1. `.codex/references/hooks-guardrail-runbook.md`
2. `.ai-governance/workflows/prompt-task-runtime.md`
3. `tasks/backlog/README.md`
4. `.codex/hooks.json` if present
5. `tasks/backlog/prompts/codex-advanced-noninvasive-layer/README.md`

## 只读检查

```bash
git diff --name-only
rg -n "hooks|plugin_hooks|warn-only|read-only|runner|task-loop|commit|push|reset|clean|stash|progress|checkpoint|VERIFY_RESULT|验证" .codex .ai-governance tasks/backlog
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references .codex/hooks.json tasks/backlog
```

## 判定

若 hooks 会自动写文件、控制 runner、控制 Git 或替代 verify-ready，判定不通过。
若启用了 plugin hooks 或缺少 rollback 口径，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
