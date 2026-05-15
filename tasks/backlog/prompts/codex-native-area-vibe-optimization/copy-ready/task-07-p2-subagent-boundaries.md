# Copy-ready: P2 Subagent 使用边界

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务定义 subagent 使用边界。

## 目标

建立 AreaMatrix 中 Codex subagents 的使用规则，尤其是：

- 什么时候可以并行只读审计。
- 什么时候可以并行实现。
- 写入任务如何拆分 disjoint write set。
- 什么时候禁止 subagent 触碰 live task-loop、progress、checkpoint、用户文件高风险边界。
- 子 agent 结果如何被主 agent 复核和整合。

## 先读

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `.codex/references/codex-workflow-and-tools.md`
4. `tasks/backlog/codex-native-area-vibe-optimization.md`
5. OpenAI Codex Subagents 官方文档，优先用 OpenAI Docs MCP 核对当前能力
6. `/Users/as/Ai-Project/project/Vibe-Skills/references/subagent-role-taxonomy.md` 如存在

## 允许修改

- `.ai-governance/**`
- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- task-loop progress / logs / run summaries

## 执行要求

1. 新增或补充 subagent 使用边界。
2. 明确“只读探索”和“写入实现”的不同要求。
3. 明确 parallel write 必须有 disjoint write set 和 owner。
4. 明确 subagent 不得绕过主 agent 对验证和最终结论的责任。
5. 明确 live runner 运行时不把同一 live task 拆给多个 writer。

## 验证

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

