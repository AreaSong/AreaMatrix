# Copy-ready: Writing Plans / Planning Handoff 吸收

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务吸收 Vibe-Skills `writing-plans` 的 handoff-safe planning 方法价值。

## 目标

补强 AreaMatrix planning / backlog prompt 产物质量，让未来计划和提示词具备：

- 明确目标和非目标
- 精确文件路径
- source of truth
- owner / landing
- 分步骤执行顺序
- 验证命令
- rollback / blocked 口径
- copy-ready / verify-ready 分离
- 不直接进入 `tasks/prompts/**`，除非经过 workflow promotion

## 非目标

- 不新增 `writing-plans` 同义 repo-local skill。
- 不安装、启用或修改 Vibe-Skills runtime。
- 不修改 `tasks/prompts/**` live queue。
- 不写 `tasks/prompts/_shared/progress.json`、checkpoint、run summary、runner lock 或 task-loop live logs。

## Source of Truth

- Workflow lifecycle: `workflow/AGENTS.md`、`workflow/README.md`
- Backlog boundary: `tasks/backlog/README.md`
- Skill owner: `.codex/skills-src/areamatrix-workflow-planning/SKILL.md`
- Capability screening: `.codex/references/vibe-skills-capability-screening.md`
- Upstream inspiration only: `/Users/as/Ai-Project/project/Vibe-Skills/bundled/skills/writing-plans/SKILL.md` 或 `core/skills/writing-plans/instruction.md`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Primary landing: `.codex/skills-src/areamatrix-workflow-planning/**`
- Supporting landing: `.codex/references/**`、`workflow/templates/**`、`tasks/backlog/**`

## 先读

1. `AGENTS.md`
2. `workflow/AGENTS.md`
3. `workflow/README.md`
4. `.codex/skills-src/areamatrix-workflow-planning/SKILL.md`
5. `tasks/backlog/README.md`
6. `tasks/backlog/codex-native-area-vibe-optimization.md`
7. `.codex/references/vibe-skills-capability-screening.md`
8. `/Users/as/Ai-Project/project/Vibe-Skills/bundled/skills/writing-plans/SKILL.md` 或 `core/skills/writing-plans/instruction.md` 如存在

## 允许修改

- `workflow/**` docs / templates only if needed
- `.codex/references/**`
- `.codex/skills-src/areamatrix-workflow-planning/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`

## 执行要求

1. 补强 planning handoff 规则或 backlog prompt 模板说明。
2. 明确 copy-ready 与 verify-ready 要分离。
3. 明确计划必须包含精确路径和验证命令。
4. 明确 backlog prompt 不进入 live queue，不写 progress。
5. 不新增 `writing-plans` 同义 skill；优先补 `areamatrix-workflow-planning`。
6. 明确 blocked / rollback 口径：缺 source of truth、精确路径、验证命令、owner 或 promotion approval 时保持 blocked / not-ready。
7. 若需要新增 reference，更新 `.codex/references/index.md`。

## 执行顺序

1. 读取所有“先读”文件并确认现有边界。
2. 对比 Vibe `writing-plans`，只抽取 handoff-safe planning 方法，不吸收 dedicated worktree、执行 skill handoff、自动 commit 或 Vibe runtime。
3. 补强 `areamatrix-workflow-planning` 触发、引用、workflow 和 guardrails。
4. 补强 workflow plan / draft / queue 模板，使目标、非目标、精确路径、验证命令和 rollback / blocked 成为显式字段。
5. 补强 backlog README 和本 prompt 包说明，确保 copy-ready / verify-ready 分离且 backlog 不写 progress。
6. 运行验证命令并汇报改动、原因、验证和未覆盖风险。

## Rollback / Blocked

- 若发现必须修改 `tasks/prompts/**` 才能满足目标，停止并标记 blocked。
- 若 Vibe-Skills 文件缺失，只记录为 upstream evidence unavailable，不阻塞 AreaMatrix 本地规则补强。
- 若验证失败，按失败命令归因；不要通过扩大到 core/apps 或 live queue 来绕过。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./dev workflow doctor
git diff --check -- workflow .codex/references .codex/skills-src tasks/backlog
```
