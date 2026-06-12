# Copy-ready: Operating Layer Inventory

你在 `.` 工作。本任务是 Codex / AreaMatrix 工作层总收口的第一步：盘点现有能力，不新增能力。

## 目标

产出一份简短、可维护的工作层 inventory，回答：

- 当前有哪些 `.ai-governance/**` 规则参与 Codex 工作层？
- 当前有哪些 `.codex/references/**` runbook / checklist？
- 当前有哪些 AreaMatrix repo-local skills？
- 当前有哪些 `tasks/backlog/prompts/**` prompt package？
- `./dev backlog list/show` 是否已经成为只读浏览入口？
- 哪些能力是已吸收，哪些只是候选/暂缓？

## 非目标

- 不实现新功能。
- 不新增 skill。
- 不安装或启用 Vibe-Skills。
- 不修改 `tasks/prompts/**`。
- 不写 progress、runner state、checkpoint 或 run summary。

## Source of Truth

- Product behavior: `docs/**`
- Governance behavior: `.ai-governance/**`
- Codex operating material: `.codex/references/**` and `.codex/skills-src/**`
- Live queue: `tasks/prompts/**`
- Backlog planning: `tasks/backlog/**`
- Workflow planning: `workflow/**`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Supporting owners: `areamatrix-doc-sync` and `areamatrix-validation-driver`
- Landing: `tasks/backlog/codex-native-area-vibe-optimization.md` or a new concise closeout reference under `tasks/backlog/**`

## 先读

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `tasks/backlog/codex-native-area-vibe-optimization.md`
4. `tasks/backlog/prompts/codex-native-area-vibe-optimization/README.md`
5. `tasks/backlog/prompts/vibe-skills-absorption/README.md`
6. `tasks/backlog/prompts/dev-backlog-tooling/README.md`
7. `.ai-governance/README.md`
8. `.ai-governance/workflows/external-capability-admission.md`
9. `.ai-governance/workflows/prompt-task-runtime.md`
10. `.ai-governance/workflows/subagent-boundaries.md`
11. `.codex/references/index.md`
12. `.codex/skills-src/README.md`

## 允许修改

- `tasks/backlog/**`
- `.codex/references/index.md` only if inventory reveals missing navigation

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `../Vibe-Skills/**`
- task-loop runtime state directories

## 执行要求

1. 盘点 `.ai-governance/**`、`.codex/references/**`、`.codex/skills-src/**`、`tasks/backlog/prompts/**`。
2. 用表格记录每个能力的 source of truth、owner、状态和是否影响 live mainline。
3. 明确 `.codex/**` 不是产品语义源事实；Vibe-Skills 是候选能力池；`tasks/backlog/**` 是 planning/backlog。
4. 若发现索引缺失，只补导航，不新增大段重复说明。
5. 不扩大到产品代码或 live queue。

## Rollback / Blocked

- 若发现 inventory 需要修改 `tasks/prompts/**` 才能成立，停止并标记 blocked。
- 若发现某能力已经污染 live queue 或 progress，只记录证据和风险，不在本任务修复。
- 若 `./dev backlog` 不可用，记录为 inventory gap，后续回到 dev-backlog-tooling 修复。

## 验证

```bash
./dev backlog list
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog .codex/references
```

汇报时说明盘点范围、发现的 gap、验证结果和未触碰 `tasks/prompts/**`。
