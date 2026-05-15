# Copy-ready: Systematic Debugging 吸收

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务只吸收 Vibe-Skills 的 `systematic-debugging` 方法价值，不安装、不复制外部仓库。

## 目标

为 AreaMatrix 增加调试 / 失败归因 runbook，使后续遇到失败时能区分：

- copy 阶段失败
- verify 阶段失败
- validation command 失败
- task-loop runner 失败
- Git checkpoint / dirty worktree 失败
- docs / API / UDL / prompt manifest 漂移
- 用户文件 / DB / staging / iCloud / FSEvents 高风险边界失败

核心原则：原因不明时先复现、收证、分层归因，再修复；不要直接猜。

## 先读

1. `AGENTS.md`
2. `.ai-governance/core/agent-principles.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `.codex/skills-src/areamatrix-validation-driver/SKILL.md`
5. `.codex/skills-src/areamatrix-task-loop/SKILL.md`
6. `.codex/references/vibe-skills-capability-screening.md`
7. `/Users/as/Ai-Project/project/Vibe-Skills/bundled/skills/systematic-debugging/SKILL.md`

## 允许修改

- `.ai-governance/**`
- `.codex/references/**`
- `.codex/skills-src/areamatrix-validation-driver/**`
- `.codex/skills-src/areamatrix-task-loop/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`
- task-loop progress、run summaries、live logs

## 执行要求

1. 新增或补充 AreaMatrix debugging / failure attribution runbook。
2. 明确“先复现、收证、假设、缩小范围、再修复”的流程。
3. 明确 task-loop 失败归因字段和查看顺序。
4. 明确何时调用 validation-driver、task-loop、git-checkpoint、doc-sync、file-safety 等 repo-local skills。
5. 如新增 `.codex/references/*.md`，更新 `.codex/references/index.md`。
6. 不新增 `systematic-debugging` 同名 repo-local skill；优先补现有 owner。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references .codex/skills-src tasks/backlog
```
