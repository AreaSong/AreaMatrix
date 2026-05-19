# Copy-ready: P0 外部能力接入门禁

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务为外部 skills / workflow 接入建立 admission gate。

## 目标

建立一套轻量但明确的接入判定规则，用于判断 Vibe-Skills 或其他外部能力是否可以进入 AreaMatrix。

接入规则必须回答：

- 解决什么 AreaMatrix 缺口？
- 是否与现有 AreaMatrix skill / rule / workflow 重复？
- source of truth 是谁？
- 触发条件是什么？
- 是否影响 `./task-loop`、`tasks/prompts/**` 或用户文件安全？
- 验证方式是什么？
- owner / 落点在哪里？
- 是吸收、暂缓、只参考，还是拒绝？

## 先读

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `.codex/references/codex-workflow-and-tools.md`
4. `tasks/backlog/codex-native-area-vibe-optimization.md`
5. `/Users/as/Ai-Project/project/Vibe-Skills/docs/install/custom-skill-governance-rules.md`
6. `/Users/as/Ai-Project/project/Vibe-Skills/references/skill-distillation-rules.md` 如存在
7. OpenAI Codex 官方 customization / migrate / skills 文档，优先用 OpenAI Docs MCP 核对当前说法

## 允许修改

- `.ai-governance/**`
- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`
- 全局 `~/.codex/**`

## 执行要求

1. 新增或补充一个 admission gate 表格。
2. 明确“目录存在不等于启用”。
3. 明确“外部 runtime 不得成为 AreaMatrix canonical runtime”。
4. 明确候选能力的四类结论：吸收、暂缓、只参考、拒绝。
5. 若创建新文档，要在相关 index 或主参考文档中链接。

## 验证

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

