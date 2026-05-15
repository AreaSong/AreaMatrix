# Copy-ready: Code Review + Security Threat Model 吸收

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务用 Vibe-Skills 的 `code-reviewer` 和 `security-threat-model` 补强现有 AreaMatrix governance / file-safety。

## 目标

补强 AreaMatrix 的 review 和 security posture：

- code review 输出 findings first，优先 correctness、regression risk、missing tests、security / privacy / user-file risk。
- threat model 场景要说明资产、信任边界、入口、攻击能力、abuse path、缓解措施和 residual risk。
- 安全/威胁建模必须 explicit-only 或由高风险边界触发，不替代普通 review。
- 不新增 `code-reviewer` 或 `security-threat-model` 同义 repo-local skill；优先补 `areamatrix-enterprise-governance`、`areamatrix-file-safety` 和相关 references。

## 先读

1. `AGENTS.md`
2. `CODE_REVIEW.md`
3. `SECURITY.md`
4. `.codex/skills-src/areamatrix-enterprise-governance/SKILL.md`
5. `.codex/skills-src/areamatrix-file-safety/SKILL.md`
6. `.codex/references/vibe-skills-capability-screening.md`
7. `/Users/as/Ai-Project/project/Vibe-Skills/bundled/skills/code-reviewer/SKILL.md`
8. `/Users/as/Ai-Project/project/Vibe-Skills/bundled/skills/security-threat-model/SKILL.md`

## 允许修改

- `CODE_REVIEW.md`
- `SECURITY.md`
- `.ai-governance/**`
- `.codex/references/**`
- `.codex/skills-src/areamatrix-enterprise-governance/**`
- `.codex/skills-src/areamatrix-file-safety/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`

## 执行要求

1. 补强 review 输出格式或 skill trigger，保持 findings first。
2. 补强 threat model checklist，覆盖资产、边界、入口、攻击路径、缓解措施和残余风险。
3. 明确用户文件、DB、staging、iCloud/FSEvents、隐私、远程 AI 调用是高风险重点。
4. 保持 security review 与 file-safety 的 owner 边界清楚。
5. 如新增 `.codex/references/*.md`，更新 `.codex/references/index.md`。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- CODE_REVIEW.md SECURITY.md .ai-governance .codex/references .codex/skills-src tasks/backlog
```
