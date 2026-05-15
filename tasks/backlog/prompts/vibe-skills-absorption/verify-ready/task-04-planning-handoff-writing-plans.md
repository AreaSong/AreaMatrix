# Verify-ready: Writing Plans / Planning Handoff 吸收

本次是只读验收，禁止修改文件。

## 验收目标

确认 planning handoff 补强满足：

- 计划或 prompt 包要求目标、非目标、精确路径、source of truth、owner、步骤、验证命令、blocked / rollback 口径。
- copy-ready 与 verify-ready 分离。
- backlog prompt 不进入 `tasks/prompts/**`，不写 progress。
- `areamatrix-workflow-planning` 是 owner；没有新增重复 `writing-plans` skill。
- 未修改 Vibe-Skills 仓库。
- workflow promotion 前不会写 live queue、checkpoint、run summary、runner lock 或 `tasks/prompts/_shared/progress.json`。

## 必须读取

1. `AGENTS.md`
2. `workflow/AGENTS.md`
3. `workflow/README.md`
4. `.codex/skills-src/areamatrix-workflow-planning/SKILL.md`
5. `.codex/references/planning-handoff-runbook.md`
6. `tasks/backlog/README.md`
7. `tasks/backlog/codex-native-area-vibe-optimization.md`
8. `.codex/references/vibe-skills-capability-screening.md`

## 只读检查

```bash
git diff --name-only
rg -n "planning|计划|handoff|copy-ready|verify-ready|source of truth|owner|验证命令|rollback|blocked|tasks/prompts|progress" workflow .codex/references .codex/skills-src tasks/backlog
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./dev workflow doctor
git diff --check -- workflow .codex/references .codex/skills-src tasks/backlog
```

## 判定

若 planning 产物可以绕过 `workflow/` gate 直接进入 live `tasks/prompts/**`，判定不通过。
若 verify-ready prompt 要求边验边修，或 copy-ready / verify-ready 合并成一个 prompt，判定不通过。
若缺少精确路径、验证命令、owner / landing 或 blocked / rollback 口径，判定不通过。
