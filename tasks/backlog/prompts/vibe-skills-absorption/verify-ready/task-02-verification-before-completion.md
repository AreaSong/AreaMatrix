# Verify-ready: Verification Before Completion 吸收

本次是只读验收，禁止修改文件。

## 验收目标

确认 AreaMatrix 已有完成前证据 checklist，并满足：

- 没有验证不能宣称完成。
- 完成汇报必须包含改动、原因、验证、未验证项、剩余风险。
- dry-run 不能替代真实验证。
- review / security / dependency / CI / Git evidence blockers 会影响最终结论。
- 未新增重复 skill。
- 未修改 `tasks/prompts/**` 和 Vibe-Skills 仓库。

## 只读检查

```bash
git diff --name-only
rg -n "完成|completion|evidence|证据|验证|dry-run|blocked|review|security|dependency|CI|Git" .ai-governance .codex/references .codex/skills-src tasks/backlog
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references .codex/skills-src tasks/backlog
```

## 判定

若 checklist 允许未验证时宣称完成，判定不通过。
