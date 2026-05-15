# Copy-ready: P1 AreaMatrix repo-local skills 强化

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务强化现有 AreaMatrix repo-local skills，不创建重复 skill。

## 目标

审查现有 7 个 repo-local skills：

- `areamatrix-task-loop`
- `areamatrix-validation-driver`
- `areamatrix-doc-sync`
- `areamatrix-file-safety`
- `areamatrix-git-checkpoint`
- `areamatrix-workflow-planning`
- `areamatrix-enterprise-governance`

补齐触发条件、边界、互相引用或参考文档索引中的明显缺口。

## 先读

1. `AGENTS.md`
2. `.codex/skills-src/README.md`
3. `.codex/references/index.md`
4. `.codex/references/codex-workflow-and-tools.md`
5. `tasks/backlog/codex-native-area-vibe-optimization.md`
6. 每个 `.codex/skills-src/<skill>/SKILL.md`

## 允许修改

- `.codex/skills-src/**`
- `.agents/skills/**` 仅在它是 repo-local skill 发现入口且需要同步时
- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- 新增重复 skill 来覆盖现有 skill
- 改变产品语义 source of truth

## 执行要求

1. 先列出现有 skill owner 和明显缺口。
2. 优先小步补现有 skill，不新增 skill。
3. 如补充交叉引用，避免循环长链和重复规则。
4. 保持 `.codex/` 只是 Codex 运行材料，不是产品语义源事实。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/skills-src .agents/skills .codex/references tasks/backlog
```

