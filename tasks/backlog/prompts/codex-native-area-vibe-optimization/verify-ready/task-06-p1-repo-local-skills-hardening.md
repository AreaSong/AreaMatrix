# Verify-ready: P1 AreaMatrix repo-local skills 强化

本次是只读验收，禁止修改文件。

## 验收目标

确认执行结果：

- 没有新增重复 skill。
- 现有 7 个 repo-local skills 的触发条件、边界或引用更清晰。
- `.codex/` 没有被写成产品 source of truth。
- `.agents/skills/**` 如有变更，与 `.codex/skills-src/**` 的源事实关系一致。
- 未修改 `tasks/prompts/**`。

## 只读检查

```bash
git diff --name-only
find .codex/skills-src -maxdepth 2 -name SKILL.md | sort
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/skills-src .agents/skills .codex/references tasks/backlog
```

## 判定

若新增 skill 只是重命名现有能力，或让 `.codex/` 反客为主，判定不通过。

