# Verify-ready: Next Roadmap Decision

本次是只读验收，禁止修改文件。

## 验收目标

确认 roadmap 不是新的执行入口，而是后续决策记录：

- 明确是否可以把当前工作层视为稳定基线。
- 明确是否推荐回到 AreaMatrix 产品主线。
- 明确 hooks / Automations / Cloud / Worktrees / Browser / Computer Use / subagents / Vibe professional skills 的后续触发条件。
- 明确外部能力仍需 admission gate。
- 未修改 `tasks/prompts/**`、progress 或 runner state。

## 必须读取

1. `tasks/backlog/README.md`
2. `tasks/backlog/codex-native-area-vibe-optimization.md`
3. `tasks/backlog/prompts/codex-operating-layer-closeout/README.md`
4. `.codex/references/vibe-skills-capability-screening.md`
5. `.ai-governance/workflows/external-capability-admission.md`
6. `.ai-governance/workflows/prompt-task-runtime.md`

## 只读检查

```bash
git diff --name-only
rg -n "Recommended now|Defer|Trigger|Reject|hooks|Automations|Cloud|Worktrees|Browser|Computer Use|subagent|Vibe|admission|稳定基线|产品主线" tasks/backlog .codex/references
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog .codex/references
```

## 判定

若 roadmap 直接批准执行 live queue 或外部 runtime 接入，判定不通过。
若缺少触发条件或 admission gate 说明，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
