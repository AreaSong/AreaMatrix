# Copy-ready: Verification Before Completion 吸收

你在 `.` 工作。本任务吸收 `verification-before-completion` 的完成声明证据纪律。

## 目标

补强 AreaMatrix “完成前证据 checklist”，确保任何任务在声称完成、修复、通过、可提交、可合并、可交付前，必须说明：

- 改了什么
- 为什么这样改
- 跑了哪些验证
- 验证是否是新鲜结果
- 哪些检查没跑，原因是什么
- 剩余风险是什么
- 是否有 review / security / dependency / CI / Git evidence blocker

## 先读

1. `AGENTS.md`
2. `.ai-governance/core/agent-principles.md`
3. `.codex/skills-src/areamatrix-validation-driver/SKILL.md`
4. `.codex/skills-src/areamatrix-validation-driver/references/validation-matrix.md`
5. `.codex/references/vibe-skills-capability-screening.md`
6. `../Vibe-Skills/bundled/skills/verification-before-completion/SKILL.md`

## 允许修改

- `.ai-governance/**`
- `.codex/references/**`
- `.codex/skills-src/areamatrix-validation-driver/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `../Vibe-Skills/**`

## 执行要求

1. 新增或补充 completion evidence checklist。
2. 明确 dry-run 不能替代真实执行证据。
3. 明确没有验证不能宣称完成。
4. 明确 review/security/dependency/CI/Git blockers 会让 PASS 降级为 blocked 或 not-ready。
5. 如新增 `.codex/references/*.md`，更新 `.codex/references/index.md`。
6. 不新增重复 skill；优先补 validation-driver 和 governance 规则。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references .codex/skills-src tasks/backlog
```
