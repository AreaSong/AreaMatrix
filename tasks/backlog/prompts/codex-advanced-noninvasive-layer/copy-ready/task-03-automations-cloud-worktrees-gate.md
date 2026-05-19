# Copy-ready: Automations / Cloud / Worktrees Gate

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务补 Automations / Cloud / Worktrees 的禁写主线门禁，不创建 automation，不启用 Cloud，不切换工作树。

## 目标

把 Automations / Cloud / Worktrees 从“暂缓”推进到“有门禁、有触发条件”：

- Automations：只允许提醒、周期性检查、状态汇报类候选；不写 repo state。
- Cloud：暂不作为 AreaMatrix canonical runtime；仅作为未来隔离执行候选。
- Worktrees：可作为隔离实验方案；不作为 live queue 默认执行环境。
- 明确三者都不能写 `tasks/prompts/**`、progress、logs、checkpoint 或替代 `./task-loop`。

## 非目标

- 不创建或更新 Codex Automation。
- 不启用 Cloud task。
- 不创建 Git worktree。
- 不修改 live queue。
- 不运行 task-loop。

## Source of Truth

- OpenAI Codex Automations: `https://developers.openai.com/codex/app/automations`
- OpenAI Codex Cloud / web: `https://developers.openai.com/codex/cloud`
- OpenAI Codex Worktree support: `https://developers.openai.com/codex/app/features#worktree-support`
- AreaMatrix external admission: `.ai-governance/workflows/external-capability-admission.md`
- AreaMatrix task runtime: `.ai-governance/workflows/prompt-task-runtime.md`
- Backlog boundary: `tasks/backlog/README.md`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Supporting owners: `areamatrix-task-loop`, `areamatrix-git-checkpoint`, `areamatrix-file-safety`
- Landing: `.codex/references/codex-workflow-and-tools.md` or a concise advanced gate note under `.codex/references/**`
- Backlog landing: `tasks/backlog/**`

## 先读

1. `AGENTS.md`
2. `.ai-governance/workflows/external-capability-admission.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `tasks/backlog/README.md`
5. `.codex/references/codex-workflow-and-tools.md`
6. `.codex/skills-src/areamatrix-task-loop/SKILL.md`
7. `.codex/skills-src/areamatrix-git-checkpoint/SKILL.md`
8. `.codex/skills-src/areamatrix-file-safety/SKILL.md`
9. OpenAI Automations 官方文档
10. OpenAI Cloud / Worktree 官方文档

## 允许修改

- `.ai-governance/**` only if existing rule has a clear gap
- `.codex/references/**`
- `.codex/skills-src/**` only for reference links / trigger wording
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- task-loop runtime state directories
- `/Users/as/Ai-Project/project/Vibe-Skills/**`

## 执行要求

1. 写一张 Automations / Cloud / Worktrees 决策表：
   - Recommended / Trigger-based / Defer / Reject
   - 触发条件
   - 禁止写入
   - owner
   - validation
2. 明确 Automations 的 unattended 风险：默认 sandbox、后台运行、local mode 可修改正在编辑文件。
3. 明确 Cloud 改变执行环境，未来必须有 local env、凭证、隐私、diff apply 和 checkpoint 方案。
4. 明确 Worktrees 只能隔离实验或并行独立任务，不替代 `workflow/**` gate 和 live task labels。
5. 明确所有三者都必须先通过 external capability admission gate。

## Rollback / Blocked

- 若任务要求实际创建 automation / cloud / worktree，停止并要求单独确认。
- 若门禁会把 automation 变成第二 runner，判定设计失败。
- 若涉及真实用户文件或隐私，转 file-safety / Mission-Critical。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references .codex/skills-src tasks/backlog
```

汇报时说明三类能力的判断、门禁、未创建 automation / cloud / worktree、未触碰 `tasks/prompts/**`。
