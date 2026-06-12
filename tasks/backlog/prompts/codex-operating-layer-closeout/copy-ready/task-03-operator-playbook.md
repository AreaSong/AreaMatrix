# Copy-ready: Operator Playbook

你在 `.` 工作。本任务把当前 Codex / AreaMatrix 工作层沉淀成一份短操作手册。

## 目标

写一份简短 playbook，说明以后日常怎么使用这套工作层：

- 什么时候查官方 OpenAI / Codex docs。
- 什么时候用 AreaMatrix repo-local skills。
- 什么时候用 `tasks/backlog/**` 和 `./dev backlog`。
- 什么时候进入 `workflow/**`。
- 什么时候回到 `tasks/prompts/**` 和 `./task-loop`。
- 遇到 Vibe-Skills / hooks / subagents / Computer Use / Automations 时怎么判断是否接入。
- 如何避免污染 source of truth、execution、state、skill owner。

## 非目标

- 不写长篇手册。
- 不新增能力。
- 不改变 runner。
- 不修改 `tasks/prompts/**`。
- 不执行 backlog prompt。

## Source of Truth

- `AGENTS.md`
- `tasks/backlog/README.md`
- `.ai-governance/workflows/prompt-task-runtime.md`
- `.ai-governance/workflows/external-capability-admission.md`
- `.codex/skills-src/README.md`
- `.codex/references/index.md`
- `.codex/references/codex-workflow-and-tools.md`
- `.codex/references/planning-handoff-runbook.md`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Landing: concise reference under `.codex/references/**` or `tasks/backlog/**`
- If adding `.codex/references/codex-operating-layer-playbook.md`, update `.codex/references/index.md`

## 先读

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `.ai-governance/workflows/external-capability-admission.md`
5. `.codex/skills-src/README.md`
6. `.codex/references/index.md`
7. `.codex/references/codex-workflow-and-tools.md`
8. `.codex/references/planning-handoff-runbook.md`
9. `.codex/references/completion-evidence-checklist.md`
10. `.codex/references/debugging-failure-attribution-runbook.md`

## 允许修改

- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `../Vibe-Skills/**`
- task-loop runtime state directories

## 执行要求

1. 手册保持短小，优先表格和决策树，不写大段重复背景。
2. 明确“默认顺序”：
   - 官方 OpenAI/Codex 变化性信息先核对官方 docs。
   - AreaMatrix 产品语义看 `docs/**`。
   - 治理和边界看 `.ai-governance/**`。
   - Codex 操作投影看 `.codex/references/**` 和 repo-local skills。
   - backlog 用 `./dev backlog` 浏览，不执行。
   - live execution 只从批准的 `tasks/prompts/**` 和 `./task-loop` 进入。
3. 明确四类污染的快速检查方式。
4. 不把 playbook 写成新的源事实；它只能索引和解释现有规则。

## Rollback / Blocked

- 若手册需要改变治理规则才能成立，停止并标记 blocked。
- 若发现现有规则互相矛盾，记录冲突，交给后续治理修复任务。
- 若 `.codex/references/index.md` 更新失败，修复导航后再验收。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

汇报时说明手册落点、覆盖的决策点、引用的源事实和未触碰 `tasks/prompts/**`。
