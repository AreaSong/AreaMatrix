# Copy-ready: Boundary Regression

你在 `.` 工作。本任务做边界回归核对，确认前三批优化和 `./dev backlog` 没有污染 AreaMatrix 主线。

## 目标

用证据核对四类污染都没有发生：

1. Source-of-truth 污染：`.codex/**`、Vibe-Skills 或 backlog 文档替代 `docs/**` / `.ai-governance/**`。
2. Execution 污染：外部 runtime、hooks、automation、subagent 或第二套 runner 接管 `./dev + ./task-loop + tasks/prompts/**`。
3. State 污染：backlog、workflow preview 或 dev tooling 写 live queue、progress、logs、run summaries、runner lock、checkpoint。
4. Skill 污染：重复 skill 或外部 skill 绕过 repo-local owner 和 admission gate。

## 非目标

- 不修复产品功能。
- 不新增工具。
- 不修改 live queue。
- 不运行真实 task-loop。
- 不安装或启用外部能力。

## Source of Truth

- Mainline boundary: `AGENTS.md`、`tasks/prompts/README.md`、`.ai-governance/workflows/prompt-task-runtime.md`
- Backlog boundary: `tasks/backlog/README.md`
- Workflow boundary: `workflow/AGENTS.md`、`workflow/README.md`
- External admission: `.ai-governance/workflows/external-capability-admission.md`
- Subagent boundary: `.ai-governance/workflows/subagent-boundaries.md`
- Skill owner map: `.codex/skills-src/README.md`

## Owner / Landing

- Owner: `areamatrix-validation-driver`
- Supporting owners: `areamatrix-workflow-planning`、`areamatrix-task-loop`、`areamatrix-doc-sync`
- Landing: `tasks/backlog/**` only if a concise regression note is needed

## 先读

1. `AGENTS.md`
2. `tasks/prompts/README.md`
3. `tasks/backlog/README.md`
4. `workflow/AGENTS.md`
5. `workflow/README.md`
6. `.ai-governance/workflows/prompt-task-runtime.md`
7. `.ai-governance/workflows/external-capability-admission.md`
8. `.ai-governance/workflows/subagent-boundaries.md`
9. `.codex/skills-src/README.md`
10. `.codex/references/codex-workflow-and-tools.md`
11. `.codex/references/vibe-skills-capability-screening.md`
12. `scripts/dev_tools/backlog.py`
13. `scripts/dev_tools/test_backlog_tools.py`

## 允许修改

- `tasks/backlog/**`
- `.codex/references/**` only if an existing closeout/index note is missing

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `../Vibe-Skills/**`
- task-loop runtime state directories

## 执行要求

1. 记录当前 `git diff --name-only` 和 `git diff --cached --name-only`，确认是否有 staged 实现文件；不要回退或改动它们。
2. grep 核对 `tasks/backlog/**`、`.codex/**`、`.ai-governance/**` 是否存在把外部能力写成主线的表述。
3. grep 核对 backlog/dev tooling 是否写 `tasks/prompts/**`、`progress.json`、logs、run summaries、lock 或 checkpoint。
4. 运行只读/自检命令，不启动真实 runner。
5. 若发现污染风险，写成 findings 表格：污染类型、证据路径、影响、建议后续任务；不要在本任务直接大改。

## Rollback / Blocked

- 若发现 live queue 或 progress 已被写入，停止并标记 blocked，保留证据。
- 若 `./dev backlog` 命令运行产生新文件或状态变化，停止并标记 blocked。
- 若验证失败，按 source-of-truth / execution / state / skill 分类归因。

## 验证

```bash
git diff --name-only
git diff --cached --name-only
rg -n "Vibe|Automations|Cloud|Worktrees|hooks|subagent|progress|tasks/prompts|checkpoint|runner|source of truth|源事实" .ai-governance .codex tasks/backlog scripts/dev_tools scripts/task_loop
./dev backlog list
./dev backlog show dev-backlog-tooling --task 1 --mode verify
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- .ai-governance .codex tasks/backlog scripts/dev_tools scripts/task_loop
```

汇报时明确四类污染分别是 PASS / FAIL / BLOCKED，并说明证据路径。
