# Verify-ready: Code Review + Security Threat Model 吸收

本次是只读验收，禁止修改文件。

## 验收目标

确认 review / security 补强满足：

- review 规则要求 findings first。
- review 优先 correctness、regression risk、missing tests、安全/隐私/用户文件风险。
- threat model checklist 覆盖资产、信任边界、入口、攻击能力、abuse path、缓解措施和 residual risk。
- 没有新增重复 `code-reviewer` 或 `security-threat-model` repo-local skill。
- 用户文件、DB、staging、iCloud/FSEvents、隐私、远程 AI 调用仍按高风险边界处理。
- 未修改 `tasks/prompts/**` 和 Vibe-Skills 仓库。

## 只读检查

```bash
git diff --name-only
rg -n "findings|review|correctness|regression|missing tests|security|threat|asset|trust boundary|abuse|residual risk|用户文件|隐私|iCloud|FSEvents|远程" CODE_REVIEW.md SECURITY.md .ai-governance .codex/references .codex/skills-src tasks/backlog
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- CODE_REVIEW.md SECURITY.md .ai-governance .codex/references .codex/skills-src tasks/backlog
```

## 判定

若 threat model 可以隐式绕过高风险确认，或 review 不再 findings first，判定不通过。
