# Verify-ready: Systematic Debugging 吸收

本次是只读验收，禁止修改文件。

## 验收目标

确认 AreaMatrix 已吸收 `systematic-debugging` 的方法价值，并满足：

- 有调试 / 失败归因 runbook 或等价规则。
- 明确原因不明时先复现和收证，不直接猜测修复。
- 能区分 copy / verify / validation / runner / checkpoint / docs drift / file safety 等失败层。
- 使用现有 AreaMatrix skill owner，不新增重复 `systematic-debugging` skill。
- 未修改 `tasks/prompts/**`。
- 未修改 Vibe-Skills 仓库。

## 只读检查

```bash
git diff --name-only
rg -n "debug|调试|失败归因|root cause|复现|收证|copy|verify|checkpoint|dirty worktree|doc-sync|file-safety" .ai-governance .codex/references .codex/skills-src tasks/backlog
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references .codex/skills-src tasks/backlog
```

## 判定

若只是提到 debugging 名字但没有失败分层和证据顺序，判定不通过。
