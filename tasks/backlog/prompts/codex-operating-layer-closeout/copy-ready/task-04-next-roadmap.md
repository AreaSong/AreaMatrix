# Copy-ready: Next Roadmap Decision

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务给出下一阶段路线建议，不直接执行路线。

## 目标

在总收口完成后，给出清晰路线判断：

- 是否可以把当前 Codex / AreaMatrix 工作层视为稳定基线。
- 是否应该回到 AreaMatrix 产品主线开发。
- 哪些高级治理增强可以暂缓。
- 哪些情况才需要继续吸收 Vibe-Skills 专业领域 skill。
- hooks、Automations、Cloud、Worktrees、Browser/Chrome、Computer Use、subagents 的后续优先级如何。

## 非目标

- 不实现 hooks。
- 不创建 automation。
- 不安装 Vibe-Skills。
- 不修改 live queue。
- 不启动 task-loop。
- 不写产品代码。

## Source of Truth

- Closeout inventory / boundary regression / playbook results
- `tasks/backlog/codex-native-area-vibe-optimization.md`
- `tasks/backlog/README.md`
- `.codex/references/vibe-skills-capability-screening.md`
- `.codex/references/hooks-guardrail-runbook.md`
- `.codex/references/computer-use-macos-ui-smoke-runbook.md`
- `.ai-governance/workflows/external-capability-admission.md`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Landing: `tasks/backlog/codex-native-area-vibe-optimization.md` or a concise roadmap note under `tasks/backlog/**`

## 先读

1. `tasks/backlog/README.md`
2. `tasks/backlog/codex-native-area-vibe-optimization.md`
3. `tasks/backlog/prompts/codex-operating-layer-closeout/README.md`
4. `.codex/references/vibe-skills-capability-screening.md`
5. `.codex/references/hooks-guardrail-runbook.md`
6. `.codex/references/computer-use-macos-ui-smoke-runbook.md`
7. `.ai-governance/workflows/external-capability-admission.md`
8. `.ai-governance/workflows/prompt-task-runtime.md`

## 允许修改

- `tasks/backlog/**`
- `.codex/references/**` only if a roadmap link or short note is needed

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`
- task-loop runtime state directories

## 执行要求

1. 给出路线表：
   - Recommended now
   - Defer
   - Trigger-based only
   - Reject / do not adopt
2. 默认推荐应优先回到 AreaMatrix 产品主线，除非 closeout 发现 blocker。
3. 对 hooks / Automations / Cloud / Worktrees / Browser / Computer Use / subagents / Vibe professional skills 分别写触发条件和门禁。
4. 明确后续任何外部能力都必须通过 external capability admission gate。
5. 不把 roadmap 当作批准执行的 live task。

## Rollback / Blocked

- 若 closeout 前三步未完成或有 blocker，不给出“稳定基线”结论。
- 若发现主线污染，roadmap 第一项应是污染修复，而不是回产品开发。
- 若需要修改 live queue 才能表达路线，停止并标记 blocked。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog .codex/references
```

汇报时说明推荐路线、暂缓项、触发项和是否可以回到产品主线。
