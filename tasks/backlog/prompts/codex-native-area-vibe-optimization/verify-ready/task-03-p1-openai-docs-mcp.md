# Verify-ready: P1 OpenAI Docs MCP 规则

本次是只读验收，禁止修改文件。

## 验收目标

确认规则已经说明：

- OpenAI/Codex/API/model 最新判断必须优先查官方文档或 OpenAI Docs MCP。
- OpenAI 官方 docs 不替代 AreaMatrix 产品 `docs/`。
- 不把旧记忆或旧本地文档当作“最新”事实。
- 不保存或要求用户提供 API key/token。

## 只读检查

```bash
git diff --name-only
rg -n "OpenAI|Codex|官方|最新|MCP|openaiDeveloperDocs|source of truth|源事实" .ai-governance .codex/references tasks/backlog
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

## 判定

如果规则把 OpenAI docs 写成 AreaMatrix 产品行为源事实，判定不通过。

