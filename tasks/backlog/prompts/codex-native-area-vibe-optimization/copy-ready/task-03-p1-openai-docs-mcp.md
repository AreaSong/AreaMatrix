# Copy-ready: P1 OpenAI Docs MCP 规则

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务固化 OpenAI 官方文档核对规则。

## 目标

当任务涉及 OpenAI / Codex / model / API / SDK / hooks / MCP / skills / plugins / Computer Use 等“可能变化”的信息时，AreaMatrix 协作规则应默认要求优先核对 OpenAI 官方文档或 OpenAI Docs MCP，而不是只靠记忆。

## 先读

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `.ai-governance/core/agent-principles.md`
4. `.codex/references/codex-workflow-and-tools.md`
5. `tasks/backlog/codex-native-area-vibe-optimization.md`
6. 当前 Codex `openai-docs` skill，如可用
7. OpenAI 官方 docs，优先使用 OpenAI Docs MCP

## 允许修改

- `.ai-governance/**`
- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- 任何凭证、token、auth 配置
- 全局 `~/.codex/**`

## 执行要求

1. 找到最合适的规则落点，优先放在 `.ai-governance`，再同步到 `.codex/references`。
2. 明确 OpenAI 官方文档只用于 OpenAI/Codex 运行层判断，不替代 AreaMatrix 产品 `docs/`。
3. 明确回答“最新”前需要重新核对官方文档。
4. 不写死易过期的模型、价格、地区、功能状态，除非同时标注核对日期和来源。

## 验证

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

